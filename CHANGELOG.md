# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-04-23

Initial public release.

### Added

- Real-time avoidance breakdown against a raid boss (default +3) — works on **any class**. Mode is picked at runtime from what the character can actually do:
  - **`block`** — a shield is equipped (`GetBlockChance() > 0`): shows `UNCRUSHABLE` / `CRUSHABLE — short by X.XX%` against the 102.4% cap.
  - **`druid-special`** — any druid: shows Defense Skill and Armor goals instead of a cap verdict (Block does not exist on the druid attack table).
  - **`no-verdict`** — anyone else: breakdown is shown for reference, no verdict (the cap is unreachable without block).
- **Target level selector** in the main window header. Pick between Raid boss (+3), Heroic dungeon (+2), Normal dungeon (+1), and Same level (+0); the breakdown and total update immediately. Persisted per-character in `UncrushableHelperPerCharDB.targetBossLevelDiff`. The `UNCRUSHABLE` / `CRUSHABLE` verdict only renders at +3 because crushing blows don't exist below that in TBC; at lower diffs the big number switches to gold with a `"vs +N target — no crushing blows"` status.
- **Planned-buff simulation drives the primary display**. Toggling a planned buff that is not currently active adds its avoidance gain to the big number, its verdict, and each row of the breakdown — the addon shows "what your avoidance will look like during the pull" as the default reading. Exact for Flask of Fortification (+10 Defense Rating → each of miss/dodge/parry/block). Class-specific via `AGI_PER_DODGE_PCT` for agility buffs (Mark / Gift of the Wild, Elixir of Major Agility, Scroll of Agility). Multiplicative approximation via `UnitStat("player", Agility)` × 0.1 for Blessing of Kings. See `docs/adr/0002` for the full decision trail.
- **Curated raid-buff list** — only buffs that measurably affect the avoidance total vs a +3 boss: Blessing of Kings, Mark / Gift of the Wild, Flask of Fortification, Elixir of Major Agility, Scroll of Agility. Active buffs auto-detected; absent buffs togglable as "planned". See `docs/adr/0002` for the inclusion criterion and the buffs intentionally excluded (Fortitude, Devotion Aura, Blessing of Sanctuary, Elixir of Major Defense — none of them touch the avoidance table).
- **Hover tooltips** on the title area and on each breakdown row. Show the `Live / Planned buffs / Projected` split plus the live verdict so the exact numbers behind the projection are always one hover away.
- **Subtitle and blue row coloring** — when planned buffs are toggled, a subtitle below the verdict reads `Including N planned buffs`, and rows whose value includes a projected contribution render in blue (same hue as the subtitle). Makes "which stat gets a bump" readable at a glance.
- Floating main window (`UHMainFrame`): draggable, position persisted per-character, ESC to close, optional click-outside-to-close.
- LibDataBroker + LibDBIcon minimap integration (left-click toggle, right-click settings).
- Settings panel (`UHSettingsFrame`) with show-minimap-icon, close-on-outside-click, and reset-position.
- Slash commands: `/uh`, `/uh show`, `/uh hide`, `/uh toggle`, `/uh config`, `/uh debug`, `/uh reset` (and `/uncrush` alias). `/uh debug` prints the full snapshot (formula, live, projected, tracked buffs, active target diff) to chat.
- Single throttled event frame in `Core.lua` reacting to `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD`, `UNIT_AURA`, `COMBAT_RATING_UPDATE`, `UNIT_STATS`, `PLAYER_EQUIPMENT_CHANGED`, `UPDATE_SHAPESHIFT_FORM`, `CHARACTER_POINTS_CHANGED`, and `PLAYER_TALENT_UPDATE` (where available).
- SavedVariables with schema versioning: `UncrushableHelperDB` (global UI preferences) and `UncrushableHelperPerCharDB` (minimap icon, main-frame position, plannedBuffs, targetBossLevelDiff).
- Repository scaffolding: README with badges, CONTRIBUTING, LICENSE (MIT), `.editorconfig`, `.gitignore`, `.pkgmeta`, GitHub issue / PR templates, BigWigs Packager release workflow, ADRs `0001-horizontal-layers-over-vsa` and `0002-planning-toggles-as-checklist`.

[Unreleased]: https://github.com/mikarregui/UncrushableHelper/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/mikarregui/UncrushableHelper/releases/tag/v0.1.0
