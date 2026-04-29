# ADR 0004 — Anti-crit cap: three additive sources, Resilience applies vs PvE in TBC 2.5.5

- **Status**: Accepted
- **Date**: 2026-04-27
- **Affects**: `Calc.lua` `computeAntiCrit`, `Classes.lua` `BOSS_CRIT_VS_PLUS3` / `SOTF_CRIT_REDUCTION` / `CR_CRIT_TAKEN_MELEE`, `UI.lua` anti-crit section, `Core.lua` `/uh debug`

## Context

The addon already tracks the **uncrushable cap** (102.4% of Miss + Dodge + Parry + Block, see [ADR 0003](0003-combat-table-formula-for-player-defender.md)). It originally also tracked an **anti-crit cap**, but only for druids — a single line `Defense Skill: X / 415 (vs +3 boss)`. Warriors and paladins, who need the same kind of guardrail (490 defense skill, or equivalent reduction from other sources), saw nothing.

A user reported equipping a PvP belt because they didn't have an epic equivalent yet, and asked whether the addon was crediting Resilience toward avoidance. It isn't, and shouldn't — Resilience doesn't add Miss/Dodge/Parry/Block. But the question surfaced two real gaps:

1. **Resilience does belong on the anti-crit ledger**, not the avoidance one. It's a perfectly valid path to crit immunity, and the addon was silently ignoring it.
2. **Warriors and paladins had no anti-crit display at all** — and TBC Phase 1/2 BiS lists explicitly recommend some PvP pieces for tanks, so Resilience-on-tanking-gear is a real and recurring scenario.

This ADR resolves both: a single computation that combines defense skill, Resilience rating, and class talents into one anti-crit goal display, shown for all tank-shaped characters (any druid, plus warriors and paladins with a shield equipped).

## Decision

The anti-crit cap is reaching **5.6% total crit reduction vs a +3 raid boss**, computed as the sum of three additive sources:

```
fromDefense   = max(0, (defenseSkill − 350) × 0.04)        -- % crit removed
fromTalents   = (class == DRUID) ? 3.0 : 0                 -- Survival of the Fittest
fromResil     = GetCombatRatingBonus(CR_CRIT_TAKEN_MELEE)  -- already in %
total         = fromDefense + fromTalents + fromResil
ok            = total ≥ 5.6
```

The cap target (5.6%) is `5% base + (15 weapon-skill diff × 0.04%) = 5.6%`. This is the boss's effective crit chance against a level 70 defender at the 350 defense floor, derived exactly the same way as the +3 weapon-skill penalty in ADR 0003 — same 0.04%-per-skill mechanic, just applied to crit chance (defender side) instead of distributed across the four avoidance outcomes.

The math runs in `Calc.lua` `computeAntiCrit(classFile, mode, defSkill)` and is gated on `mode in {"block", "druid-special"}`. For non-tank shapes (DPS without shield, casters) the function returns nil and no display renders — anti-crit is a tanking concept.

## Evidence

### Anti-crit cap math: 5.6% target, three additive sources

