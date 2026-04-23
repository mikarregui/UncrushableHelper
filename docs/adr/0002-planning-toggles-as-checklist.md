# ADR 0002 — Projected total is the primary display; live is secondary

- **Status**: Accepted (second revision). Supersedes the pre-release "checklist-only" position and the first iteration's "simulate but keep live primary" position.
- **Date**: 2026-04-23
- **Affects**: `v0.1.0` onward

## Context

One of the product differentiators for `UncrushableHelper` is the **Raid buffs** section in the main window. Each tracked buff (Blessing of Kings, Mark / Gift of the Wild, Flask of Fortification, Elixir of Major Agility, Scroll of Agility) shows up as a checkbox. When the buff is present on the player we flag it auto-detected (`active`); when the buff is absent but the user has ticked the box, we flag it `planned`.

Two related questions follow. First: **should the planned buffs contribute to the total avoidance number?** Second: **which buffs belong on this list at all?** Both decisions are captured here.

## Decision

**The primary display is the projected total (live stats plus the effect of planned buffs not currently active).** The big number in the header, its color, and the `UNCRUSHABLE / CRUSHABLE` verdict are all driven by the projection. When no planned buffs are toggled, the projection equals live and the display is indistinguishable from a pure live view.

**Live ground truth is surfaced via a `GameTooltip` on hover over the title area**, showing the aggregate split: `Live: A.AA%`, `Planned buffs: +B.BB%`, `Projected: C.CC%`, plus the live verdict. The earlier iteration of this ADR also surfaced a small muted `live: X.XX%` inline row under the status; it was removed based on user feedback after the tooltip was in place — the inline row duplicated information that was already one hover away, and the header reads cleaner with only the primary number, its verdict, and the "Including N planned" subtitle.

**Per-component rows (Miss/Dodge/Parry/Block) show the projected value only**, with the base/delta/projected split available in a hover tooltip on each row. The inline `(+X.XX%)` delta text that a previous iteration rendered next to each value has been removed — it required mental math and cluttered the row. Tooltips trade discoverability for a cleaner default view.

This is the second revision of ADR 0002. The first revision already reversed the pre-release "checklist only" position (simulating was the right answer); this revision reverses the "keep live as primary" decision that accompanied it. The reason for the second reversal is the same thread of user feedback that drove the first: the addon's target audience — tanks verifying their raid setup against the cap — thinks in terms of "state during the pull", not "state right now while I'm in Shattrath with half my buffs off". A primary that shows `CRUSHABLE` when the user would pull `UNCRUSHABLE` inverted the actionable reading of the screen. Promoting the projection fixes that; keeping live accessible via tooltip and the live line preserves the ground-truth discipline.

**On the inclusion criterion: strict.** A buff is tracked **only if** it has a measurable effect on at least one of Miss / Dodge / Parry / Block % against a +3 boss. The curated MVP list:

| Buff | Mechanism |
|---|---|
| Blessing of Kings | +10% all stats → +Agi (dodge), +Str (parry via class talents) |
| Mark / Gift of the Wild | Flat +Stats → same pathways as BoK, smaller magnitude |
| Flask of Fortification | +10 Defense Rating → +0.4% on each of miss, dodge, parry, block (total +1.6%) |
| Elixir of Major Agility | +35 Agi → dodge; competes with Flask for the elixir/flask slot |
| Scroll of Agility (V–VIII) | +Agi → small dodge bump, cheap alternative to Major Agility |

Buffs that improve tank survival without touching the avoidance table — **Blessing of Sanctuary** (block value, not chance), **Power Word / Prayer of Fortitude** (stamina), **Devotion Aura** (armor), **Elixir of Major Defense** (armor despite the misleading name) — are **not** tracked. Listing them would teach players to chase buffs that don't move the cap.

