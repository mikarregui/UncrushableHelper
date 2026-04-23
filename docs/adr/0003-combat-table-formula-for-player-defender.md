# ADR 0003 — Player-defender combat table: 0.04% per skill diff on all four outcomes

- **Status**: Accepted
- **Date**: 2026-04-23
- **Affects**: `Calc.lua` `ComputeSnapshot` (lines 173–189 of the current revision) and every snapshot the addon has ever produced

## Context

In TBC the defender's effective Miss / Dodge / Parry / Block against an incoming melee attack depends on the defender's Defense Skill versus the attacker's Weapon Skill. Against a raid boss (+3 levels), the attacker's weapon skill exceeds the defender's maximum defense by 15 points, and that deficit reduces each of the four avoidance outcomes.

The question that prompted this ADR: **does the deficit apply equally to all four outcomes, or only to Miss?**

Secondary sources disagreed at a glance. Our reference TBC stats addon [CharacterStatsTBC](https://github.com/getov/CharacterStatsTBC) only adjusts Miss for the boss level and displays Dodge/Parry/Block from `GetDodgeChance()` / `GetParryChance()` / `GetBlockChance()` unmodified — reading that code naïvely suggested "Miss only". On the other hand, magey's TBC warrior wiki stated the penalty applies to all four. And a first pass of web research conflated "player attacking mob" formulas (which use different multipliers per outcome: 0.1% / 0.2% / 0.6%) with the "mob attacking player" formulas we care about, producing a report that looked contradictory.

Because the addon's verdict (UNCRUSHABLE / CRUSHABLE) swings by ±1.8% total depending on which interpretation is right — enough to flip the line at the margin — the question needed to be resolved with primary-source evidence rather than consensus.

## Decision

When a mob (including a +3 raid boss) attacks a player, the player's effective avoidance is computed from the same character-sheet values WoW reports via `GetDodgeChance()` / `GetParryChance()` / `GetBlockChance()` / a manually computed Miss, each reduced by the same `0.04%` per point of weapon-skill deficit. Equivalently, against a +3 boss each of Miss / Dodge / Parry / Block loses `0.6%` off the value the character sheet shows (the combat system treats 1 level = 5 skill, so 3 levels = 15 skill × 0.04% = 0.6%).

This matches the formula [`Calc.lua`](../../Calc.lua) already implements:

```lua
local levelPenalty = ns.PER_LEVEL_SHIFT * ns.BOSS_LEVEL_DIFF   -- 0.2 × 3 = 0.6
local missBase     = ns.BASE_MISS - levelPenalty               -- 5.0 − 0.6 = 4.4
local miss  = clampNonNeg(missBase + (defSkill - 350) * 0.04)
local dodge = clampNonNeg((GetDodgeChance() or 0) - levelPenalty)
local parry = clampNonNeg((GetParryChance() or 0) - levelPenalty)
local block = clampNonNeg((GetBlockChance() or 0) - levelPenalty)  -- only in block mode
```

The `ns.PER_LEVEL_SHIFT = 0.2` constant × 3 levels = `0.6`, which is the same 15 × 0.04% path expressed per-level. Both formulations are equivalent.

## Evidence

Four independent sources — one theorycrafting, three open-source server implementations from different lineages — agree on the `0.04%` factor applied to all four defender outcomes when the defender is a player.

### Source 1 — [magey/tbc-warrior Wiki, Attack-table page](https://github.com/magey/tbc-warrior/wiki/Attack-table)

The wiki explicitly splits each outcome into "target is a mob" vs "target is a player" cases. For the **target-is-a-player** case (what a tank experiences):

> **Miss**: `MissChance = 5% + (TargetDefense - AttackerSkill) * 0.04%`
>
> **Dodge**: `DodgeChance = PlayerDodge + (PlayerDefense - AttackerSkill) * 0.04%`
>
> **Parry**: `ParryChance = PlayerParry + (PlayerDefense - AttackerSkill) * 0.04%`
>
> **Block**: "Each point of difference adjusts the base chance by 0.1% if the target is a mob and 0.04% if the target is a player."

All four use the identical `0.04%` per skill point of (PlayerDefense − AttackerSkill).

### Source 2 — [TrinityTBC/core, `Unit.cpp`](https://github.com/TrinityTBC/core/blob/master/src/server/game/Entities/Unit/Unit.cpp)

The server-side combat code for a TBC 2.4.3 emulator, independent of Mangos lineage.

```cpp
// GetUnitDodgeChance — line 2945
if (victim->GetTypeId() == TYPEID_PLAYER)
{
    chance = victim->GetFloatValue(PLAYER_DODGE_PERCENTAGE);
    skillBonus = 0.04f * skillDiff;
}

// GetUnitParryChance — line 2988
if (Player const* playerVictim = victim->ToPlayer())
    if (playerVictim->CanParry())
    {
        chance = playerVictim->GetFloatValue(PLAYER_PARRY_PERCENTAGE);
        skillBonus = 0.04f * skillDiff;
    }

// GetUnitBlockChance — line 3053
if (Player const* playerVictim = victim->ToPlayer())
    if (playerVictim->CanBlock() && hasShield)
    {
        chance = playerVictim->GetFloatValue(PLAYER_BLOCK_PERCENTAGE);
        skillBonus = 0.04f * skillDiff;
    }

// MeleeSpellMissChance — line 2698
int32 diff = -skillDiff;
if (victim->GetTypeId() == TYPEID_PLAYER)
    missChance += diff > 0 ? diff * 0.04 : diff * 0.02;
```

The `skillBonus = 0.04f * skillDiff` is literal and identical across Dodge / Parry / Block. Miss uses `diff * 0.04` for positive diff (attacker-advantage case, which is ours for +3 boss).

### Source 3 — [cmangos/mangos-tbc, `Unit.cpp`](https://github.com/cmangos/mangos-tbc/blob/master/src/game/Entities/Unit.cpp)

CMangos is a completely separate TBC emulator from TrinityCore's lineage. The three `CalculateEffective*Chance` functions (lines 3380 / 3409 / 3445) all follow the same pattern:

```cpp
int32 difference = int32(GetDefenseSkillValue(attacker) - skill);
// Defense/weapon skill factor: for players and NPCs
float factor = 0.04f;
// NPCs gain additional bonus dodge chance based on positive skill difference
if (!isPlayerOrPet && difference > 0)
    factor = 0.1f;
chance += (difference * factor);
```

The `0.1f` override only fires when the defender is an NPC with positive skill difference. **Player defenders always use `0.04f` for all three outcomes.** Miss (`CalculateEffectiveMissChance`, line 3977) follows the identical pattern with the same per-player `factor = 0.04f`.

### Source 4 — [azerothcore/azerothcore-wotlk, `Unit.cpp`](https://github.com/azerothcore/azerothcore-wotlk/blob/master/src/server/game/Entities/Unit/Unit.cpp)

AzerothCore is a WotLK 3.3.5 emulator, branched long ago from the MaNGOS / TrinityCore ancestor. The skill-diff mechanic did not change between TBC and WotLK (only the defense-skill cap rose from 350 to 400 at max level), so this source is valid corroboration for the same formula.

```cpp
// RollMeleeOutcomeAgainst — line 2995
int32 skillBonus = 4 * (attackerWeaponSkill - victimMaxSkillValueForLevel);

// …then the same skillBonus is subtracted from DODGE (line 3038),
// PARRY (line 3070), and BLOCK (line 3087):
&& ((tmp -= skillBonus) > 0)
```

The `4 *` is `0.04%` expressed in a 10 000-scaled integer representation (used throughout AzerothCore for sub-percent precision). Identical `skillBonus` is applied to all three. Miss uses the same `0.04f` factor for player victims in `MeleeSpellMissChance` (line 15240).

For spell / ability attacks specifically, the file also carries (lines 3446 / 3468 / 3486):

```cpp
int32 dodgeChance  = int32(victim->GetUnitDodgeChance() * 100.0f) - skillDiff * 4;
int32 parryChance  = int32(victim->GetUnitParryChance() * 100.0f) - skillDiff * 4;
int32 blockChance  = int32(victim->GetUnitBlockChance() * 100.0f) - skillDiff * 4;
```

Literally the same `* 4` across all three.

## Why secondary sources looked contradictory

- **CharacterStatsTBC addon** shows Dodge / Parry / Block as returned by `GetDodgeChance()` / `GetParryChance()` / `GetBlockChance()` unmodified. This is not evidence that the boss-level penalty doesn't exist — the addon simply chooses to display the character-sheet value (vs same-level attacker) rather than compute the effective value against a +3 boss. The author opted into a display convention, not a different formula. Our addon makes the opposite choice: we surface the *effective* value against the content the user cares about (+3 raid bosses), so we apply the `0.6%` adjustment.
- **Player-attacking-mob formulas** in magey's wiki use higher multipliers (0.1% / 0.2% / 0.6% depending on outcome). Those describe the *mob's* chance to dodge / parry / block the player's attack, not the player's defensive chances when being attacked. An earlier web-research pass conflated the two directions of combat and produced a misleading "multipliers differ per outcome" claim that applies to the wrong scenario.

## Consequences

### Positive

- The formula is validated against four independent implementations, three of them being open-source server-side code that reproduces Blizzard's combat table. At this point the formula is as well-grounded as it can be without access to Blizzard's own source.
- The addon's UNCRUSHABLE / CRUSHABLE verdict is accurate at the margin: no systematic 1.8% under- or over-estimation of the total.

### Negative

- None that we know of. The arithmetic is simple and cheap.

### Reversibility

If a retail / private-server patch were to change the factor (hypothetically to 0.1% for dodge/parry/block while keeping 0.04% for miss), the fix is mechanical: change `ns.PER_LEVEL_SHIFT` (or switch to per-outcome multipliers) in `Classes.lua` and re-verify against updated sources. Not a concern for TBC Classic Anniversary (2.5.5), which is frozen on the original mechanics.

## Non-goals

This ADR does **not** cover:

- Per-class **base** dodge / parry / block values (those come from `GetDodgeChance()` etc., which the game computes correctly from the player's stats, gear, and talents — we just read the number).
- Defense-rating-to-skill conversion at max level. That's covered in `Classes.lua`'s `DEFENSE_RATING_PER_SKILL = 2.3654` constant, for which the reference is the standard `1 / 0.4228` ratio cited across the same sources.
- Block *value* (damage absorbed per block), which is a separate stat not on the avoidance table.

## Postscript — Applying the formula vs the 102.4% cap target (2026-04-23)

The server-side formula above is correct about what happens at combat-roll time. It is **not**, however, what you compare against the 102.4% uncrushable cap. A later cross-check against five additional sources — four peer addons (`AvoidanceRating`, `AvoidanceStatsTBC`, `Unbreakable Paladin`, `CharacterStatsTBC`) read directly from the user's `Interface\AddOns\` directory, plus the "Libram of Protection" top-ranker paladin guide (Google Doc) — revealed a unanimous convention: **the 102.4% target is for the sum of character-sheet values** (`GetDodgeChance() + GetParryChance() + GetBlockChance() + 5% base miss + (defense_skill − 350) × 0.04%`), with no `−0.6%` adjustment before comparison.

The "Libram of Protection" guide is explicit on this point. The guide's own slash-script in the post reads:

```
/script DEFAULT_CHAT_FRAME:AddMessage("Need 102.4 combined avoidance. Currently at:",0.8,0.8,1)
/script DEFAULT_CHAT_FRAME:AddMessage(GetDodgeChance()+GetBlockChance()+GetParryChance()+5+
(GetCombatRating(CR_DEFENSE_SKILL)*150/355 + 20)*0.04,1,0.5,0)
```

Sheet values summed directly, `5%` miss base un-adjusted, compared against `102.4`. The author also says in the narrative text: *"this calculation has already subtracted the 2.4% total miss, dodge, parry, and block reduction for you"* — confirming that the `102.4%` number absorbs the skill-diff penalty implicitly.

Mathematical derivation: crushing is off the table when effective `Miss + Dodge + Parry + Block ≥ 100%`. Since effective = sheet − `4 × 0.6%` = sheet − `2.4%`, the sheet-value equivalent is sheet ≥ `102.4%`. Every addon and authoritative guide we checked uses the sheet form because it matches the number WoW displays on the character pane and the number the community cites.

Versions of `UncrushableHelper` prior to `v0.1.2` subtracted `0.6%` from each of the four components before comparing against `102.4%`, effectively requiring `sheet ≥ 104.8%`. That was a double-count — the addon silently told users they were `CRUSHABLE` when they were actually uncrushable per the community consensus and per the server-side math applied correctly. Fixed in `v0.1.2` (see `CHANGELOG`).

The four server-code sources cited in the main body above **remain valid and accurate** about what the combat roll does internally. This ADR does not retract them. The postscript only clarifies how the result is used when comparing against the community-standard cap target.

## References

- [magey/tbc-warrior Wiki — Attack-table](https://github.com/magey/tbc-warrior/wiki/Attack-table)
- [TrinityTBC/core — `src/server/game/Entities/Unit/Unit.cpp`](https://github.com/TrinityTBC/core/blob/master/src/server/game/Entities/Unit/Unit.cpp) (functions `GetUnitDodgeChance`, `GetUnitParryChance`, `GetUnitBlockChance`, `MeleeSpellMissChance`)
- [cmangos/mangos-tbc — `src/game/Entities/Unit.cpp`](https://github.com/cmangos/mangos-tbc/blob/master/src/game/Entities/Unit.cpp) (functions `CalculateEffectiveDodgeChance`, `CalculateEffectiveParryChance`, `CalculateEffectiveBlockChance`, `CalculateEffectiveMissChance`)
- [azerothcore/azerothcore-wotlk — `src/server/game/Entities/Unit/Unit.cpp`](https://github.com/azerothcore/azerothcore-wotlk/blob/master/src/server/game/Entities/Unit/Unit.cpp) (function `RollMeleeOutcomeAgainst` and `MeleeSpellMissChance`)
- [`Calc.lua`](../../Calc.lua) — implementation under audit

### Postscript sources (peer-addon and guide cross-check, 2026-04-23)

- [AvoidanceRating on CurseForge](https://www.curseforge.com/wow/addons/avoidance-rating) — `AvoidanceRating.lua:1-24`. Sums `GetDodgeChance() + GetParryChance() + GetBlockChance() + 5 + (defense_skill − 350) × 0.04` vs 102.4%. No per-stat penalty applied.
- [AvoidanceStats TBC on CurseForge](https://www.curseforge.com/wow/addons/avoidancestats-tbc) — `AvoidanceStats.lua:158-161` computes Miss with `5 + (d-350)*0.04 - 0.6` (note: applies `−0.6` to Miss specifically, unlike other addons) but uses `GetDodgeChance/Parry/Block` directly without `−0.6`. Compares sum against 102.4%.
- [Unbreakable Paladin on CurseForge](https://www.curseforge.com/wow/addons/unbreakable-paladin) — `main.lua:1-20`. `Dodge + Block + Parry + 5 + defense_contribution`, adds `+30` when Holy Shield is down (simulating it on). No per-stat penalty.
- [CharacterStatsTBC on GitHub](https://github.com/getov/CharacterStatsTBC) — `CharacterStatsTbcCore.lua`. Paperdoll frame uses `GetDodgeChance()` / `GetParryChance()` / `GetBlockChance()` directly; only its `missChanceVsBoss` helper adjusts for weapon-skill-diff (but that's player attacking boss, not the defensive table).
- "Libram of Protection" — top-ranker Protection Paladin guide (Google Doc shared by user, 2026-04-23). Lines 870-874 and 1230-1234. Explicitly states the `102.4%` target already absorbs the `2.4%` level-diff penalty, and provides a slash-script that sums sheet values directly against that target.
