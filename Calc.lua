local addonName, ns = ...

ns.calc = {}

-- Bear form id in TBC Classic. Shapeshift index 1 for druids is Bear Form
-- (learned at level 10 and the only relevant tank form here). We treat
-- Dire Bear Form (same index, rank 2) identically.
local BEAR_FORM_ID = 1

local function clampNonNeg(v)
    if v < 0 then return 0 end
    return v
end

local function isBearForm()
    local formId = GetShapeshiftFormID and GetShapeshiftFormID()
    return formId == BEAR_FORM_ID
end

-- Shield check via offhand slot (17 / SecondaryHandSlot) rather than via
-- GetBlockChance. Warriors and Paladins carry passive block chance from
-- talents (Shield Specialization, Redoubt, Anticipation) even with no
-- shield equipped, so GetBlockChance > 0 is a false positive — they would
-- get a CRUSHABLE verdict for a cap they cannot reach. Checking equipLoc
-- against INVTYPE_SHIELD is locale-independent and directly answers the
-- question we actually care about: can this character block right now?
local function hasShieldEquipped()
    if not GetInventoryItemLink then return false end
    local itemLink = GetInventoryItemLink("player", 17)
    if not itemLink or not GetItemInfo then return false end
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemLink)
    return equipLoc == "INVTYPE_SHIELD"
end

-- Pick the display mode based on what the character can actually do right
-- now, not on their class:
--   "druid-special" — druids, always; block doesn't exist on their attack
--                     table, so we show Defense/Armor goals instead.
--   "block"         — a shield is equipped, so the 102.4% cap is
--                     reachable and we render the UNCRUSHABLE verdict.
--   "no-verdict"    — anyone else (DPS without shield, casters, …). We
--                     still show Miss/Dodge/Parry for reference but no
--                     UNCRUSHABLE verdict, because the cap is unreachable
--                     without block and meaningless in that context.
local function determineMode(classFile)
    if classFile == "DRUID" then return "druid-special" end
    if hasShieldEquipped() then return "block" end
    return "no-verdict"
end

-- Estimate the avoidance delta a single buff adds, per class. Only models
-- effects that directly touch a component of the avoidance table — crit
-- rating, haste, armor, stamina etc. from the same items are ignored.
--
-- Returns a table with miss/dodge/parry/block entries (defaulted to 0).
local function deltaForBuff(key, agiPerDodge, currentAgi)
    if key == "flaskFort" then
        -- +10 Defense Rating → ~4.228 Defense Skill → +0.04% on each of
        -- miss/dodge/parry/block per skill gained.
        local pct = (10 / ns.DEFENSE_RATING_PER_SKILL) * 0.04
        return { miss = pct, dodge = pct, parry = pct, block = pct }
    elseif key == "motw" then
        -- Gift of the Wild (rank 3): +14 agility flat.
        return { dodge = 14 / agiPerDodge }
    elseif key == "elixirMajorAgility" then
        -- +35 agility; the +20 crit rating on the same elixir does not
        -- touch the avoidance table.
        return { dodge = 35 / agiPerDodge }
    elseif key == "scrollAgility" then
        -- Scroll of Agility VIII: +25 agility.
        return { dodge = 25 / agiPerDodge }
    elseif key == "bok" then
        -- Greater Blessing of Kings: +10% all stats, multiplicative on
        -- the pre-buff value. Using current agility as the multiplicand
        -- is exact when no other % stat buffs are active and a close
        -- approximation when they are (the error is the cross-term).
        return { dodge = (currentAgi * 0.1) / agiPerDodge }
    end
    return {}
end

-- Sum the deltas of all planned buffs that are NOT currently active.
-- Active buffs are already reflected in GetDodgeChance etc., so simulating
-- them would double-count.
function ns.calc:SimulatePlannedDelta(classFile, plannedSet, activeSet)
    local zero = { miss = 0, dodge = 0, parry = 0, block = 0, count = 0 }
    if not plannedSet then return zero end

    local agiPerDodge = ns.AGI_PER_DODGE_PCT[classFile or ""] or ns.DEFAULT_AGI_PER_DODGE_PCT

    local currentAgi = 0
    if UnitStat then
        local stat = UnitStat("player", 2) -- 2 = Agility
        currentAgi = stat or 0
    end

    local total = { miss = 0, dodge = 0, parry = 0, block = 0, count = 0 }
    for key, enabled in pairs(plannedSet) do
        if enabled and not (activeSet and activeSet[key]) then
            local d = deltaForBuff(key, agiPerDodge, currentAgi)
            total.miss  = total.miss  + (d.miss  or 0)
            total.dodge = total.dodge + (d.dodge or 0)
            total.parry = total.parry + (d.parry or 0)
            total.block = total.block + (d.block or 0)
            total.count = total.count + 1
        end
    end
    return total
end

