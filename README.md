<p align="center">
  <img src="https://raw.githubusercontent.com/mikarregui/UncrushableHelper/main/assets/logo.png" alt="Uncrushable Helper logo" width="160">
</p>

# UncrushableHelper

> Tell a TBC tank — at a glance — whether they're uncrushable. Breakdown, raid-buff projection, and the math you'd otherwise pull out of a spreadsheet.

[![Release](https://img.shields.io/github/v/release/mikarregui/UncrushableHelper?sort=semver&display_name=tag)](https://github.com/mikarregui/UncrushableHelper/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![CurseForge downloads](https://img.shields.io/curseforge/dt/1522401?label=CurseForge&color=f16436)](https://legacy.curseforge.com/wow/addons/uncrushable-helper-tbc)
[![Issues](https://img.shields.io/github/issues/mikarregui/UncrushableHelper.svg)](https://github.com/mikarregui/UncrushableHelper/issues)

> Target client: **World of Warcraft — The Burning Crusade Classic Anniversary Edition** (2.5.5, Interface `20505`).
> Available on **[GitHub Releases](https://github.com/mikarregui/UncrushableHelper/releases)**, **[CurseForge](https://legacy.curseforge.com/wow/addons/uncrushable-helper-tbc)**, and **[Wago](https://addons.wago.io/addons/uncrushablehelper)**.

## Why

In TBC, tanks avoid Crushing Blows by reaching **102.4% total avoidance** against a raid boss (+3 levels). The total is Miss + Dodge + Parry + Block, each adjusted for the boss's level, each affected by gear, talents, and an assortment of raid buffs that don't come from your own character. Adding all those pieces up correctly — and knowing whether you'll still be over the line *after* someone inevitably forgets to rebuff — is annoying enough that most tanks either use a clunky WeakAura or do the math on alt-tabbed spreadsheets.

`UncrushableHelper` puts the answer on screen with none of that: a clean floating window that shows your current total against the cap, the per-component breakdown, and a checklist of the raid buffs that feed into the calculation — auto-detected when active, togglable for planning.

## Features

- **Real-time avoidance breakdown** — Miss + Dodge + Parry + Block vs +3 boss, updated on every `COMBAT_RATING_UPDATE`, `UNIT_AURA`, `PLAYER_EQUIPMENT_CHANGED`, and talent change.
- **Mode picked by capability, not class** — any class can use the addon:
  - **Block mode** (shield equipped): shows `UNCRUSHABLE` (green) or `CRUSHABLE — short by X.XX%` (red) against the 102.4% cap.
  - **Druid mode** (any druid): Defense Skill and Armor goals instead of a cap verdict.
  - **Informational** (no shield, non-druid): breakdown only, no verdict — the cap is unreachable without block.
- **Component breakdown** — see exactly which stat is holding you back.
- **Raid-buff checklist, curated** — Blessing of Kings, Mark / Gift of the Wild, Flask of Fortification, Elixir of Major Agility, Scroll of Agility. Only buffs that measurably affect the avoidance total are on the list (see [ADR 0002](docs/adr/0002-planning-toggles-as-checklist.md) for what was deliberately excluded). Active buffs are auto-detected (locked on, green); missing buffs can be ticked as "planned" (blue) for pre-pull checks.
- **Floating window** — draggable, position persists per-character, ESC to close, optional click-outside-to-close.
- **Minimap icon** — via LibDBIcon. Left-click toggles the window, right-click opens settings.

## Installation

### Via addon manager (recommended)

Available on [CurseForge](https://legacy.curseforge.com/wow/addons/uncrushable-helper-tbc) and [Wago](https://addons.wago.io/addons/uncrushablehelper). Install via the CurseForge app, the Wago app, or [WowUp](https://wowup.io) (multi-source).

### Manual

1. Download the latest `UncrushableHelper-vX.Y.Z.zip` from the Releases page.
2. Extract the `UncrushableHelper/` folder into your AddOns directory:
   ```
   <WoW install>\_anniversary_\Interface\AddOns\
   ```
3. Launch WoW. Enable the addon in the AddOns menu if needed. `/reload` in-game.

## Usage

- **Click** the minimap icon → toggle the main window.
- **Right-click** the minimap icon → open settings.
- **`/uh`** → toggle the main window.
- **`/uh debug`** → print a snapshot (values, formulas, detected buffs) to chat.
- **`/uh config`** → open settings.
- **`/uh reset`** → re-center the main window.
- **ESC** → close the main window.
- **Click a buff checkbox** while the buff is missing → mark it as "planned" for pre-pull checklists.

### Reading the window

- **Target label** at the top: static `Target: Raid boss (+3)`. The addon always calculates against a +3 raid boss — the only TBC scenario where crushing blows exist, and therefore the only one where the 102.4% cap is meaningful.
- **Big number**: your total avoidance vs the +3 boss, including any planned buffs you've toggled. Green `UNCRUSHABLE` / red `CRUSHABLE — short by X.XX%` when a shield is equipped; gold for druids and shieldless characters (no verdict applies).
- **Subtitle** (blue): when you have planned buffs toggled, shows `Including N planned buffs`. The live value is one hover away on the title tooltip.
- **Breakdown**: Miss / Dodge / Parry / Block, each showing the projected value for the target. Rows affected by a planned buff render in blue. Hover any row for the `Live / Planned / Projected` split.
- **Raid buffs**: one row per tracked buff. Green check + `(active)` = applied to you right now (contribution already in the live numbers). Blue check + `(planned)` = in your checklist (contribution simulated and added to the projection). Click to toggle planned.

### Druids (Feral / Bear)

Druids cannot block, so reaching 102.4% is impractical. Instead, the window shows:

- **Defense Skill** with the anti-crit goal (415 vs a +3 boss, accounting for the 3% crit reduction from Survival of the Fittest).
- **Armor** total, which is the dominant mitigation stat for bear tanks.

The Block row is rendered as `n/a`. Miss/Dodge/Parry still sum, but no `UNCRUSHABLE` verdict is shown because the goal is different.

### Other classes (no shield)

Open the window on a rogue, hunter, mage, or a paladin in Ret with a 2H and you get the breakdown without a verdict — useful for reference, but the 102.4% cap isn't reachable without block chance, so we don't pretend it is.

## How the numbers are calculated

Against a raid boss (+3 levels above the player):

```
miss  = clampNonNeg(5 − 0.6 + (defenseSkill − 350) × 0.04)
dodge = clampNonNeg(GetDodgeChance()  − 0.6)
parry = clampNonNeg(GetParryChance()  − 0.6)
block = clampNonNeg(GetBlockChance()  − 0.6)
total = miss + dodge + parry + block
```

The `− 0.6` is the per-level combat-table shift (0.2% per level × 3 levels). The addon is locked to +3 because crushing blows — and therefore the 102.4% cap — only exist at that level difference. An earlier iteration exposed a target-level dropdown with +0/+1/+2/+3 options; it was removed to keep the frame focused on the scenario that matters.

When planned buffs are toggled, the primary number shifts to reflect the projected post-buff state (Flask of Fortification's +10 Defense Rating is exact; agility-based buffs use a per-class `AGI_PER_DODGE_PCT` table; Blessing of Kings uses `UnitStat` × 0.1). The live value stays accessible via the title hover tooltip. See [docs/adr/0002](docs/adr/0002-planning-toggles-as-checklist.md) for the reasoning.

## Architecture

Horizontal layers — one file per responsibility:

| File | Role |
|---|---|
| `Classes.lua` | Static data (classes, constants, tracked aura spellIds) |
| `Calc.lua`    | Pure snapshot computation |
| `Aura.lua`    | Active-buff detection + planned-buff storage |
| `Core.lua`    | Event frame, SavedVariables, slash commands |
| `UI.lua`      | Main floating frame + LDB + LibDBIcon |
| `Settings.lua`| Settings panel |

See [docs/adr/0001](docs/adr/0001-horizontal-layers-over-vsa.md) for why this structure was chosen over Vertical Slice Architecture.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full workflow — branch naming, commit format, in-game iteration, releasing.

## Tech stack

- **Lua 5.1** (the version WoW's client runs)
- [LibStub](https://www.wowace.com/projects/libstub)
- [CallbackHandler-1.0](https://www.wowace.com/projects/callbackhandler)
- [LibDataBroker-1.1](https://github.com/tekkub/libdatabroker-1-1)
- [LibDBIcon-1.0](https://www.wowace.com/projects/libdbicon-1-0)
- [BigWigs Packager](https://github.com/BigWigsMods/packager) for release automation

## Support

If **Uncrushable Helper** saves you a wipe or two and you feel like saying thanks, you can tip me a coffee on Ko-fi. Completely optional — the addon stays free and fully functional regardless. Issues and PRs on GitHub are just as appreciated.

[![Ko-fi](https://img.shields.io/badge/Ko--fi-tip%20me-FF5E5B?logo=kofi&logoColor=white)](https://ko-fi.com/mikarregui)

## License

[MIT](LICENSE) © mikarregui
