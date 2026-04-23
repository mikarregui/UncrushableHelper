local addonName, ns = ...

ns.state = {
    classFile = nil,
    snapshot = nil,
    activeBuffs = {},
    activeBuffsMeta = {},
    activeBuffsFingerprint = "",
    recalcScheduled = false,
}

local CHAT_PREFIX       = "|cff55ff55UH:|r "
local CHAT_PREFIX_WARN  = "|cffffcc55UH:|r "
local CHAT_PREFIX_ERROR = "|cffff5555UH:|r "

local function migrateSavedVariables()
    UncrushableHelperDB        = UncrushableHelperDB        or {}
    UncrushableHelperPerCharDB = UncrushableHelperPerCharDB or {}

    local db      = UncrushableHelperDB
    local perChar = UncrushableHelperPerCharDB

    db.global = db.global or {}
    if db.global.closeOnOutsideClick == nil then
        db.global.closeOnOutsideClick = false
    end
    -- v0.1.0-dev left an `enabledClasses` opt-out table here; it's no
    -- longer used since the addon now works for any class. The field is
    -- left in place if present (harmless) but not created fresh.

    perChar.minimap      = perChar.minimap      or {}
    perChar.mainFrame    = perChar.mainFrame    or { shown = false }
    perChar.plannedBuffs = perChar.plannedBuffs or {}
    if perChar.targetBossLevelDiff == nil then
        perChar.targetBossLevelDiff = 3  -- default: raid boss (+3)
    end

    db.schemaVersion      = 1
    perChar.schemaVersion = 1
end

-- Re-build the snapshot and fan it out to UI. Callers should hit us via
-- ns:RequestRecalc() so bursts of UNIT_AURA/COMBAT_RATING_UPDATE events
-- collapse to a single render per frame.
function ns:Publish()
    if not ns.calc or not ns.calc.ComputeSnapshot then return end

    local perChar = UncrushableHelperPerCharDB
    local snap = ns.calc:ComputeSnapshot({
        classFile     = ns.state.classFile,
        activeSet     = ns.state.activeBuffs,
        plannedSet    = perChar and perChar.plannedBuffs,
        bossLevelDiff = perChar and perChar.targetBossLevelDiff,
    })
    ns.state.snapshot = snap

    if ns.ui and ns.ui.OnSnapshotChanged then
        ns.ui:OnSnapshotChanged(snap)
    end
end

-- Coalesces a flurry of same-tick events into one Publish. A ~100 ms delay
-- (instead of next-frame 0) gives WoW time to finish propagating stat
-- updates after PLAYER_EQUIPMENT_CHANGED: the event fires *before* the
-- client recomputes GetDodgeChance/GetParryChance/GetBlockChance, so a 0-
-- delay recalc would read stale values on gear swaps. 100 ms is
-- imperceptible in play and lets UNIT_STATS/COMBAT_RATING_UPDATE settle.
function ns:RequestRecalc()
    if ns.state.recalcScheduled then return end
    ns.state.recalcScheduled = true
    C_Timer.After(0.1, function()
        ns.state.recalcScheduled = false
        ns:Publish()
    end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("COMBAT_RATING_UPDATE")
eventFrame:RegisterEvent("UNIT_STATS")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
-- TBC uses CHARACTER_POINTS_CHANGED for talent spends; PLAYER_TALENT_UPDATE
-- is a retail-era rename. Registering both keeps the addon forward-compatible
-- without forking the event frame, and the throttle de-dupes.
eventFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
if eventFrame.RegisterEvent then
    pcall(eventFrame.RegisterEvent, eventFrame, "PLAYER_TALENT_UPDATE")
end
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        migrateSavedVariables()
        ns.state.classFile = select(2, UnitClass("player"))
        UncrushableHelperPerCharDB.lastKnownClass = ns.state.classFile
        if ns.aura and ns.aura.RefreshActiveBuffs then
            ns.aura:RefreshActiveBuffs()
        end
        ns:RequestRecalc()
        print(CHAT_PREFIX .. "loaded (" .. tostring(ns.state.classFile) .. "). /uh debug for a snapshot.")
    elseif event == "UNIT_AURA" then
        if arg1 ~= "player" then return end
        local changed = true
        if ns.aura and ns.aura.RefreshActiveBuffs then
            changed = ns.aura:RefreshActiveBuffs()
        end
        if changed then ns:RequestRecalc() end
    elseif event == "PLAYER_ENTERING_WORLD"
        or event == "COMBAT_RATING_UPDATE"
        or event == "UNIT_STATS"
        or event == "PLAYER_EQUIPMENT_CHANGED"
        or event == "UPDATE_SHAPESHIFT_FORM"
        or event == "CHARACTER_POINTS_CHANGED"
        or event == "PLAYER_TALENT_UPDATE" then
        ns:RequestRecalc()
    end
end)

local function formatPct(v)
    return string.format("%.2f%%", v or 0)
end