-- Compute a full defensive snapshot for the current player vs a target
-- whose level is `ctx.bossLevelDiff` above the player (defaults to +3 raid
-- boss when unspecified).
--
-- ctx fields consumed:
--   classFile      — "WARRIOR" | "PALADIN" | "DRUID" | … | nil (auto-detect)
--   activeSet      — { [buffKey] = true } currently applied buffs
--   plannedSet     — { [buffKey] = true } user-toggled planned buffs
--   bossLevelDiff  — 0..3, level difference between target and player
--
-- Returned table shape:
--   {
--     classFile, classInfo,
--     mode              = "block" | "druid-special" | "no-verdict",
--     inBearForm        = bool,                     -- druid only
--     defenseSkill, armor,
--     miss, dodge, parry, block, total,
--     isUncrushable     = bool | nil,               -- nil when not applicable
--     shortBy           = number | nil,             -- how far below 102.4 we are
--     components        = { miss = {...}, dodge = {...}, parry = {...}, block = {...} },
--     simulated         = {                          -- with planned buffs applied
--         delta = { miss, dodge, parry, block, count },
--         total, isUncrushable, shortBy,
--     },
--     notes             = { "string", ... },
--   }
function ns.calc:ComputeSnapshot(ctx)
    ctx = ctx or {}
    local classFile = ctx.classFile or (UnitClass and select(2, UnitClass("player")))
    local classInfo = ns.classInfo[classFile or ""] or { label = classFile or "Unknown" }
    local mode      = determineMode(classFile)

    -- Clamp level diff to 0..3 so the UI can't accidentally pass a
    -- meaningless value (negative, or above where crushing blow mechanics
    -- even exist in TBC content).
    local bossLevelDiff = tonumber(ctx.bossLevelDiff) or ns.BOSS_LEVEL_DIFF
    if bossLevelDiff < 0 then bossLevelDiff = 0 end
    if bossLevelDiff > 3 then bossLevelDiff = 3 end

    local snap = {
        classFile     = classFile,
        classInfo     = classInfo,
        mode          = mode,
        bossLevelDiff = bossLevelDiff,
        notes         = {},
        components    = {},
    }

    -- Defense Skill: UnitDefense returns (base, modifier); their sum is what
    -- the combat table actually uses.
    local defBase, defMod = UnitDefense("player")
    local defSkill = (defBase or 0) + (defMod or 0)
    snap.defenseSkill = defSkill
    snap.armor        = UnitArmor and select(2, UnitArmor("player")) or 0

    if classFile == "DRUID" then
        snap.inBearForm = isBearForm()
        if not snap.inBearForm then
            table.insert(snap.notes, "Switch to Bear Form to read your actual tanking stats.")
        end
    end

    -- Miss vs target:
    --   base 5% − 0.2%/level × bossLevelDiff, plus +0.04% per Defense Skill above 350.
    local levelPenalty = ns.PER_LEVEL_SHIFT * bossLevelDiff
    local missBase     = ns.BASE_MISS - levelPenalty
    local missFromDef  = (defSkill - 350) * 0.04
    local miss         = clampNonNeg(missBase + missFromDef)

    -- Dodge / Parry / Block: GetDodgeChance etc. already bake in base +
    -- stats + rating + talents vs a same-level target. The target's level
    -- penalty is not included, so we subtract it manually.
    local dodge = clampNonNeg((GetDodgeChance() or 0) - levelPenalty)
    local parry = clampNonNeg((GetParryChance() or 0) - levelPenalty)

    local block = 0
    if mode == "block" then
        block = clampNonNeg((GetBlockChance() or 0) - levelPenalty)
    end

    snap.miss  = miss
    snap.dodge = dodge
    snap.parry = parry
    snap.block = block
    snap.total = miss + dodge + parry + block

    snap.components.miss  = { value = miss,  label = "Miss",  formula = "5 + (def-350)*0.04 - 0.6" }
    snap.components.dodge = { value = dodge, label = "Dodge", formula = "GetDodgeChance() - 0.6" }
    snap.components.parry = { value = parry, label = "Parry", formula = "GetParryChance() - 0.6" }
    snap.components.block = {
        value      = block,
        label      = "Block",
        formula    = "GetBlockChance() - 0.6",
        applicable = mode == "block",
    }

    -- Crushing blows only exist against +3 targets in TBC, so the
    -- UNCRUSHABLE verdict is only meaningful at bossLevelDiff == 3. For
    -- lower diffs we still show the breakdown but no cap verdict — the
    -- 102.4% target is a +3-specific artifact.
    local verdictApplies = mode == "block" and bossLevelDiff >= 3

    if verdictApplies then
        snap.isUncrushable = snap.total >= ns.TARGET_CAP
        if not snap.isUncrushable then
            snap.shortBy = ns.TARGET_CAP - snap.total
        end
    elseif mode == "druid-special" then
        snap.isUncrushable = nil
        snap.druidGoals = {
            defenseTarget = ns.ANTI_CRIT_DEFENSE_TARGET_DRUID,
            defenseOk     = defSkill >= ns.ANTI_CRIT_DEFENSE_TARGET_DRUID,
            armor         = snap.armor,
        }
    else
        snap.isUncrushable = nil
    end

    -- Planned-buff projection. Runs regardless of mode so a non-block
    -- class still sees "with planned buffs you'd gain X%" if they care,
    -- but the UNCRUSHABLE verdict on the projection is only meaningful
    -- in block mode at +3.
    local delta = self:SimulatePlannedDelta(classFile, ctx.plannedSet, ctx.activeSet)
    local simTotal = snap.total + delta.miss + delta.dodge + delta.parry + delta.block
    local simulated = {
        delta = delta,
        total = simTotal,
    }
    if verdictApplies then
        simulated.isUncrushable = simTotal >= ns.TARGET_CAP
        if not simulated.isUncrushable then
            simulated.shortBy = ns.TARGET_CAP - simTotal
        end
    end
    snap.simulated = simulated

    return snap
end
