---
name: verify-dial
description: Launch, drive and capture evidence from the real Dial macOS menu bar app without touching the user's own Dial. Builds an isolated "Dial Verify" copy (its own bundle id and home folder), seeds made-up listening history, reads its windows, accessibility tree, database and preferences, and runs Dial's headless import, archive export and merge modes against it. Use it to prove a Dial change works in the running app, beyond unit and snapshot tests, especially for history, stats data, multi-Mac merges, the desktop object, the HUD and Settings.
---

# Verify Dial in the running app

Dial is a menu bar app (SwiftUI + AppKit, macOS 14+). What a user touches:

- the menu bar item, which opens the 440×440 HUD panel (HUD, History, Stats and Pet screens);
- the desktop memory object, which sits on the desktop under every window;
- the Dial Settings window (General, Menu Bar, HUD and Pet tabs);
- headless command-line modes: `--import`, `--export-archive`, `--merge-archive`.

The user's own Dial (usually `/Applications/Dial.app`) holds their real listening history and accounts. **Never drive it, quit it, or open its files.** Everything below runs against Dial Verify, a copy that `dialctl` builds from this checkout and starts itself.

Run everything from the repo root:

```bash
D=.claude/skills/verify-dial/bin/dialctl
```

## How the copy is isolated

| | Real Dial | Dial Verify |
|---|---|---|
| Bundle id and preferences | `com.dial.Dial` | `com.dial.Dial.verify`: its own defaults domain, privacy grants and "already running" checks |
| Database, Spotify token, Last.fm files | `~/Library/Application Support/Dial/` | `.build/verify/home/Library/Application Support/Dial/` (via `CFFIXED_USER_HOME`) |
| `dial://` links | registered | not registered (`CFBundleURLTypes` removed) |
| Last.fm | as the user connected it | empty key files stop the login-keychain fallback, so it can't reach the user's Last.fm |
| Spotify | signed in | signed out until someone signs in inside Dial Verify |

Signed out, the copy makes no Spotify or Last.fm calls. Shared, because macOS has one of each: the menu bar, the desktop, global shortcuts, the screen, and (once signed in) the Spotify account and its playback. See Gotchas.

## Launch

```bash
$D build                    # scripts/dev.sh build, then a re-signed copy in .build/verify/
$D launch --fresh --seed    # empty home, 120 made-up plays, then start the copy
```

`launch` returns when the copy is usable: the process is alive, its database has the newest migration in `Dial/Store/Migrations.swift`, and it has a window on screen. It waits up to 30 s, then prints the window table. A fresh signed-out launch shows two windows: the desktop memory object (level −20, 256×328) and Dial Settings (level 3, floating, 700×572).

- `--fresh` wipes the copy's home and preferences and starts a new evidence run.
- `--seed` imports `bin/synth-history.py` output before the app starts: made-up names (`Verify Track 01` by `Verify Artist A`), 120 plays over 21 days. The newest play is always Verify Track 01, five minutes before the seed ran. About one in ten plays is a skip under 30 s: 120 plays give 108 counted. `--plays N` changes the count.
- `-- <Dial flags>` passes flags to Dial, e.g. `$D launch -- --perf-automation --perf-automation-no-quit`.

`launch` refuses when this checkout's copy is already running, or when another checkout's Dial Verify runs (they share one preferences domain). Teardown is `$D stop` or `$D clean`.

## Doctor

`$D doctor` is read-only. Run it first, and again whenever anything looks off; exit 0 means the instance is worth driving. It checks that:

- the copy is a signed `com.dial.Dial.verify`, built from HEAD, with no newer source files;
- the PID is the one `launch` started, and no other Dial Verify runs;
- the process has the verify database open and nothing in the real Dial's folder;
- the database has the newest migration (it prints play and counted-play totals);
- the copy has windows on screen;
- Spotify is signed in or out inside the copy;
- every Last.fm file is empty, so Last.fm is blocked.

