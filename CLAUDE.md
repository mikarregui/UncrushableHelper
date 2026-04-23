# CLAUDE.md — UncrushableHelper

Context for Claude Code working on this repository. For human contributors, start with [README.md](README.md) and [CONTRIBUTING.md](CONTRIBUTING.md).

## What this addon is

A WoW TBC Classic Anniversary (Interface `20505`) addon that shows a character's avoidance breakdown (Miss + Dodge + Parry + Block) against a +3 boss. For characters that can block — a shield is equipped, `GetBlockChance() > 0` — it also renders the UNCRUSHABLE / CRUSHABLE verdict against the 102.4% cap. Druids get a special mode with Defense Skill and Armor goals instead, since Block doesn't exist on the druid attack table. Any class can open the addon; for characters that cannot block the breakdown is informational only (no verdict).

It also lists the raid buffs that actually influence the avoidance total, auto-detects the ones currently applied, and lets the user tick "planned" toggles as a pre-pull checklist.

## Architecture

Horizontal layers, not Vertical Slice Architecture. See [docs/adr/0001](docs/adr/0001-horizontal-layers-over-vsa.md) for why the global VSA prescription is not followed here.

| File | Role |
|---|---|
| `Classes.lua` | Static data: classes, constants (`TARGET_CAP`, `BOSS_LEVEL_DIFF`), `trackedAuras` spellId map |
| `Calc.lua` | Pure module: `ns.calc:ComputeSnapshot(ctx)` returns the breakdown. No frames. No side effects. |
| `Aura.lua` | Active-buff detection + planned-buff storage. Mutates `ns.state.activeBuffs*` only. |
| `Core.lua` | Single event frame, SV migration, slash commands, `ns:Publish()`, `ns:RequestRecalc()` |
| `UI.lua` | `UHMainFrame`, LDB + LibDBIcon, render logic |
| `Settings.lua` | `UHSettingsFrame`, lazy-built at `PLAYER_LOGIN` |

The loading order in `UncrushableHelper.toc` matches the dependency direction: data → pure modules → orchestration → UI.

## Load-bearing invariants

- **One event frame in `Core.lua`.** Every other module exposes functions and is invoked by Core's event handler. Do not register WoW events elsewhere except where already present (LDB register in `UI.lua`, settings pre-build in `Settings.lua`).
- **Calc is pure.** `Calc.lua` must never call `CreateFrame`, `print`, or `UnitAura`. It reads player stats (`UnitDefense`, `GetDodgeChance`, `GetParryChance`, `GetBlockChance`, `GetShapeshiftFormID`, `UnitArmor`) and returns a table. Everything else is orchestration.
- **Mode is determined at runtime, not by class.** Calc picks `"druid-special"` for any druid, `"block"` for any class whose `GetBlockChance() > 0` (i.e. has a shield equipped), and `"no-verdict"` otherwise. Do not reintroduce class-based gating — the addon is open to all classes.
- **Planning toggles do not alter `total`.** See [docs/adr/0002](docs/adr/0002-planning-toggles-as-checklist.md). The total always reflects what the game reports. Planned buffs are a visual checklist only.
- **Tracked buffs must affect avoidance.** Every entry in `ns.trackedAuras` must measurably change Miss / Dodge / Parry / Block %. Buffs that help tank survival but don't touch the avoidance table (Fortitude, Devotion Aura, Blessing of Sanctuary, armor-only consumables) are out of scope — see ADR 0002.
- **Throttled publish.** Bursts of `UNIT_AURA` + `COMBAT_RATING_UPDATE` + `UNIT_STATS` on a single tick must coalesce into one `ns:Publish()`. The flag + `C_Timer.After(0, fn)` pattern in `ns:RequestRecalc()` is the contract — do not bypass it.

## Avoidance formula (vs +3 boss)

```
defSkill = base + mod  (from UnitDefense("player"))
miss     = clampNonNeg(5 − 0.6 + (defSkill − 350) × 0.04)
dodge    = clampNonNeg(GetDodgeChance()  − 0.6)
parry    = clampNonNeg(GetParryChance()  − 0.6)
block    = clampNonNeg(GetBlockChance()  − 0.6)      [block classes only]
total    = miss + dodge + parry + block
uncrushable = (mode == "block") and (total ≥ 102.4)
```

The `− 0.6` on each component is the per-level combat-table shift: each of the 3 levels the boss is above the player subtracts 0.2% from each avoidance outcome. This constant is **documented here** so future refactors do not accidentally change it.

Druids do not have Block on their attack table and cannot reach 102.4% in practice; the addon renders them in `"druid-special"` mode and surfaces Defense Skill + Armor goals instead of a cap verdict. Non-druid characters without a shield render in `"no-verdict"` mode — the breakdown is shown but no cap verdict, since the 102.4% target is not reachable without block.

## SavedVariables

Global (`UncrushableHelperDB`): UI preferences.
```
{ schemaVersion=1, global = { closeOnOutsideClick } }
```

Per-character (`UncrushableHelperPerCharDB`): minimap icon position, main-frame position/shown, plannedBuffs.
```
{ schemaVersion=1, minimap, mainFrame, plannedBuffs, lastKnownClass }
```

`plannedBuffs` is per-character because the composition of a player's raid (and their consumables) is character-specific. Do not move it to global without a user-driven rationale.

## Out of scope for v0.1

Deferred intentionally. Do not add them unless the user asks:

- Gear compare / equipment set import
- Suggestions of pieces or enchants to reach the cap
- In-combat history / uptime graphs
- Raid buff *simulation* (see ADR 0002)
- A separate "tank survival buffs" section (Fortitude, Devotion Aura, Sanctuary) alongside the avoidance one. If added, it must live in its own sub-section with a clearly different heading so the avoidance checklist is not polluted.

## Target client

- World of Warcraft — **The Burning Crusade Classic Anniversary Edition** (2.5.5, Interface `20505`).
- Lua 5.1 is what WoW runs. The `luac` in `scoop` is 5.4 — it catches syntax errors fine but cannot diagnose 5.1-specific gotchas (e.g. `goto`, integer division operator `//`) that 5.4 accepts. Write Lua 5.1-compatible code.
