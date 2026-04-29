local addonName, ns = ...

-- Target total avoidance vs a +3 raid boss, compared against the sum of
-- character-sheet avoidance values (Miss + Dodge + Parry + Block). The
-- 2.4% above 100 already absorbs the four 0.04%-per-skill-deficit
-- penalties the server applies at combat-roll time (0.2% × 3 levels = 0.6%
-- per component × 4 components = 2.4%). In other words: sum the raw sheet
-- values, compare against 102.4, do not subtract anything beforehand.
-- See docs/adr/0003 postscript for the derivation and peer-addon
-- corroboration (AvoidanceRating, AvoidanceStatsTBC, Unbreakable Paladin,
-- CharacterStatsTBC, and the "Libram of Protection" top-ranker guide).
ns.TARGET_CAP = 102.4

-- Base chance to be missed by a same-level attacker. Used as-is in the
-- Miss component — the 102.4% target handles the +3 boss adjustment
-- implicitly, so we do NOT subtract per-level shift here.
ns.BASE_MISS  = 5.0

-- Boss crit chance vs a +3 raid boss when the player is at the 350 defense
-- skill floor: 5% base + (15 weapon-skill diff × 0.04%) = 5.6%. The
-- anti-crit cap is reaching this number in total reduction via the three
-- additive sources tracked by ns.calc.computeAntiCrit:
--   1. Defense skill above 350    → 0.04% per point
--   2. Resilience rating (lvl 70) → ~1% per 39.4 rating
--   3. Class talents              → only Survival of the Fittest (druid) -3%
-- See docs/adr/0004 for the math and the TBC-vs-WotLK note on Resilience
-- applying vs PvE in 2.5.5.
ns.BOSS_CRIT_VS_PLUS3 = 5.6

-- Druid Survival of the Fittest: -3% melee crit chance taken. Passive,
-- always-on for any druid that has it talented. Assumed talented for any
-- druid that opens this addon — feral tanks without SotF maxed aren't
-- tanking raids, so the assumption holds in practice. Not gated via
-- GetTalentInfo to avoid unnecessary API chatter.
ns.SOTF_CRIT_REDUCTION = 3.0

-- WoW combat-rating index for "crit chance taken from melee" — what the
-- Resilience stat reduces. GetCombatRatingBonus(CR_CRIT_TAKEN_MELEE) returns
-- the percentage directly (rating-to-% conversion already applied), so we
-- never have to handle the 39.4231 rating-per-1% constant ourselves. We use
-- the global constant exposed by the client (via _G) rather than a hardcoded
-- number because different TBC client versions have used 14, 15, and 16 for
-- this index over time; the global always points to the right one.
ns.CR_CRIT_TAKEN_MELEE = _G.CR_CRIT_TAKEN_MELEE

-- Defense Rating → Defense Skill conversion at level 70. Used to simulate
-- Flask of Fortification (which adds +10 Defense Rating, not raw skill).
--   1 Defense Skill = 2.3654 Defense Rating → 1 Defense Rating = ~0.4228 skill
ns.DEFENSE_RATING_PER_SKILL = 2.3654

-- Libram of Repentance (paladin, ranged/libram slot). Grants +42 block
-- rating while Holy Shield is active — equivalent to ~5.326% block chance
-- at level 70 (42 / 7.8846 block-rating-per-1%-block). GetBlockChance
-- already includes this while HS is up, so we only need to add it to the
-- Holy Shield planned-delta when the libram is equipped and HS is being
-- simulated rather than actually active. Verified against wowhead TBC and
-- the Unbreakable Paladin addon's hardcoded 5.326455… constant.
ns.LIBRAM_OF_REPENTANCE_ITEM_ID    = 29388
ns.LIBRAM_OF_REPENTANCE_BLOCK_DELTA = 5.326

-- Agility points required for 1% Dodge at level 70, per class. Cross-checked
-- against magey/tbc-warrior wiki, wowhead TBC tank guides, and
-- warcraft.wiki.gg on 2026-04-22. Druid in Bear form uses the base druid
-- agi→dodge value (Heart of the Wild does NOT modify this ratio; it scales
-- STR/STA in bear form but dodge-per-agi stays at the druid baseline).
ns.AGI_PER_DODGE_PCT = {
    WARRIOR = 30.0,
    PALADIN = 25.0,
    DRUID   = 14.7,
    SHAMAN  = 25.0,
    HUNTER  = 26.0,
    ROGUE   = 14.5,
    PRIEST  = 20.0,
    MAGE    = 20.0,
    WARLOCK = 20.0,
}
ns.DEFAULT_AGI_PER_DODGE_PCT = 20.0