It also notes the real Dial's PID and leaves it alone.

## Drive

Use the user's own path; each feature file names it.

1. **Headless modes.** `$D cli <flags>` runs one of Dial's command-line modes against the copy's home and saves its cmd, stdout, stderr and exit code: `--import <folder>`, `--export-archive <file>`, or `--merge-archive <file> [--dry-run] [--source-name <name>]`. An import or a real merge refuses while the copy's app is running (same bundle id), so run `$D stop` first. To act as a second Mac, set `DIAL_VERIFY_HOME=.build/verify/home-<name>` on `seed` and `cli`.
2. **Accessibility (`bin/dialax.swift`, compiled on first use).** `$D ax tree` prints the tree. `$D ax press "<text>"` presses the one pressable element whose title, label, help or identifier contains the text; `--exact` matches the whole title or label instead. Either way it refuses when several match, and lists them. It needs the Accessibility grant of the app running your shell. Pressing is what VoiceOver does, which for a few controls is a different code path from a mouse click (see desktop-memory.md).
   - The menu bar item: `AXMenuBarItem/AXMenuExtra label="Dial, nothing playing"` (playing: `Dial, now playing: <track> by <artist>`). `$D ax press "Dial, "` opens the HUD.
   - Dial Settings: `AXWindow title="Dial Settings"`, with sidebar buttons `General`, `Menu Bar`, `HUD` and `Pet`. Each switch is a button whose value is `On` or `Off`, e.g. `label="Launch at login" value="Off"`. Labels repeat: General has two `Connect` buttons (Spotify's and Last.fm's), and "menu bar" appears in help texts, so use `--exact` or more of the help text.
   - The desktop memory object: `AXWindow/AXSystemDialog`, then `AXButton label="Not playing." help="Opens Dial."`.
   - Once, minutes after a launch on 2026-11-01, every Dial window (the real Dial's too) read as the application element. `ax tree` then printed only the menu bar item and a line saying how many windows it couldn't see into. A later run showed the full tree, and the cause wasn't found. If you see that line, wait and run it again.
   - Pressing is UI control. If the user declined UI control of Dial Verify, ask before you press.
3. **computer-use** (Claude desktop app) for screenshots, clicks by coordinate and drags. Call `request_access` with `com.dial.Dial.verify`, then use `app_list_windows`, `app_screenshot` and `app_click`. If the user declines, don't route around it: report those journeys as blocked.
4. **State.**
   - `$D windows` lists id, level and frame. Levels: −20 desktop memory, 3 Settings while floating, 0 a normal window, 25 menu bar, 101 the HUD panel (440×440) or a menu.
   - `$D db "<sql>"` is a read-only query.
   - `$D prefs [key]` reads the copy's preferences.
   - `$D logs [10m]` shows the copy's unified log.
   - `$D set-pref <key> <type> <value>` sets up a precondition while the copy is stopped. It never proves a setting works; flip the switch in Settings for that.

## Evidence

Each run keeps its evidence in `$($D evidence)`, which is `.build/verify/artifacts/<run-id>/`. A run lasts from `launch --fresh` (or the first launch after `clean`) to `clean`, and `clean` never deletes evidence.

- `cli` saves `cli-NN-<mode>.{cmd,stdout,stderr,exit}` there.
- `$D snap <name>` saves `<name>.txt` with the windows, the accessibility tree, the copy's preferences, and database counts (plays, counted plays, newest counted play, imports, merges, pet). Take one before an action and one after.
- `$D shot <desktop|hud|settings|window-id> <name>` saves a PNG, but only when the app running your shell has Screen Recording; it checks first. Without it, look with computer-use `app_screenshot` and describe what you saw in the report.
- Save query results next to them: `$D db "…" | tee "$($D evidence)/<name>.txt"`.

What counts as proof:

- Drive the user's path: the menu bar item, a click, a Settings switch, or a documented CLI flag. `set-pref` and SQL writes don't count.
- Capture the action and the state it leaves, before and after.
- Check side effects as well as what's visible: rows in `plays`, `counted_plays` and `archive_merges`, `plays.origin`, files in `Backups/`, preference keys.
- Don't trust a dry run's word: compare counts and the database folder before and after it.
- User-facing numbers come from `counted_plays`, not `plays` (see AGENTS.md).
- Report a path you couldn't reach with the command you tried and the precondition that was missing. Don't count it as verified through another path.

## Cleanup

`$D stop` stops only the PID in `.build/verify/run/pid`, after checking that it is still the Dial Verify binary. It never kills by name and never touches the real Dial. `$D clean` also deletes:

- the copy;
- every `.build/verify/home*`;
- the `com.dial.Dial.verify` preferences, caches and saved state.

It keeps `.build/verify/artifacts/`. Run `clean` after a failed attempt too. It leaves on purpose any privacy grants the user gave Dial Verify; resetting them is the user's call (`tccutil reset All com.dial.Dial.verify`).

## Helpers

| File | How to run it | What it does |
|---|---|---|
| `bin/dialctl` | `$D help` | everything above |
| `bin/dialax.swift` | through `$D windows`, `$D ax …` | windows via CGWindowList; accessibility tree and press |
| `bin/synth-history.py` | through `$D seed`, or `python3 -I .claude/skills/verify-dial/bin/synth-history.py --out <file> [--plays N] [--days N] [--label NAME]` | made-up Extended Streaming History; `--label` gives a separate catalog, e.g. another Mac's |

## Gotchas

- **Settings at launch.** Signed out, Dial opens Dial Settings at launch, floating above every window and taking focus (`present` in `AppDelegate.swift`). Stop the copy as soon as you're done.
- **HUD needs Spotify.** Signed out, the HUD shows only the connect view (`ConnectSetupView`, with "Open Settings"). The History, Stats and Pet screens and every live-track state need someone to sign in to Spotify inside Dial Verify first, and only the user can do that.
- **Two of everything on screen.** While the copy runs there are two Dial menu bar items and two desktop objects. Both objects default to the bottom-right corner, with the copy's on top. To move the copy's object, stop it and run `$D set-pref settings.desktopMemoryCorner string topLeft`.
- **Shortcuts.** The ⌃⌥⌘ shortcuts are global and normally belong to the real Dial. Don't verify shortcuts while the real Dial runs.
- **Signed-in copy.** Once someone signs in, the copy polls the same Spotify account, and its transport controls play, pause and skip the user's real playback. Never press them unasked.
- **Last.fm.** Never connect Last.fm in the copy: it would scrobble the user's live plays a second time. Doctor fails if any Last.fm file has content.
- **Launch at login.** Turning on Launch at login in the copy's Settings registers `Dial Verify.app` as a real login item. Turn it off again before `clean`.
- **Perf automation.** Don't create `/tmp/dial-perf-automation`: every running Dial reads it, the real one too. Pass `-- --perf-automation` to `launch` instead. Perf automation goes through internal entry points, so it's a smoke check that every screen renders, not proof of a user path.
- **`killall Dial`.** Dial's "already running" message suggests `killall Dial`. Never run it: it kills the user's real Dial along with the copy. Use `$D stop`.
- **Pipes.** Don't pipe `dialctl` into `head` inside a `set -o pipefail` chain. The early close kills it with SIGPIPE (exit 141) and stops the chain. Redirect to a file instead.
- **Stale copy.** The copy is whatever the last `$D build` made, and doctor flags a stale one. Rebuild after every code change.
- **Pixels.** `scripts/dev.sh snapshot` (AGENTS.md) still owns how the HUD looks. This skill proves behavior in the running app.

## Feature map

`features/README.md` indexes the features, with one recipe each. Drive the matching file. A proof that covers only one convenient entry point is incomplete when the map lists more. Keep the map current with `/pstack:maintain-verification-skill`.
