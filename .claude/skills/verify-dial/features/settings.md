# Settings

Dial Settings is a 700×572 window with four tabs: General, Menu Bar, HUD and Pet. General holds Spotify, listening history import, Last.fm, Launch at login and shortcuts. Menu Bar holds the menu bar display and the desktop object. HUD holds the HUD theme and readouts, and Pet the pet. A switch takes effect at once and is saved in Dial's preferences. When Dial launches signed out of Spotify, it opens Settings by itself, floating above other windows, so the user can connect.

## Sub-features

- `set-open-launch`: signed out, Settings opens at launch, floating (level 3) and focused.
- `set-open`: `Settings…` (⌘,) in the menu bar item's right-click menu, or `Open Settings` in the signed-out HUD.
- `set-tabs`: the sidebar switches between `General`, `Menu Bar`, `HUD` and `Pet`.
- `set-switch`: a switch writes its preference immediately. For example, Menu Bar › `Desktop memory` writes `settings.showDesktopMemory`, `Live Dock artwork` writes `settings.showDockArtwork`, and `Show album art` writes `settings.showAlbumArtInMenuBar`.
- `set-spotify`: General › `Connect` ("Connect Spotify so Dial can read playback and liked tracks.") signs in through the browser.
- `set-lastfm`: General › Last.fm › `Connect`.
- `set-login`: General › `Launch at login`.
- `set-import`: General › Listening history › `Import Folder` (see history-import.md).

## How to get to it (user POV)

- Launch Dial signed out.
- Right-click Dial's menu bar item and choose `Settings…`, or press ⌘, while Dial is active.
- In the signed-out HUD, choose `Open Settings`.

## Driving it with dialctl

Preconditions:

- The baseline: Dial Verify launched with `--fresh --seed`, signed out.
- Pressing anything is UI control: get the user's OK for `$D ax press`, or their computer-use grant for `com.dial.Dial.verify`.

- **Opens at launch (`set-open-launch`).** Run `$D launch --fresh --seed`. The window table has a level-3 row, 700×572, with `what` = `Settings (floating)`, next to the desktop memory row. Driven 2026-11-01.
- **What General shows.** `$D ax tree` lists the window as `AXWindow/AXStandardWindow title="Dial Settings"`, with sidebar buttons `General`, `Menu Bar`, `HUD` and `Pet`. Signed out, General shows `Spotify offline`, a `Connect` button, `No history folder imported.` with `Import Folder`, `Last.fm not connected`, `Launch at login` (value `Off`), and the shortcut buttons with their chords, e.g. `Show / hide desktop memory shortcut` = `Control Option Command M`. Seen 2026-11-01 (`snap mm-baseline`).
- **Tabs (`set-tabs`).** Run `$D ax press --exact "Menu Bar"`. `$D ax tree` then shows `Show album art`, `Live Dock artwork` and `Desktop memory` as buttons with values. Not driven yet.
- **A switch (`set-switch`).** Run `$D prefs settings.showDesktopMemory`; on a fresh home the key is not set, and the default is on. Run `$D ax press --exact "Desktop memory"`, or click it with computer-use. The pref now gives `0`, the button's value reads `Off`, and `$D windows` loses its `-20` row. Press it again, and the pref gives `1` and the row returns. Save `$D snap` before and after. Not driven yet.
- **Spotify (`set-spotify`).** Only the user can sign in: hand over the copy with Settings open on General. Proof after they sign in: doctor says `Spotify: signed in inside Dial Verify`, and the menu bar item's label follows playback. Not driven yet.
- **Reopen (`set-open`).** Close the window, then use the right-click menu's `Settings…`; that needs full-screen control, because background computer-use refuses context menus. The window returns at level 3. Not driven yet.

## Gotchas

- At launch the floating window covers the user's work and takes focus. Stop the copy when you're done; closing the window also works.
- Never use `Connect` in the Last.fm section of the copy. It would scrobble the user's live plays twice, and doctor fails once any Last.fm file has content.
- `Launch at login` in the copy registers `Dial Verify.app` as a real login item. If a journey turns it on, turn it off before `clean`.
- `$D set-pref` is refused while the copy runs, because Dial reads preferences at launch. Use it only to set up a precondition, and prove a switch by clicking it.
- Theme ids aren't display names: `ember` shows as "Magenta" and `classic` as "Smoke Gel".
