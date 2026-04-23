# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.3] - 2026-04-23

### Changed

- The Holy Shield planned-delta now adds an extra `+5.326% block chance` when **Libram of Repentance** (item 29388) is equipped in the ranged slot, matching the libram's in-game interaction with Holy Shield. Previously the simulator assumed a flat `+30%` regardless of the libram; paladins using Libram of Repentance saw the projected total under-estimate their real post-HS state by ~5%. When HS is actually active, no change — `GetBlockChance()` already includes both effects. Verified against the Unbreakable Paladin addon's hardcoded constant (`5.326455…`) and wowhead TBC item data.

## [0.1.2] - 2026-04-23

### Added

- **Physical mitigation % next to the Armor line** in the druid section. The raw armor number is now shown together with its damage-reduction percentage (e.g. `Armor: 15230  (59.1% physical mitigation)`), computed at level 70 via `armor / (armor + 10557.5)`. Bears tank through armor rather than block, so the % is the stat they actually care about — the raw number alone wasn't actionable. Same mitigation % is appended to the minimap-icon tooltip for consistency.

### Fixed

- **Druid layout overlap.** The `Defense Skill` and `Armor` goal lines for druids were anchored with a fixed absolute offset that collided with the "Raid buffs —" header beneath them — they rendered on top of the buff rows and looked unreadable. Fixed: the druid section now anchors below the last breakdown row, and the raid-buffs header anchors below the druid section (only for druids; other classes still anchor directly below the breakdown). The frame also extends to the taller layout for druids so the extra section has room instead of being cramped into the base layout.
- **Incorrect math in the `ANTI_CRIT_DEFENSE_TARGET_DRUID` constant comment.** The constant value (415) was correct and matches community references, but the intermediate arithmetic in its comment stated `boss base crit 5% + 3 levels × 2% = 11%` — which is both a wrong "per-level crit bonus" and gives `(11 − 3) / 0.04 = 200`, not the 65 needed to land at 415. Replaced with the correct derivation: boss crit = 5% + (15 skill diff × 0.04%) = 5.6%; Survival of the Fittest removes 3%; remaining 2.6% / 0.04% per skill = 65 skill over 350 = 415 target.
- **Total avoidance was underreported by ~2.4%, producing false CRUSHABLE verdicts for tanks that were actually uncrushable.** Root cause: the addon was subtracting `0.6%` from each of Miss / Dodge / Parry / Block before comparing the sum against `102.4%`. That amounts to a double-count — the `102.4%` cap target is derived from character-sheet values and already absorbs the `2.4%` the server removes at combat-roll time via weapon-skill-diff penalties. Comparing sheet-minus-2.4% against 102.4% silently required sheet ≥ 104.8%.

  The fix: sum `GetDodgeChance()` / `GetParryChance()` / `GetBlockChance()` directly, with Miss as `5 + (defenseSkill − 350) × 0.04%`, and compare against `102.4%` unchanged. This matches the formula every peer TBC tank addon uses (`AvoidanceRating`, `AvoidanceStatsTBC`, `Unbreakable Paladin`, `CharacterStatsTBC`) and the slash-script published in the "Libram of Protection" top-ranker paladin guide.

  Effect for users: the total displayed goes up by 2.4% (or less, for non-shield characters) with no gear change. Some tanks previously marked CRUSHABLE will flip to UNCRUSHABLE; that's the correct state per the community consensus and the server math applied correctly.

  [`docs/adr/0003`](docs/adr/0003-combat-table-formula-for-player-defender.md) has been extended with a postscript documenting the sheet-vs-effective distinction and the five peer sources that corroborate the fix. The four server-code sources cited in the main ADR remain valid — they accurately describe the combat-roll mechanic; the postscript just clarifies how that result is applied when comparing against 102.4%.

### Removed

- `ns.PER_LEVEL_SHIFT` and `ns.BOSS_LEVEL_DIFF` from `Classes.lua`. Both were byproducts of the incorrect `−0.6%` model and are no longer used anywhere. `ns.TARGET_CAP = 102.4` and `ns.BASE_MISS = 5.0` remain, with an expanded comment explaining how the target absorbs the penalty implicitly.

## [0.1.1] - 2026-04-23

### Added

- **Personal cooldowns section** in the main window, class-gated. Paladins see **Holy Shield** (+30% block while active); warriors see **Shield Block** (+75% block while active). Toggling them as *planned* simulates their block contribution the same way raid buffs do — useful for pre-pull checks like "would I be uncrushable if I keep Holy Shield rolling?". Auto-detection covers every known TBC rank. The section is hidden entirely for classes without a matching cooldown (druids, DPS, casters) and for paladins/warriors without a shield equipped (the cooldowns require one).
- **[ADR 0003](docs/adr/0003-combat-table-formula-for-player-defender.md)** validating the defender-side combat-table formula (0.04% per weapon-skill differential applied equally to Miss / Dodge / Parry / Block when a mob attacks a player). Four independent sources corroborate: magey/tbc-warrior wiki + three open-source server emulators (TrinityTBC, CMangos-TBC, AzerothCore). Not a code change — the formula was already correct — but now documented rigorously so it doesn't have to be re-litigated.

### Changed

- The projected total no longer adds any `delta.block` contribution when the player can't block (no shield, or druid). Previously a shield-less warrior marking Flask of Fortification as planned would see a marginal block bump added to the total that would never actually apply.

### Removed

- **Target-level dropdown**. The previous iteration exposed a +0/+1/+2/+3 selector in the main window so users could see the breakdown against different target levels. It's gone: the addon now always calculates against a +3 raid boss (the only TBC scenario where crushing blows exist, and therefore the only one where the 102.4% cap is meaningful). A passive `Target: Raid boss (+3)` label sits where the dropdown was so the context stays visible. The dead code paths that handled lower diffs (`vs +N target — no crushing blows` status, clamping logic in `Calc:ComputeSnapshot`, the `bossLevelDiff` ctx field and snapshot field, the `targetBossLevelDiff` SV default) are all removed. Users who saved `targetBossLevelDiff` in their SavedVariables keep the field (harmless legacy), it just isn't read anymore.
- **`CLAUDE.md` is no longer tracked in the repo** (moved to `.gitignore`). The file held project-internal notes — roadmap, working memory, non-formal design rationale. Formal architectural decisions stay documented under [`docs/adr/`](docs/adr/) and are still part of the public repo.

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

[Unreleased]: https://github.com/mikarregui/UncrushableHelper/compare/v0.1.3...HEAD
[0.1.3]: https://github.com/mikarregui/UncrushableHelper/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/mikarregui/UncrushableHelper/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/mikarregui/UncrushableHelper/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/mikarregui/UncrushableHelper/releases/tag/v0.1.0
