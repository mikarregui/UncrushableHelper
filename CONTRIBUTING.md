# Contributing to UncrushableHelper

Thanks for looking under the hood. This document describes how the repo is organized and how changes flow in.

## Branch strategy

- `main` is protected. Never push to it directly.
- Create a branch off `main` for every change:
  - `feat/<short-name>` — new features
  - `fix/<short-name>` — bug fixes
  - `chore/<short-name>` — maintenance, config, tooling
  - `docs/<short-name>` — docs-only changes
- Open a pull request against `main` when the branch is ready.

## Commit messages

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add Drums of Battle to tracked buffs
fix: clamp miss component to zero when defense is below 350
chore: bump packager action to v2.5
docs: clarify uncrushable formula in CLAUDE.md
refactor: extract snapshot printing out of the slash handler
```

Use the body to explain the **why** when it isn't obvious. Breaking changes go in the footer:

```
feat!: restructure SavedVariables schema

BREAKING CHANGE: plannedBuffs are now per-character; existing global toggles will be migrated on first load.
```

## Pull requests

1. Keep PRs focused. Smaller is better.
2. Fill out the PR template.
3. Reference the issue it closes (`Closes #42`).
4. Test locally in-game (see below) before marking ready.
5. Prefer **squash merge** to keep `main` history linear.

## Local development

### Clone and symlink

```powershell
git clone https://github.com/mikarregui/UncrushableHelper.git
cd UncrushableHelper

# PowerShell as Administrator:
New-Item -ItemType SymbolicLink `
  -Path "C:\BattleNet\World of Warcraft\_anniversary_\Interface\AddOns\UncrushableHelper" `
  -Target "$PWD"
```

After the symlink, edits in the repo are picked up by WoW after a `/reload`.

> **Note on libraries.** `Libs/` is resolved by the BigWigs Packager at release time and is not committed. For local testing you need the libraries present in that folder. Easiest path: download the latest release ZIP, copy its `Libs/` into the repo root, then edit source files freely.

### Iterating in-game

Handy console commands:

| Command | Purpose |
|---|---|
| `/console scriptErrors 1` | Surface Lua errors on screen |
| `/reload` or `/rl` | Reload UI after a code change |
| `/eventtrace` | Live stream of events firing (useful for validating the event frame) |
| `/uh` | Toggle the main window |
| `/uh debug` | Print the current snapshot (breakdown, fraction of cap, tracked buffs) to chat |
| `/uh reset` | Reset the main window position |

Install [BugGrabber](https://www.curseforge.com/wow/addons/bug-grabber) + [BugSack](https://www.curseforge.com/wow/addons/bugsack) to capture full stack traces.

### Validating numbers

Open the character pane (C) and compare what it shows with the `/uh debug` output. The addon's Dodge/Parry/Block are `GetXChance() − 0.6` (the +3 boss level penalty). Miss is `5 − 0.6 + (defenseSkill − 350) × 0.04`. If the numbers disagree by more than rounding, something has drifted — investigate before merging.

### Syntax check before pushing

```bash
luac -p Core.lua Classes.lua Calc.lua Aura.lua UI.lua Settings.lua
```

WoW runs **Lua 5.1**. Newer `luac` (5.3/5.4) catches syntax errors fine but will happily accept constructs Lua 5.1 does not support. Keep the code in the Lua 5.1 subset.

## Releasing

Releases are fully automated.

1. Bump the version in `CHANGELOG.md` under a new heading.
2. Merge the release PR into `main`.
3. Tag it:
   ```bash
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```
4. The `release.yml` workflow runs the BigWigs Packager, which:
   - Resolves `.pkgmeta` externals (downloads `Libs/`).
   - Substitutes `@project-version@` tokens in `.toc` files.
   - Packages `UncrushableHelper/` into a versioned ZIP.
   - Publishes it to GitHub Releases, CurseForge, and Wago.

No manual packaging, no manual upload.

## Repository settings (for maintainers)

One-time GitHub configuration that lives outside the repo:

- Branch protection on `main`: require PR before merge, require conversations resolved, no direct pushes.
- Auto-delete head branches on merge.
- Allow squash merging; disable merge commits and rebase merging.
- Secrets for CurseForge/Wago distribution (`CF_API_KEY`, `WAGO_API_TOKEN`, `GITHUB_TOKEN` is built-in).
- Add topics: `wow`, `world-of-warcraft`, `addon`, `wow-addon`, `tbc-classic`, `classic-anniversary`, `tank`, `lua`.

## Code style

- Lua indent: **4 spaces**. Enforced by `.editorconfig`.
- Prefer `local` for everything. Never leak globals except the addon namespace (`ns`) and the SavedVariables tables declared in the `.toc`.
- Events over `OnUpdate`. If `OnUpdate` is unavoidable, throttle.
- No premature abstraction — three similar lines are fine, a speculative helper is not.
- No comments that restate the code. Comments explain **why**, not **what**.
- Never let `Calc.lua` grow side effects (no `print`, no frames). See [CLAUDE.md](CLAUDE.md) for the full list of load-bearing invariants.