local function printSnapshot()
    local snap = ns.state.snapshot
    if not snap then
        print(CHAT_PREFIX_WARN .. "no snapshot yet — try again after login finishes.")
        return
    end

    print(CHAT_PREFIX .. "snapshot (" .. (snap.classInfo and snap.classInfo.label or snap.classFile or "?") .. ")")
    print("  Target: +" .. tostring(snap.bossLevelDiff or 0) .. "  (penalty " .. formatPct(ns.PER_LEVEL_SHIFT * (snap.bossLevelDiff or 0)) .. " per component)")
    print("  Defense Skill: " .. tostring(snap.defenseSkill or 0))
    print("  Miss:  " .. formatPct(snap.miss))
    print("  Dodge: " .. formatPct(snap.dodge))
    print("  Parry: " .. formatPct(snap.parry))
    if snap.components.block.applicable then
        print("  Block: " .. formatPct(snap.block))
    elseif snap.mode == "druid-special" then
        print("  Block: n/a (druid — no block on attack table)")
    else
        print("  Block: n/a (no shield equipped)")
    end
    print("  Total: " .. formatPct(snap.total))

    if snap.mode == "block" then
        if snap.isUncrushable then
            print("  |cff33ff55UNCRUSHABLE|r (>= " .. formatPct(ns.TARGET_CAP) .. ")")
        else
            print("  |cffff5555CRUSHABLE|r — short by " .. formatPct(snap.shortBy or 0))
        end
    elseif snap.druidGoals then
        local defOk = snap.druidGoals.defenseOk and "|cff33ff55OK|r" or "|cffffcc55below goal|r"
        print(("  Druid goals: defense skill %d / %d  %s"):format(
            snap.defenseSkill, snap.druidGoals.defenseTarget, defOk))
        print("  Armor: " .. tostring(snap.druidGoals.armor or 0))
    else
        print("  |cffbbbb99Informational only|r — no shield, cap verdict not applicable.")
    end

    if ns.aura and ns.aura.ListTrackedForUI then
        local rows = ns.aura:ListTrackedForUI()
        if rows and #rows > 0 then
            print("  Tracked buffs:")
            for _, row in ipairs(rows) do
                local tag = row.active and "|cff33ff55ACTIVE|r"
                         or row.planned and "|cff5599ffplanned|r"
                         or "|cff777777none|r"
                print("    " .. tag .. " " .. row.label)
            end
        end
    end

    if snap.simulated and snap.simulated.delta and snap.simulated.delta.count > 0 then
        local s = snap.simulated
        print(("  With %d planned buffs: total %s  (+%s miss, +%s dodge, +%s parry, +%s block)"):format(
            s.delta.count, formatPct(s.total),
            formatPct(s.delta.miss), formatPct(s.delta.dodge),
            formatPct(s.delta.parry), formatPct(s.delta.block)))
        if snap.mode == "block" then
            if s.isUncrushable then
                print("  \194\183 projected |cff33ff55UNCRUSHABLE|r")
            else
                print("  \194\183 projected |cffff5555CRUSHABLE|r — still short by " .. formatPct(s.shortBy or 0))
            end
        end
    end

    for _, note in ipairs(snap.notes or {}) do
        print("  note: " .. note)
    end
end

SLASH_UNCRUSHABLEHELPER1 = "/uh"
SLASH_UNCRUSHABLEHELPER2 = "/uncrush"
SlashCmdList["UNCRUSHABLEHELPER"] = function(msg)
    local raw   = (msg or ""):match("^%s*(.-)%s*$") or ""
    local lower = raw:lower()

    if lower == "debug" then
        ns:RequestRecalc()
        -- RequestRecalc schedules for next tick; to give the user fresh
        -- numbers we also compute synchronously here before printing.
        ns:Publish()
        printSnapshot()
    elseif lower == "reset" then
        if UncrushableHelperPerCharDB and UncrushableHelperPerCharDB.mainFrame then
            UncrushableHelperPerCharDB.mainFrame.point = nil
        end
        if ns.ui and ns.ui.ResetPosition then ns.ui:ResetPosition() end
        print(CHAT_PREFIX .. "frame position reset.")
    elseif lower == "config" or lower == "settings" or lower == "options" then
        if ns.OpenSettings then
            ns:OpenSettings()
        else
            print(CHAT_PREFIX_WARN .. "settings panel not implemented yet.")
        end
    elseif lower == "show" then
        if ns.ShowMain then ns:ShowMain() else print(CHAT_PREFIX_WARN .. "UI not implemented yet.") end
    elseif lower == "hide" then
        if ns.HideMain then ns:HideMain() else print(CHAT_PREFIX_WARN .. "UI not implemented yet.") end
    elseif lower == "" or lower == "toggle" then
        if ns.ToggleMain then
            ns:ToggleMain()
        else
            print(CHAT_PREFIX_WARN .. "UI not implemented yet — try /uh debug for the raw snapshot.")
        end
    else
        print(CHAT_PREFIX .. "commands: /uh, /uh show, /uh hide, /uh toggle, /uh config, /uh debug, /uh reset")
    end
end