**Personal cooldowns extension (post-v0.1.0).** A sibling "Personal cooldowns" section exists beneath the raid buffs for shield-wearing tanks: **Holy Shield** (paladin, +30% block while active) and **Shield Block** (warrior, +75% block while active). They follow the same simulation path as raid buffs (a flat `delta.block` from `deltaForBuff`), but are rendered in a separate class-gated section because they're *self*-casts, not external buffs — the mental model of "did someone remember to give me this?" doesn't apply. Class gate in `ns.aura:ListPersonalCDsForUI`; the section is hidden entirely for classes without a match and for paladins/warriors without a shield equipped (mode != "block"). Same strict inclusion criterion as raid buffs: only abilities that touch the avoidance table qualify (Divine Shield and Shield Wall are out because they're invulnerability / damage reduction, not block chance).

## Rationale

The earlier checklist-only decision was defensible in the abstract — simulating arbitrary buffs across every talent tree is a minefield — but the **curated buff list** we actually track sidesteps most of that risk:

- **Flask of Fortification** (+10 Defense Rating): pure rating → skill conversion, exact for every class.
- **Mark / Gift of the Wild**, **Elixir of Major Agility**, **Scroll of Agility**: flat agility deltas. We multiply by `1 / (agility points per 1% dodge at level 70)` — a per-class constant well documented in wowhead/magey tank guides. Minor class drift at fractional percents, but nothing that flips an UNCRUSHABLE/CRUSHABLE verdict.
- **Blessing of Kings** (+10% all stats): multiplicative on the player's pre-buff agility. We read `UnitStat("player", 2)` (Agility) and multiply by 0.1. Exact when no other % stat buff is concurrently active; a small cross-term approximation otherwise.

Effects on Strength → Parry and Intellect → Spell Crit are intentionally ignored: in TBC, none of the tracked buffs' secondary stat deltas meaningfully touch the tank avoidance table (Warriors don't get parry-from-strength, Paladins don't get dodge-from-intellect). Buffs whose pipelines are genuinely complex or whose impact is zero on avoidance — **Fortitude, Devotion Aura, Blessing of Sanctuary, Elixir of Major Defense** — remain **excluded from the tracked list** (see inclusion criterion below), so they don't appear as toggles and no simulation is needed for them.

The projection is the primary reading of the frame, with the live number (plus its verdict) surfaced on the secondary `live:` line and in the title tooltip. Earlier revisions of this ADR argued the opposite — that ground truth should occupy the most visible slot — and we still respect that concern: the live number is always one glance (or one hover) away, never hidden. The inversion is justified because the addon's target audience reasons in terms of "state during the pull", not "state right now". A primary display that reads `CRUSHABLE` when the user *will* be `UNCRUSHABLE` in their actual raid setup was actively misleading even though it was technically accurate, and raiders do not read the secondary line first in practice.

## Consequences

### Positive

- **Matches how the target audience reads the frame.** A tank glancing at the big number to decide "do I pull?" gets the answer *for their raid setup*, not for a transient out-of-raid state. The verdict color (green/red) flips between `UNCRUSHABLE` and `CRUSHABLE` based on the projection, so "green big number" is a reliable signal.
- **Ground truth is still one hover away.** The title-area tooltip gives the full `live / planned / projected` split plus the live verdict. Accessibility of the live number is preserved, just not the visual priority.
- **Rows stay uncluttered.** With the inline `(+X.XX%)` delta removed, each row is just `label` and `projected value`. Users who want the breakdown get it on hover, a standard Blizzard UI pattern.
- **Small class table, no talent walk.** Because the curated buff list is short and its stat→avoidance paths are simple, the implementation is one per-class constant (`AGI_PER_DODGE_PCT`) plus five `deltaForBuff` cases. No talent tree traversal, no per-spec branching.

### Negative

- **The primary number is a projection, not ground truth.** A user who doesn't notice the "Including N planned buffs" subtitle or hover for the tooltip could momentarily believe their live avoidance is higher than it actually is. The blue coloring on rows affected by planned buffs is an additional signal, and the subtitle's blue color matches those rows. If that mitigation chain proves insufficient in practice, the display decision is the first thing to revisit.
- **Class drift at fractional percents.** The `agi per 1% dodge` values are correct within TBC tank theorycrafting's usual tolerance (±0.3 agility across patches), but the simulated dodge gain can be off by ~0.05% for odd classes. Immaterial for cap decisions (no one's inside 0.05% of 102.4%), but worth being honest about.
- **Blessing of Kings approximation.** The multiplicative path uses `UnitStat("player", Agility)` × 0.1. When other concurrent % stat buffs are active (not common in the buffs we track, but possible with external buffs the addon doesn't know about), there's a cross-term underestimate. For the tracked list specifically, BoK is the only multiplicative buff, so in practice the simulation is exact.
- **Strict inclusion criterion becomes load-bearing.** Adding a buff to `trackedAuras` now also commits us to a simulation path for it in `deltaForBuff`. Armor-only or stamina-only buffs remain excluded — their simulation would be `+0` on the avoidance table and listing them as "planned" buffs would be misleading UX.

### Reversibility

The simulation can be disabled with near-zero churn: `ns.calc:SimulatePlannedDelta` returns a zero-delta table and the UI hides the secondary line. If future data shows a class's `AGI_PER_DODGE_PCT` drift more than we thought, we can either refine the constants per-class or retreat to simulating only the buff with exact math (Flask of Fortification) and leaving the agility-based buffs as pure checklist entries.

The strict inclusion criterion can also be relaxed *only* by adding a separate section with a distinct heading (for example "Tank survival buffs") so the avoidance checklist keeps pointing users at buffs that move the cap. Mixing the two back into one list is what we reject here.

## References

- Competitor analysis confirming none of `AvoidanceStats TBC`, `TankPoints`, `TankInfos TBC`, `AvoidanceRating` simulate raid buffs reliably on 2026-04-22 — the gap is consistent across the category.
- `github.com/magey/tbc-warrior/wiki` and `warcraft.wiki.gg/wiki/Combat_rating_system` for the stat-to-avoidance pipelines that this ADR declines to re-implement.
- TBC buff/consumable effects cross-checked against wowhead TBC DB and `warcraft.wiki.gg` for the inclusion decision (Blessing of Sanctuary affects block value not chance; Elixir of Major Defense grants armor not defense rating).
