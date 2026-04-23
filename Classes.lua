local addonName, ns = ...

-- Target total avoidance vs a raid boss (+3 levels over the player).
-- Getting to this number means Crushing Blow and Regular Hit fall off the
-- attack table — the tank is "uncrushable". The 2.4% above 100 is the
-- inherent level-based bias bosses have against lower-level defenders.
ns.TARGET_CAP       = 102.4
ns.BOSS_LEVEL_DIFF  = 3

-- Per-level combat table shift vs same-level target: each level of the
-- attacker above the defender shifts every avoidance outcome down by 0.2%.
-- Against a boss (+3), each of Miss/Dodge/Parry/Block loses 0.6%.
ns.PER_LEVEL_SHIFT  = 0.2

-- Base chance to be missed by a same-level attacker.
ns.BASE_MISS        = 5.0

-- Defense Skill a druid needs vs a +3 boss to be crit-immune given the
-- -3% crit reduction from the Survival of the Fittest talent:
--   boss base crit 5% + 3 levels × 2% = 11%
--   crit removed per Defense Skill over 350 = 0.04%
--   350 + (11 - 3) / 0.04 = 415
ns.ANTI_CRIT_DEFENSE_TARGET_DRUID = 415

-- Defense Rating → Defense Skill conversion at level 70. Used to simulate
-- Flask of Fortification (which adds +10 Defense Rating, not raw skill).
--   1 Defense Skill = 2.3654 Defense Rating → 1 Defense Rating = ~0.4228 skill
ns.DEFENSE_RATING_PER_SKILL = 2.3654

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
-- Inclusion criterion is strict: every entry must have a measurable effect
-- on Miss / Dodge / Parry / Block % against a +3 boss. Buffs that improve
-- tank survival but don't touch the avoidance table (Fortitude, Devotion
-- Aura, Blessing of Sanctuary, armor-only consumables) are intentionally
-- out of scope — see docs/adr/0002.
ns.trackedAuras = {}

local function register(key, label, ids)
    for _, id in ipairs(ids) do
        ns.trackedAuras[id] = { key = key, label = label }
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

-- Display order for the UI buff section. Fixed so the list stays stable
-- even as the player gains/loses buffs.
ns.trackedAurasOrder = {
    "bok",
    "motw",
    "flaskFort",
    "elixirMajorAgility",
    "scrollAgility",
}

ns.trackedAurasLabels = {
    bok                = "Blessing of Kings",
    motw               = "Mark / Gift of the Wild",
    flaskFort          = "Flask of Fortification",
    elixirMajorAgility = "Elixir of Major Agility",
    scrollAgility      = "Scroll of Agility",
}