- **Boss base crit = 5%, +0.04% per skill diff**: this is the same 0.04%-per-weapon-skill-diff factor documented in ADR 0003. The diff vs a +3 boss (level 73) for a level 70 defender is `(73 × 5) − (70 × 5) = 15` weapon skill above defense, so boss crit = `5% + 15 × 0.04% = 5.6%`. Cross-checks: [magey/tbc-warrior wiki Attack-table page](https://github.com/magey/tbc-warrior/wiki/Attack-table), [TrinityTBC `Unit::CalculateMeleeAttackerProcChance`](https://github.com/The-Cataclysm-Preservation-Project/TrinityCore/tree/2.4.3) (cited from ADR 0003), [icy-veins TBC Protection Warrior guide stat priorities page](https://www.icy-veins.com/tbc-classic/protection-warrior-tank-pve-stat-priority).

- **Defense skill reduction: 0.04% per point above 350**: same factor, applied to crit chance reduction. This is the standard "1 defense skill removes 0.04% from each of crit, crushing, hit, etc." TBC mechanic. 140 points above 350 (= 490 def skill) closes the full 5.6% gap; 65 points above 350 (= 415 def skill) closes 2.6% which is exactly what a druid needs after SotF.

- **Resilience: 39.4231 rating per 1% crit reduction at level 70**. Verified against [wowhead TBC Resilience tooltip](https://www.wowhead.com/tbc/spell=29080), the Magey wiki, and the [icy-veins stat priority pages](https://www.icy-veins.com/tbc-classic/protection-warrior-tank-pve-stat-priority). The addon doesn't apply this conversion itself — `GetCombatRatingBonus(CR_CRIT_TAKEN_MELEE)` returns the post-conversion percentage directly.

- **Survival of the Fittest: -3% melee crit chance taken**. Druid feral talent. Verified against [wowhead TBC Survival of the Fittest spell](https://www.wowhead.com/tbc/spell=33181). Passive, always-on, does not require Bear Form.

The three sources stack additively, not multiplicatively. The combat-table mechanic in TBC subtracts each contribution from the boss's crit chance independently; there is no diminishing-returns interaction below the cap.

### Resilience applies vs PvE in TBC 2.5.5 (critical distinction)

Resilience's behavior changed across expansions. In **TBC 2.x**, the tooltip reads:

> *Reduces your chance of being struck by a critical strike from **any source** by X%, reduces the damage taken from critical strikes by 2X%, reduces the damage of damage-over-time spells from other players by X%, reduces all mana drained from spells like Mana Burn and Viper Sting by X%.*

The "any source" language was changed in **WotLK patch 3.0** to "from another player only" — making Resilience a PvP-only stat for crit reduction from that point on. **TBC Anniversary 2.5.5** keeps the original TBC behavior; Resilience reduces crit chance from all sources, including raid bosses.

Sources confirming TBC behavior:
- [wowhead TBC Resilience tooltip](https://www.wowhead.com/tbc/spell=29080) (TBC-era tooltip preserved on the TBC database).
- [Tank That blog: Resilience and the defense cap](https://tankthat.wordpress.com/2008/12/17/resilience-and-the-defense-cap/) — written in late TBC, explicitly discusses Resilience as a substitute for defense skill on tanks.
- [icy-veins TBC Protection Warrior stat priority](https://www.icy-veins.com/tbc-classic/protection-warrior-tank-pve-stat-priority) and equivalent paladin/druid pages — list Resilience as a viable anti-crit path for tanks running PvP gear.

This is what makes Resilience worth tracking on a TBC tank addon at all. If the cap were computed for a WotLK or later client, this ADR's logic would need to gate Resilience to PvP only.

### Combat rating index — why we use the global `_G.CR_CRIT_TAKEN_MELEE` instead of a hardcoded number

Different WoW Lua client versions have used different numeric indices for the "crit chance taken from melee" combat rating: 14 (early TBC), 15 (some Classic builds), 16 (modern). The TBC Anniversary 2.5.5 client exposes a global `CR_CRIT_TAKEN_MELEE` constant that always points to the right index for the running client. We read `_G.CR_CRIT_TAKEN_MELEE` once at addon load and pass it to `GetCombatRatingBonus`, which keeps the addon resilient to future Blizzard reshuffles of the index table.

## What the addon does NOT need to special-case

A separate research pass (documented in the v0.2.0 plan file, summarized here for reference) verified that **no other TBC item, gem, enchant, libram, idol, set bonus, racial passive, buff, or consumable** contributes to crit reduction outside of the two API paths:

1. Anything contributing to defense skill — defense rating gear, talents (Anticipation +5 for prot warrior, Combat Expertise +15 for prot paladin), meta gems with defense rating, Glyph of the Defender enchant, Flask of Fortification — flows through `UnitDefense("player")` and is captured automatically.

2. Anything contributing to Resilience — gem cuts (Subtle Crimson Spinel +12 res, Subtle Living Ruby +8 res), PvP gear (Vengeful/Merciless Gladiator's plate sets, Brooch of Deftness, season trinkets, PvP belts), any future Resilience source — flows through `GetCombatRatingBonus(CR_CRIT_TAKEN_MELEE)` and is captured automatically.

3. The only crit-reduction effect that bypasses both APIs is **Survival of the Fittest** (druid passive talent), hardcoded as `ns.SOTF_CRIT_REDUCTION = 3.0` and applied conditionally to druids. This is the single special case, and it is not conditional on form, gear, or any other state — just on whether the character is a druid.

There is no TBC analogue to [Libram of Repentance's conditional block bonus](../../CHANGELOG.md) (the +5.326% block while Holy Shield is active that required special handling in v0.1.3). No item gives "+X% crit reduction while ability Y is active" or "+X% crit reduction below Z% HP". If Blizzard adds one in a future TBC Anniversary patch, we would model it as a "personal cooldown" entry in `Aura.lua` paralleling Holy Shield/Shield Block, with a `delta` shape that includes a `critReduction` field — same architectural pattern as the existing block-chance personal CDs.

## Why we don't programmatically check Survival of the Fittest

`GetTalentInfo` would let us read the talent rank and gate the `-3%` accordingly. We chose not to:

- Every druid that opens this addon to look at tank stats has SotF talented. Feral tanks max it as one of their first picks; balance/restoration druids who didn't talent SotF aren't tanking raids and aren't using this addon.
- Reading `GetTalentInfo` requires extra event handling (`PLAYER_TALENT_UPDATE` / `CHARACTER_POINTS_CHANGED`) and complicates a hot path that already runs on `UNIT_AURA` bursts.
- The cost of being wrong is low — a druid without SotF would see a 3% over-estimate in their crit reduction. They'd notice the discrepancy when comparing against the character sheet, and if they reported it we'd add the talent check.

If a bug report ever surfaces, gating SotF behind `GetTalentInfo` is a small, isolated change. The current assumption is documented in the constant's comment in `Classes.lua`.

## Why we show Resilience even when the rating is 0

A user with no Resilience sees `Resilience (0 rating)  −0.00%` in the breakdown. We considered hiding the line in that case but kept it visible:

- The line teaches users that Resilience is a tracked input. When they later acquire a piece with Resilience, they immediately understand how it contributes — no need to check release notes or guess.
- Three lines of layout (defense / SotF / resilience) is a stable visual; conditional collapse would create a jumpy display when gear changes.
- The dual function of the addon — diagnostic and pedagogic — benefits from making the math visible even at zero values.

## Validation cases

| Class | Defense skill | Resilience rating | Expected breakdown | Verdict |
|---|---|---|---|---|
| Druid feral, bear | 415 | 0 | def 2.6% + SotF 3.0% = 5.6% | ✓ OK |
| Druid feral, bear | 410 | 100 | def 2.4% + SotF 3.0% + res 2.54% = 7.94% | ✓ OK |
| Druid feral, bear | 400 | 0 | def 2.0% + SotF 3.0% = 5.0% | ✗ short by 0.6% |
| Warrior prot | 490 | 0 | def 5.6% = 5.6% | ✓ OK exact |
| Warrior prot | 480 | 30 | def 5.2% + res 0.76% = 5.96% | ✓ OK |
| Warrior prot | 480 | 0 | def 5.2% = 5.2% | ✗ short by 0.4% |
| Paladin prot | 485 | 50 | def 5.4% + res 1.27% = 6.67% | ✓ OK |
| Paladin ret with 2H | 350 | 0 | mode = no-verdict, snap.antiCrit = nil | n/a (no display) |

Direct in-game verification: equip a piece with Resilience → the Resilience line picks up the correct rating and percentage. Unequip → line returns to `0 rating  −0.00%`. Defense skill changes via gear/buffs flow through `UnitDefense` and update the defense line on the same render.

## Comparison against peer addons

Unlike the avoidance cap math (cross-checked in ADR 0003 against AvoidanceRating, AvoidanceStatsTBC, Unbreakable Paladin, CharacterStatsTBC, and the Libram of Protection guide), peer tank addons do not generally surface the anti-crit cap as a single goal. Some show defense skill alone; some show Resilience separately under "PvP stats". None aggregate the three sources into a single "crit immunity vs +3 boss" display the way this addon does.

That makes the validation primary-source: the three components are each independently verified (linked sources above), and their additive combination is verified by the TBC combat-table mechanic, but there is no peer addon that produces a directly comparable number to A/B against. The validation case table above takes the place of peer-addon comparison.

## Consequences

- A single header line is added between the avoidance breakdown and the raid-buffs section: `Anti-crit goal: 5.60% needed   ✓ OK` (green) or `Anti-crit goal: 5.60% needed   short by X.XX%` (red). Hovering the line surfaces a `GameTooltip` with the per-source breakdown (defense above 350, Survival of the Fittest if druid, Resilience rating) plus the running totals — the same data, off-screen until requested. Keeps the main window compact while making the math one hover away.
- Druids previously saw a `Defense Skill: X / 415` line and an `Armor: Y (Z% mitigation)` line. Both are removed: anti-crit replaces the defense line, and the armor + mitigation display is dropped entirely (the character pane already surfaces both, and the addon's scope is the avoidance and anti-crit caps, not general tanking stats).
- Warriors and paladins with a shield equipped now see the same anti-crit header line. This is new UI surface; it adds ~18px under the avoidance breakdown, before the raid-buffs section.
- The `wantsExtended` flag in the UI now triggers on `snap.antiCrit ~= nil` (any tank-shaped character) plus the existing personal-cooldowns trigger. `FRAME_HEIGHT_EXTENDED` bumped from 540 to 560 to fit the anti-crit header + personal CDs stack for block-mode tanks.
- `snap.druidGoals` is no longer populated — the constant `ANTI_CRIT_DEFENSE_TARGET_DRUID = 415`, `ARMOR_MITIGATION_K_L70`, and the `snap.armor` field are removed. External code that read those would need to migrate to `snap.antiCrit` (which has the equivalent and richer information). The minimap-icon LDB tooltip is also slimmed: only the avoidance total + UNCRUSHABLE/CRUSHABLE verdict for block mode remains; defense, armor, and anti-crit lines previously shown there are removed in favor of the main window doing that work.
