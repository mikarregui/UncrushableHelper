local addonName, ns = ...

ns.ui = {}

local FRAME_WIDTH  = 300
local FRAME_HEIGHT = 494
local PADDING      = 14
local ROW_HEIGHT   = 20
local BUFF_ROW_H   = 22

local COLOR_GREEN       = { 0.20, 0.85, 0.30 }
local COLOR_RED         = { 0.90, 0.25, 0.25 }
local COLOR_GOLD        = { 0.85, 0.70, 0.30 }
local COLOR_GREY        = { 0.55, 0.55, 0.55 }
local COLOR_MUTED_LABEL = { 0.78, 0.78, 0.78 }

local function setColor(fs, rgb)
    fs:SetTextColor(rgb[1], rgb[2], rgb[3])
end

local function formatPct(v)
    return string.format("%.2f%%", v or 0)
end

local function shouldCatchOutsideClicks()
    local db = UncrushableHelperDB
    return db and db.global and db.global.closeOnOutsideClick == true
end

-- LibDataBroker + LibDBIcon trigger. Both libs are embedded in every
-- packaged build via embeds.xml, so we can assume LibStub is available.
local ldb  = LibStub and LibStub("LibDataBroker-1.1", true)
local icon = LibStub and LibStub("LibDBIcon-1.0", true)

local dataObject
if ldb then
    dataObject = ldb:NewDataObject("UncrushableHelper", {
        type = "launcher",
        text = "UH",
        icon = "Interface\\Icons\\Ability_Warrior_ShieldMastery",
        OnClick = function(_, btn)
            if btn == "RightButton" then
                if ns.OpenSettings then ns:OpenSettings() end
            else
                ns:ToggleMain()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("Uncrushable Helper")
            local snap = ns.state.snapshot
            if snap then
                if snap.mode == "block" then
                    local status = snap.isUncrushable and "|cff33ff55UNCRUSHABLE|r" or "|cffff5555CRUSHABLE|r"
                    tt:AddDoubleLine("Total", formatPct(snap.total), 1, 1, 1, 1, 1, 1)
                    tt:AddLine(status)
                elseif snap.druidGoals then
                    tt:AddDoubleLine("Defense", tostring(snap.defenseSkill), 1, 1, 1, 1, 1, 1)
                    tt:AddDoubleLine("Armor",   tostring(snap.druidGoals.armor), 1, 1, 1, 1, 1, 1)
                end
            end
            tt:AddLine("Left-click: open/close", 1, 1, 1)
            tt:AddLine("Right-click: settings",  1, 1, 1)
            tt:AddLine("/uh debug  ·  /uh reset", 0.7, 0.7, 0.7)
        end,
    })
end

local ldbRegisterFrame = CreateFrame("Frame")
ldbRegisterFrame:RegisterEvent("PLAYER_LOGIN")
ldbRegisterFrame:SetScript("OnEvent", function(self)
    UncrushableHelperPerCharDB = UncrushableHelperPerCharDB or {}
    UncrushableHelperPerCharDB.minimap = UncrushableHelperPerCharDB.minimap or {}
    if icon and dataObject then
        if not icon:IsRegistered("UncrushableHelper") then
            icon:Register("UncrushableHelper", dataObject, UncrushableHelperPerCharDB.minimap)
        end
    end
    self:UnregisterAllEvents()
end)

local mainFrame
local header, titleFS, closeBtn
local targetDropdown
local totalFS, statusFS, subtitleFS
local titleHoverFrame
local breakdown = {}
local druidSection
local buffRows = {}
local buffsHeaderFS
local footerFS
local outsideCatcher

local TARGET_OPTIONS = {
    { diff = 3, label = "Raid boss (+3)"    },
    { diff = 2, label = "Heroic dungeon (+2)" },
    { diff = 1, label = "Normal dungeon (+1)" },
    { diff = 0, label = "Same level (+0)"     },
}

local function labelForDiff(diff)
    for _, opt in ipairs(TARGET_OPTIONS) do
        if opt.diff == diff then return opt.label end
    end
    return TARGET_OPTIONS[1].label
end

local function currentTargetDiff()
    local perChar = UncrushableHelperPerCharDB
    if perChar and perChar.targetBossLevelDiff ~= nil then
        return perChar.targetBossLevelDiff
    end
    return 3
end

