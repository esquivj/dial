# HUD

Clicking Dial's menu bar item opens the HUD: a 440×440 panel under the menu bar with the current track, its personal stats, transport controls and the pet. From the HUD, the user can open the History, Stats and Pet screens and come back with Back. Signed out of Spotify, the HUD shows only a connect view. Right-clicking the menu bar item opens a menu instead. The HUD's shape is locked: read `HUD_LOOK_LOCK.md` before changing anything in it.

## Sub-features

- `hud-item-label`: the menu bar item says what's playing to accessibility. Its label is `Dial, nothing playing`, `Dial, now playing: <track> by <artist>` or `Dial, paused: …`, and its help is "Click to open Dial. Right-click for more options."
- `hud-open`: a click on the menu bar item opens the HUD panel, and another click closes it.
- `hud-connect`: signed out, the HUD shows the connect view with an `Open Settings` button.
- `hud-now-playing`: the track hero, the readouts (`Year to date track plays N`, `Last played …`) and the controls (`Previous track`, `Next track`, `Playback position`).
- `hud-screens`: `Open listening history`, the stats surface, `Open pet`, and `Back`.
- `hud-stats-range`: the Stats screen's range buttons, labeled `<range> stats range`.
- `hud-menu`: the right-click menu: `Dial <version>`, `Settings…`, `Open History`, `Open Stats`, `Open Pet`, `Restart Current Track`, `Quit Dial`.

## How to get to it (user POV)

- Click Dial's item in the menu bar.
- With VoiceOver, move to the menu bar item and press VO-Space.
- Right-click the menu bar item, then choose `Open History`, `Open Stats` or `Open Pet`.
- Click the desktop memory object (see desktop-memory.md).

## Driving it with dialctl

Preconditions:

- The baseline: Dial Verify launched with `--fresh --seed`.
- `hud-now-playing`, `hud-screens` and `hud-stats-range` also need someone to sign in to Spotify inside Dial Verify (General › Connect), and only the user can do that.
- Opening the panel is UI control. Get the user's OK for `ax press` or computer-use first.

- **Menu bar item (`hud-item-label`).** Run `$D ax tree`. The first two lines are `AXMenuBar …` and `AXMenuBarItem/AXMenuExtra label="Dial, nothing playing" help="Click to open Dial. Right-click for more options." … [AXPress]`. Driven 2026-11-01, signed out.
- **Open (`hud-open`).** Run `$D snap hud-before`, then `$D ax press "Dial, "`. It prints `pressed: AXMenuBarItem/AXMenuExtra label="Dial, nothing playing" …`. `$D windows` then gains a level-101 `HUD panel` (440×440); save `$D snap hud-open`. Press again, and the row goes away. Not driven yet.
- **Connect view (`hud-connect`).** With the panel open and the copy signed out, `app_screenshot` the HUD panel window. It shows the connect view and `Open Settings`. Click `Open Settings`, and `$D windows` gains the Settings window. Not driven yet.
- **Screens (`hud-screens`, `hud-stats-range`).** Signed in, open the HUD and choose `Open listening history`. The History screen lists recent plays. Compare it with `$D db "SELECT t.name FROM counted_plays c JOIN tracks t ON t.uri = c.track_uri ORDER BY c.played_at DESC LIMIT 5"`. Choose `Back`, then the stats entry ("Open the stats surface for the full library view."). Each `<range> stats range` button changes the totals; compare them with `counted_plays` for that range. Choose `Open pet`; it shows `Room`, `This week`, `Memories`, `Bond N%` and `Evolution progress`. Not driven yet.
- **Right-click menu (`hud-menu`).** Background computer-use refuses context menus, so this needs full-screen control, which the user must approve. Choose `Open Stats`, and the HUD opens on the Stats screen. Not driven yet.
- **Smoke, not proof.** `$D stop`, then `$D launch -- --perf-automation --perf-automation-no-quit` cycles the HUD, History, Stats, Pet and HUD through internal entry points, then the Settings tabs. Watch `$D windows` and `$D logs 2m` for the panel and for errors.

## Gotchas

- Signed out, every screen shows the connect view, including under perf automation. The seed alone can't reach `hud-now-playing` or the screens; report them as blocked on a Spotify sign-in.
- Signed in, the controls and `Restart Current Track` act on the user's real Spotify playback. Don't press them unless the user asked.
- What accessibility shows inside the open HUD panel hasn't been recorded yet. Run `$D ax tree` with the panel open and add the handles here.
- While the copy runs there are two Dial items in the menu bar. `$D ax press` only searches the copy's own item, but a screenshot shows both: the copy's is the one at the frame `ax tree` prints.
- Never fix a layout or art problem found here by moving UI (`HUD_LOOK_LOCK.md`). Report it instead, with the screenshot.
