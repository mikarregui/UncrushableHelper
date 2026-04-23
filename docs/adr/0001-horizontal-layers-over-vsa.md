# ADR 0001 — Horizontal layers over Vertical Slice Architecture

- **Status**: Accepted
- **Date**: 2026-04-22
- **Affects**: project structure since inception

## Context

The author's global `CLAUDE.md` prescribes **Vertical Slice Architecture (VSA)** as the default for all projects: each feature is an independent, self-contained module, features never import from one another directly, and anything shared lives in `shared/`. That convention is an excellent fit for web applications and multi-feature backends where independent teams ship isolated capabilities.

This repository is a WoW TBC Classic addon. The shape of the problem is different:

1. **One effective feature**. The entire addon is a single product surface: "read tank avoidance, cross it with buffs, render it". Breaking it into feature slices would either produce one slice (and thus no vertical decomposition) or force artificial splits (`display-avoidance`, `detect-buffs`, `panel-settings`) that all import from one another, defeating the point of VSA.
2. **One consumer**. Everything the addon produces is consumed by exactly one caller — the WoW client — via a small, fixed API surface (events, slash commands, SavedVariables). There is no multi-client pressure for loose coupling.
3. **Small codebase**. The MVP is ~700 LOC. VSA's coordination overhead (per-slice barrel files, cross-slice `shared/` promotion rules, colocated tests) is calibrated for repos an order of magnitude larger.
4. **Idiomatic community pattern**. Popular addons in the WoW ecosystem — including the reference project in `C:\Programming\wow-addon-multibutton` — organize around **layers by responsibility** (Core, UI, Settings) rather than around features. Contributors are familiar with that shape; forcing VSA here would trade discoverability for theoretical purity.

## Decision

Organize `UncrushableHelper` as **horizontal layers by responsibility**. Each `.lua` file owns one kind of concern:

| File | Responsibility |
|---|---|
| `Classes.lua` | Static data: supported classes, tracked aura spellIds, constants |
| `Calc.lua` | Pure computation of avoidance snapshots — no frames, no side effects |
| `Aura.lua` | Buff detection + planned-buff state, isolated from UI concerns |
| `Core.lua` | Orchestration: single event frame, SavedVariables, slash commands |
| `UI.lua` | Rendering: the main floating frame, LDB + LibDBIcon integration |
| `Settings.lua` | The settings panel, self-contained and lazy-built |

Calc and Aura are **pure modules**: they expose functions on `ns.calc` / `ns.aura` and mutate `ns.state` only through the well-known fields documented in `CLAUDE.md`. Core subscribes to WoW events and calls into them. UI consumes snapshots but never reads raw WoW state itself.

## Consequences

### Positive

- **Onboarding is fast for anyone who has read another idiomatic addon.** Contributors who have worked on LibDBIcon-based addons, Ace3 addons, or the `wow-addon-multibutton` reference pick up the layout immediately.
- **Pure modules are easy to reason about and swap.** `Calc.lua` and `Aura.lua` can be exercised mentally without running the game because they have no frame dependencies.
- **Single event frame.** One event pump in `Core.lua` throttles recalc requests, keeping the event surface small and predictable.

### Negative

- **The author's global `CLAUDE.md` is not followed literally here.** Anyone applying global rules mechanically would "correct" the structure to VSA. This ADR exists so that such a correction is recognized as a regression, not an improvement.
- **Cross-file changes are slightly more common.** Adding a new tracked buff touches `Classes.lua` (the spellId list) and potentially `UI.lua` (if the display order matters). In a VSA layout, both would live in the same slice.

### Reversibility

Reversible at any time. If the addon grows to three or more distinct features (for example: avoidance cap, threat meter, cooldown tracker), a VSA refactor becomes a reasonable option. At that point the layer split could be replaced with per-feature folders each containing their own `Calc/Aura/UI/Settings` micro-layers. Until then, this ADR stands.

## References

- `C:\Users\mikar\.claude\CLAUDE.md` — the global user instructions prescribing VSA as default.
- `C:\Programming\wow-addon-multibutton` — the reference project, which follows the same horizontal-layers pattern adopted here.