local function setFramePosition(f)
    local point = UncrushableHelperPerCharDB
               and UncrushableHelperPerCharDB.mainFrame
               and UncrushableHelperPerCharDB.mainFrame.point
    f:ClearAllPoints()
    if point and point[1] then
        f:SetPoint(point[1], UIParent, point[3] or point[1], point[4] or 0, point[5] or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function persistFramePosition(f)
    UncrushableHelperPerCharDB.mainFrame = UncrushableHelperPerCharDB.mainFrame or {}
    local point, _, relPoint, x, y = f:GetPoint()
    UncrushableHelperPerCharDB.mainFrame.point = { point, "UIParent", relPoint, x, y }
end

local function buildOutsideCatcher()
    if outsideCatcher then return end
    outsideCatcher = CreateFrame("Frame", nil, UIParent)
    outsideCatcher:SetAllPoints(UIParent)
    outsideCatcher:SetFrameStrata("MEDIUM")
    outsideCatcher:EnableMouse(true)
    outsideCatcher:SetScript("OnMouseDown", function() ns:HideMain() end)
    outsideCatcher:Hide()
end

local function showRowTooltip(self)
    local d = self.tooltipData
    if not d then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(d.label, 1, 0.82, 0)
    GameTooltip:AddDoubleLine("Live:",        string.format("%.2f%%", d.live),      1, 1, 1, 1, 1, 1)
    if d.delta and d.delta > 0 then
        GameTooltip:AddDoubleLine("Planned buffs:", string.format("+%.2f%%", d.delta), 1, 1, 1, 0.45, 0.70, 1.0)
        GameTooltip:AddDoubleLine("Projected:",     string.format("%.2f%%", d.projected), 1, 1, 1, 0.20, 0.85, 0.30)
    end
    GameTooltip:Show()
end

local function showTitleTooltip(self)
    local d = self.tooltipData
    if not d then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(d.title or "Avoidance", 1, 0.82, 0)
    GameTooltip:AddDoubleLine("Live:",          string.format("%.2f%%", d.live or 0),      1, 1, 1, 1, 1, 1)
    if d.delta and d.delta > 0 then
        GameTooltip:AddDoubleLine("Planned buffs:", string.format("+%.2f%%", d.delta),       1, 1, 1, 0.45, 0.70, 1.0)
        GameTooltip:AddDoubleLine("Projected:",     string.format("%.2f%%", d.projected or 0), 1, 1, 1, 0.20, 0.85, 0.30)
    end
    if d.liveVerdict then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Live: " .. d.liveVerdict, 0.75, 0.75, 0.75, true)
    end
    GameTooltip:Show()
end

local function hideTooltip()
    GameTooltip:Hide()
end

local function makeRow(parent, yOffset, label)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(FRAME_WIDTH - 2 * PADDING, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING, yOffset)
    row:EnableMouse(true)
    row:SetScript("OnEnter", showRowTooltip)
    row:SetScript("OnLeave", hideTooltip)

    local left = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    left:SetPoint("LEFT", row, "LEFT", 0, 0)
    left:SetText(label)
    setColor(left, COLOR_MUTED_LABEL)

    local right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    right:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    right:SetJustifyH("RIGHT")

    return { frame = row, label = left, value = right }
end

local function buildBuffRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(FRAME_WIDTH - 2 * PADDING, BUFF_ROW_H)
    row:EnableMouse(true)

    local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    check:SetSize(20, 20)
    check:SetPoint("LEFT", row, "LEFT", 0, 0)

    local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", check, "RIGHT", 4, 0)
    text:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    text:SetJustifyH("LEFT")

    row.check = check
    row.text  = text
    return row
end

local function buildMainFrame()
    if mainFrame then return mainFrame end

    mainFrame = CreateFrame(
        "Frame",
        "UHMainFrame",
        UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil
    )
    mainFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    mainFrame:SetFrameStrata("HIGH")
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        persistFramePosition(self)
    end)
    mainFrame:SetClampedToScreen(true)

    if mainFrame.SetBackdrop then
        mainFrame:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 8,
            edgeSize = 12,
        })
        if mainFrame.SetBackdropColor then
            mainFrame:SetBackdropColor(0.07, 0.07, 0.09, 0.92)
        end
        if mainFrame.SetBackdropBorderColor then
            mainFrame:SetBackdropBorderColor(0.78, 0.64, 0.30, 0.95)
        end
    end

    -- Header
    header = CreateFrame("Frame", nil, mainFrame)
    header:SetPoint("TOPLEFT",  mainFrame, "TOPLEFT",  0, 0)
    header:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", 0, 0)
    header:SetHeight(30)

    titleFS = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleFS:SetPoint("LEFT", header, "LEFT", PADDING, 0)
    titleFS:SetText("Uncrushable Helper")

    closeBtn = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    closeBtn:SetScript("OnClick", function() ns:HideMain() end)

    -- Target level dropdown. Sits above the big number because the player
    -- picks this context BEFORE reading the results; placing it below
    -- would lead to "oh wait, those numbers were vs +2, not +3".
    local targetLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    targetLabel:SetPoint("TOPLEFT", header, "BOTTOMLEFT", PADDING, -2)
    targetLabel:SetText("Target:")

    targetDropdown = CreateFrame(
        "Frame",
        "UHTargetDropdown",
        mainFrame,
        "UIDropDownMenuTemplate"
    )
    targetDropdown:SetPoint("LEFT", targetLabel, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(targetDropdown, 160)
    UIDropDownMenu_Initialize(targetDropdown, function(_, level)
        local current = currentTargetDiff()
        for _, opt in ipairs(TARGET_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text    = opt.label
            info.value   = opt.diff
            info.checked = (opt.diff == current)
            info.func    = function()
                UncrushableHelperPerCharDB.targetBossLevelDiff = opt.diff
                UIDropDownMenu_SetText(targetDropdown, opt.label)
                if ns.Publish then ns:Publish() end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(targetDropdown, labelForDiff(currentTargetDiff()))

    -- Big total
    totalFS = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    totalFS:SetPoint("TOP", targetDropdown, "BOTTOM", 0, -2)
    totalFS:SetText("--")

    statusFS = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusFS:SetPoint("TOP", totalFS, "BOTTOM", 0, -4)
    statusFS:SetText("")

    -- "Including N planned buffs" — one-line blue hint when the primary
    -- number reflects planned-buff simulation. Empty when nothing planned.
    -- The live value (and its verdict) is intentionally NOT shown inline
    -- here — it lives in the title-area hover tooltip to keep the header
    -- uncluttered.
    subtitleFS = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitleFS:SetPoint("TOP", statusFS, "BOTTOM", 0, -2)
    subtitleFS:SetText("")

    -- Breakdown rows (Miss/Dodge/Parry/Block). yStart accounts for the
    -- dropdown + big total + status + simulated line stack above.
    local yStart = -160
    breakdown.miss  = makeRow(mainFrame, yStart,                    "Miss")
    breakdown.dodge = makeRow(mainFrame, yStart - ROW_HEIGHT - 2,   "Dodge")
    breakdown.parry = makeRow(mainFrame, yStart - 2*(ROW_HEIGHT+2), "Parry")
    breakdown.block = makeRow(mainFrame, yStart - 3*(ROW_HEIGHT+2), "Block")

    -- Druid goals section (hidden by default)
    druidSection = CreateFrame("Frame", nil, mainFrame)
    druidSection:SetSize(FRAME_WIDTH - 2 * PADDING, 50)
    druidSection:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", PADDING, yStart - 4*(ROW_HEIGHT+2) - 4)

    druidSection.defenseFS = druidSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    druidSection.defenseFS:SetPoint("TOPLEFT", druidSection, "TOPLEFT", 0, 0)
    druidSection.defenseFS:SetJustifyH("LEFT")

    druidSection.armorFS = druidSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    druidSection.armorFS:SetPoint("TOPLEFT", druidSection.defenseFS, "BOTTOMLEFT", 0, -4)
    druidSection.armorFS:SetJustifyH("LEFT")

    druidSection:Hide()

    -- Buffs section header
    buffsHeaderFS = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    buffsHeaderFS:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", PADDING, yStart - 4*(ROW_HEIGHT+2) - 14)
    buffsHeaderFS:SetText("Raid buffs — check = active · click to plan")
    setColor(buffsHeaderFS, COLOR_MUTED_LABEL)

    -- Buff rows (built lazily from trackedAurasOrder)
    if ns.trackedAurasOrder then
        for i, key in ipairs(ns.trackedAurasOrder) do
            local row = buildBuffRow(mainFrame, i)
            row:SetPoint("TOPLEFT", buffsHeaderFS, "BOTTOMLEFT", 0, -(i - 1) * BUFF_ROW_H - 4)
            row.check:SetScript("OnClick", function(self)
                if ns.aura:IsActive(key) then
                    -- Auto-detected buffs can't be toggled off manually; snap back.
                    self:SetChecked(true)
                    return
                end
                local value = ns.aura:TogglePlanned(key)
                self:SetChecked(value)
                -- Toggling planned changes the simulated total — re-render
                -- synchronously so the UI reflects the new projection
                -- immediately, without waiting for the next event tick.
                if ns.Publish then ns:Publish() end
            end)
            buffRows[key] = row
        end
    end

    footerFS = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footerFS:SetPoint("BOTTOM", mainFrame, "BOTTOM", 0, 8)
    footerFS:SetText("/uh toggle  ·  /uh config  ·  /uh debug")

    -- Invisible hover region covering the title block (big total + status
    -- + subtitle + live line). Hovering it surfaces a GameTooltip with the
    -- base/planned/projected breakdown, the same way per-row hover does.
    -- The frame is created AFTER all four fontstrings exist so we can
    -- anchor it to them.
    titleHoverFrame = CreateFrame("Frame", nil, mainFrame)
    titleHoverFrame:SetPoint("TOPLEFT",     totalFS,    "TOPLEFT",     -40, 4)
    titleHoverFrame:SetPoint("BOTTOMRIGHT", subtitleFS, "BOTTOMRIGHT",  40, -2)
    titleHoverFrame:EnableMouse(true)
    titleHoverFrame:SetScript("OnEnter", showTitleTooltip)
    titleHoverFrame:SetScript("OnLeave", hideTooltip)

    -- ESC-to-close support.
    tinsert(UISpecialFrames, "UHMainFrame")
    mainFrame:SetScript("OnHide", function()
        if UncrushableHelperPerCharDB and UncrushableHelperPerCharDB.mainFrame then
            UncrushableHelperPerCharDB.mainFrame.shown = false
        end
        if outsideCatcher then outsideCatcher:Hide() end
    end)

    setFramePosition(mainFrame)
    mainFrame:Hide()
    return mainFrame
end

local function applySnapshotToFrame(snap)
    if not snap then return end

    -- Keep the dropdown label in sync with the snapshot's active diff
    -- (covers cases where SV was edited externally or migrated).
    if targetDropdown then
        UIDropDownMenu_SetText(targetDropdown, labelForDiff(snap.bossLevelDiff or 3))
    end

    local diff  = snap.bossLevelDiff or 3
    local sim   = snap.simulated or { delta = { count = 0, miss = 0, dodge = 0, parry = 0, block = 0 }, total = snap.total or 0 }
    local delta = sim.delta or { count = 0, miss = 0, dodge = 0, parry = 0, block = 0 }
    local plannedCount = delta.count or 0
    local hasPlanned   = plannedCount > 0
    local BLUE = { 0.45, 0.70, 1.0 }

    -- Primary display is the projected value. When plannedCount = 0 the
    -- projected equals the live value, so this collapses naturally to the
    -- old behavior for characters without planned buffs toggled.
    totalFS:SetText(formatPct(sim.total))
    if snap.mode == "block" and diff >= 3 then
        if sim.isUncrushable then
            setColor(totalFS,  COLOR_GREEN)
            setColor(statusFS, COLOR_GREEN)
            statusFS:SetText("UNCRUSHABLE")
        else
            setColor(totalFS,  COLOR_RED)
            setColor(statusFS, COLOR_RED)
            statusFS:SetText(string.format("CRUSHABLE — short by %s", formatPct(sim.shortBy or 0)))
        end
    elseif snap.mode == "druid-special" then
        setColor(totalFS,  COLOR_GOLD)
        setColor(statusFS, COLOR_GOLD)
        statusFS:SetText("N/A — Druid (no block on table)")
    elseif snap.mode == "block" then
        setColor(totalFS,  COLOR_GOLD)
        setColor(statusFS, COLOR_GOLD)
        statusFS:SetText(string.format("vs +%d target — no crushing blows", diff))
    else
        setColor(totalFS,  COLOR_GOLD)
        setColor(statusFS, COLOR_GOLD)
        statusFS:SetText("No shield — informational only")
    end

    -- Subtitle "Including N planned buffs" + live line. Only when there's
    -- a planned buff whose effect isn't already baked into the live stats.
    if hasPlanned then
        local buffsLbl = plannedCount == 1 and "buff" or "buffs"
        subtitleFS:SetText(string.format("Including %d planned %s", plannedCount, buffsLbl))
        setColor(subtitleFS, BLUE)
    else
        subtitleFS:SetText("")
    end

    -- Breakdown: rows show projected values. When plannedCount = 0 the
    -- projected equals live; when N > 0 each row reflects the post-buff
    -- state. Tooltip on hover reveals the base/delta/projected split.
    local function projectedFor(key)
        return (snap[key] or 0) + (delta[key] or 0)
    end

    -- Paint the value blue when a planned buff contributes to this
    -- component, so "which stat is getting a projection bump" is
    -- readable at a glance without hovering for the tooltip.
    local function paintRow(row, key, applicable)
        if applicable == false then
            row.value:SetText("n/a")
            setColor(row.label, COLOR_GREY)
            setColor(row.value, COLOR_GREY)
            return
        end
        row.value:SetText(formatPct(projectedFor(key)))
        setColor(row.label, COLOR_MUTED_LABEL)
        local d = delta[key] or 0
        if d > 0.005 then
            setColor(row.value, BLUE)
        else
            setColor(row.value, { 1, 1, 1 })
        end
    end

    paintRow(breakdown.miss,  "miss",  true)
    paintRow(breakdown.dodge, "dodge", true)
    paintRow(breakdown.parry, "parry", true)
    paintRow(breakdown.block, "block", snap.components.block.applicable)

    -- Per-row tooltip payload. Consumed by showRowTooltip on hover.
    breakdown.miss.frame.tooltipData  = { label = "Miss",  live = snap.miss  or 0, delta = delta.miss  or 0, projected = projectedFor("miss")  }
    breakdown.dodge.frame.tooltipData = { label = "Dodge", live = snap.dodge or 0, delta = delta.dodge or 0, projected = projectedFor("dodge") }
    breakdown.parry.frame.tooltipData = { label = "Parry", live = snap.parry or 0, delta = delta.parry or 0, projected = projectedFor("parry") }
    if snap.components.block.applicable then
        breakdown.block.frame.tooltipData = { label = "Block", live = snap.block or 0, delta = delta.block or 0, projected = projectedFor("block") }
    else
        breakdown.block.frame.tooltipData = nil
    end

    -- Title hover tooltip payload: aggregate across all four components.
    if titleHoverFrame then
        local titleDelta = (delta.miss or 0) + (delta.dodge or 0) + (delta.parry or 0) + (delta.block or 0)
        local liveVerdict
        if hasPlanned and snap.mode == "block" and diff >= 3 then
            liveVerdict = snap.isUncrushable
                and "UNCRUSHABLE"
                or string.format("CRUSHABLE — short by %s", formatPct(snap.shortBy or 0))
        end
        titleHoverFrame.tooltipData = {
            title       = string.format("Avoidance vs +%d target", diff),
            live        = snap.total or 0,
            delta       = titleDelta,
            projected   = sim.total or 0,
            liveVerdict = liveVerdict,
        }
    end

    -- Druid extras.
    if snap.druidGoals then
        druidSection:Show()
        local defColor = snap.druidGoals.defenseOk and COLOR_GREEN or COLOR_RED
        druidSection.defenseFS:SetText(string.format(
            "Defense Skill: %d / %d",
            snap.defenseSkill or 0,
            snap.druidGoals.defenseTarget))
        setColor(druidSection.defenseFS, defColor)
        druidSection.armorFS:SetText(string.format("Armor: %d", snap.druidGoals.armor or 0))
        setColor(druidSection.armorFS, COLOR_MUTED_LABEL)
    else
        druidSection:Hide()
    end
end

local function refreshBuffRows()
    if not mainFrame then return end
    for key, row in pairs(buffRows) do
        local isActive  = ns.aura:IsActive(key)
        local isPlanned = ns.aura:IsPlanned(key)
        local label = ns.trackedAurasLabels[key] or key

        row.check:SetChecked(isActive or isPlanned)
        if isActive then
            setColor(row.text, COLOR_GREEN)
            row.text:SetText(label .. "  (active)")
        elseif isPlanned then
            setColor(row.text, { 0.45, 0.70, 1.0 })
            row.text:SetText(label .. "  (planned)")
        else
            setColor(row.text, COLOR_MUTED_LABEL)
            row.text:SetText(label)
        end
    end
end

function ns.ui:OnSnapshotChanged(snap)
    if not mainFrame then return end
    applySnapshotToFrame(snap)
    refreshBuffRows()
end

function ns.ui:RefreshBuffRows()
    refreshBuffRows()
end

function ns.ui:ResetPosition()
    if not mainFrame then return end
    setFramePosition(mainFrame)
end

function ns:ShowMain()
    local f = buildMainFrame()
    if ns.state.snapshot then applySnapshotToFrame(ns.state.snapshot) end
    refreshBuffRows()
    f:Show()
    if UncrushableHelperPerCharDB and UncrushableHelperPerCharDB.mainFrame then
        UncrushableHelperPerCharDB.mainFrame.shown = true
    end
    if shouldCatchOutsideClicks() then
        buildOutsideCatcher()
        outsideCatcher:Show()
    end
end

function ns:HideMain()
    if mainFrame then mainFrame:Hide() end
end

function ns:ToggleMain()
    if mainFrame and mainFrame:IsShown() then
        ns:HideMain()
    else
        ns:ShowMain()
    end
end