-- Class display labels. Every TBC-era class is listed so the snapshot
-- prints a clean name for any character — `mode` is NOT stored here
-- because it's determined at runtime from equipment (shield) and form.
ns.classInfo = {
    WARRIOR = { label = "Warrior" },
    PALADIN = { label = "Paladin" },
    DRUID   = { label = "Druid"   },
    HUNTER  = { label = "Hunter"  },
    ROGUE   = { label = "Rogue"   },
    PRIEST  = { label = "Priest"  },
    SHAMAN  = { label = "Shaman"  },
    MAGE    = { label = "Mage"    },
    WARLOCK = { label = "Warlock" },
}

-- spellId → tracked aura key. Multiple spellIds map to the same key so the
-- aura survives rank changes (e.g. Blessing of Kings base vs the Greater
-- Blessing variant cast from a Symbol of Kings reagent).
--
-- Each entry carries `category` ("raid_buff" | "personal_cd") and an
-- optional `class` filter. Raid buffs come from external casters and apply
-- regardless of class; personal cooldowns are self-casts that only make
-- sense for the class that can use them (Holy Shield for paladins, Shield
-- Block for warriors).
--
-- Inclusion criterion for raid buffs is strict: every entry must have a
-- measurable effect on Miss / Dodge / Parry / Block % against a +3 boss.
-- Buffs that improve tank survival but don't touch the avoidance table
-- (Fortitude, Devotion Aura, Blessing of Sanctuary, armor-only consumables)
-- are intentionally out of scope — see docs/adr/0002.
ns.trackedAuras = {}

local function register(key, label, ids, opts)
    opts = opts or {}
    for _, id in ipairs(ids) do
        ns.trackedAuras[id] = {
            key      = key,
            label    = label,
            class    = opts.class,
            category = opts.category or "raid_buff",
        }
    end
end

-- +10% all stats → +Agi (dodge) and +Str (parry via class talents).
register("bok", "Blessing of Kings", { 20217, 25898 })

-- Flat +Stats → smaller version of BoK; affects the same avoidance paths.
register("motw", "Mark / Gift of the Wild",
    { 1126, 5232, 6756, 5234, 8907, 9884, 9885, 26990, 21849, 21850, 26991 })

-- +25 Agility → small but non-zero dodge bump. Competes with Elixir of
-- Major Agility for the "guardian" consumable slot; tanks sometimes pick
-- the scroll when cycling trash.
register("scrollAgility", "Scroll of Agility (V-VIII)",
    { 8115, 8116, 8117, 12174, 33077 })

-- +10 Defense Rating + 500 HP. The Defense is the standout: +0.4% to each
-- of miss, dodge, parry, block = +1.6% total avoidance. Single biggest
-- consumable impact on the uncrushable cap.
register("flaskFort", "Flask of Fortification", { 28518 })

-- +35 Agility + 20 Crit Rating. Agility path affects dodge; typically the
-- competitor to Flask of Fortification in the elixir/flask slot.
register("elixirMajorAgility", "Elixir of Major Agility", { 28497 })

-- Personal cooldowns — self-cast block-chance boosts. Class-gated by the
-- UI so the rows only appear for classes that can actually use them.
--
-- Holy Shield (paladin): +30% block chance for 10s, 4 charges, 10s CD —
-- the de-facto way paladins close the block gap to uncrush during combat.
-- TBC rank IDs 1-4 (rank 5 / 48952 is WotLK+).
register("holyShield", "Holy Shield", { 20925, 20927, 20928, 27179 },
    { class = "PALADIN", category = "personal_cd" })

-- Shield Block (warrior): +75% block chance for 5s, 5s CD. With Improved
-- Shield Block (Prot talent 4/4) uptime approaches 100% during tanking.
register("shieldBlock", "Shield Block", { 2565 },
    { class = "WARRIOR", category = "personal_cd" })

-- Display order — raid buffs (all classes see these).
ns.trackedAurasOrder = {
    "bok",
    "motw",
    "flaskFort",
    "elixirMajorAgility",
    "scrollAgility",
}

-- Display order — personal cooldowns. The UI filters by class so each
-- player only sees the ones they can cast.
ns.personalCDsOrder = {
    "holyShield",
    "shieldBlock",
}

ns.trackedAurasLabels = {
    bok                = "Blessing of Kings",
    motw               = "Mark / Gift of the Wild",
    flaskFort          = "Flask of Fortification",
    elixirMajorAgility = "Elixir of Major Agility",
    scrollAgility      = "Scroll of Agility",
    holyShield         = "Holy Shield",
    shieldBlock        = "Shield Block",
}

-- Class requirement for personal cooldowns. Keys not present here are
-- treated as "any class" (i.e. raid buffs).
ns.personalCDsClass = {
    holyShield  = "PALADIN",
    shieldBlock = "WARRIOR",
}
