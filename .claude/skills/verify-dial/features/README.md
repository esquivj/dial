# Dial verification map

This directory is the maintained source for verifying Dial's user-facing behavior in the running app. Read this index and `../SKILL.md` first, then use the matching feature file as the recipe.

## Baseline preconditions

- Run from the repo root, with `D=.claude/skills/verify-dial/bin/dialctl`.
- `$D build`, then `$D launch --fresh --seed`. Dial Verify is now running from this checkout with 120 made-up plays (108 counted), signed out of Spotify, with Last.fm blocked.
- `$D doctor` exits 0.
- Never drive, quit, or read the files of the user's own Dial.

## Driving conventions

- Start every recipe from the baseline unless its preconditions say otherwise.
- Prefer, in this order: headless modes (`$D cli`), accessibility labels (`$D ax`), computer-use `app_*` tools on `com.dial.Dial.verify`. Use computer-use only when the user has granted it.
- Commands are literal. Keep quoted labels and flags unchanged.
- `$D set-pref` and SQL only set up preconditions or read results. Neither stands in for a user action.
- Stop the copy as soon as a journey ends: signed out, its Settings window floats over the user's work.

## Proof and skip reporting

- Save everything in `$($D evidence)`, and take a `$D snap <name>` before and after each action.
- CLI proof is the saved cmd, stdout, stderr and exit files.
- Data proof is a read-only query of the rows the action should change, run before and after.
- UI proof is a computer-use screenshot, described in the report, plus a `snap`.
- Label every artifact with the feature ID and the entry point used.
- Report an unreachable path with the command you tried and the precondition that was missing. Don't report a skipped entry point as verified through a different one.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the user-visible behavior. It then has exactly four H2 sections, in this order:

1. `Sub-features`: short IDs, one line per behavior.
2. `How to get to it (user POV)`: every user entry point.
3. `Driving it with dialctl`: starts with `Preconditions:`, then labeled bullets that pair each user action with an exact command and its observable result.
4. `Gotchas`: traps that waste or invalidate a run.

Keep implementation details out of the map. Name only user paths, stable handles, required state, commands and observable proof.

## Features

| Feature | Covers | Last driven (macOS 27) |
|---|---|---|
| [Multi-Mac history](./multi-mac-history.md) | export, dry run, merge, repeat merge, refusals | 2026-11-01: every step, headless |
| [History import](./history-import.md) | Extended Streaming History import, dedup, counted plays | 2026-11-01: headless path; the Settings path needs UI control |
| [Desktop memory](./desktop-memory.md) | the desktop object, its states, click, menu, snapping, shortcut | 2026-11-01: window and placement only; interactions need UI control |
| [HUD](./hud.md) | menu bar item, the HUD panel and its screens | 2026-11-01: menu bar item label only; screens need a Spotify sign-in |
| [Settings](./settings.md) | the Settings window, its tabs and switches | 2026-11-01: window at launch only; switches need UI control |
