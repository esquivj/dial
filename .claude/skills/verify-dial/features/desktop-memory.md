# Desktop memory

A small piece of Dial hardware on the desktop: the current album in a smoke-gel frame with a three-line LCD that says what the track means to you. It sits under every app window, shows on every Space, opens the HUD when clicked, has a right-click menu, snaps to the nearest corner when dragged, and can be switched off in Settings or with ⌃⌥⌘M. Spec, including every state: `docs/design/desktop-memory.md`.

## Sub-features

- `dm-present`: the object appears at launch when Settings › Menu Bar › Desktop memory is on (the default).
- `dm-state-fresh`: on a fresh launch with nothing known, it shows the Dial app icon and `NOT PLAYING`.
- `dm-states-live`: Playing, Paused, `NOW PLAYING` while a memory loads, and Not playing with the last track dimmed. These need live playback.
- `dm-click`: a click opens the HUD.
- `dm-voiceover`: one VoiceOver element whose label starts `Not playing.`, `Now playing.` or `<Memory>: <line>.`, with the hint "Opens Dial."; VO-Space opens the HUD.
- `dm-menu`: right-click shows `Open Dial` and `Hide Desktop Memory`.
- `dm-snap`: a drag snaps to the nearest corner of the display it was dropped on, and Dial remembers that corner.
- `dm-setting`: the Settings switch hides and shows the object.
- `dm-shortcut`: ⌃⌥⌘M toggles it from any app and flashes `DESKTOP MEMORY ON` or `DESKTOP MEMORY OFF` under the menu bar item.

## How to get to it (user POV)

- Look at the desktop: by default it sits in the bottom-right corner of the main display, 20 pt inside the menu bar and Dock.
- Click it, right-click it, or drag it.
- Dial Settings › Menu Bar › Display › `Desktop memory` ("Keep the current album and what it means to you on your desktop, under your windows.").
- Press ⌃⌥⌘M anywhere.

## Driving it with dialctl

Preconditions:

- The baseline: Dial Verify launched with `--fresh --seed`, signed out.
- Steps that click or drag need computer-use access to `com.dial.Dial.verify`, granted by the user.

- **Present (`dm-present`).** Run `$D windows`. It lists one row with level `-20`, size `256 × 328` (the 216×288 object plus a 20 pt shadow margin) and `what` = `desktop memory`, at the bottom-right of the main display. On 2026-11-01 that was `2304,1046` on a 2560-wide display. Save it with `$D snap dm-present`.
- **Fresh state (`dm-state-fresh`).** Run `app_screenshot` on `com.dial.Dial.verify` with that window id. It shows the Dial icon in the art well and `NOT PLAYING` on the LCD. Not driven yet.
- **Click (`dm-click`).** Run `app_click` at the window's center by coordinate. `$D windows` then gains a level-101 `HUD panel` (440×440). Signed out, it shows the connect view (see hud.md). Not driven yet.
- **VoiceOver press (`dm-voiceover`).** `$D ax tree` shows `AXWindow/AXSystemDialog`, then `AXButton label="Not playing." help="Opens Dial." [AXPress]`; that was seen 2026-11-01. Run `$D ax press "Opens Dial."`, and the HUD panel appears in `$D windows`. That is VoiceOver's action (`DesktopMemoryView.onOpen`), not the click path. Not pressed yet.
- **Settings switch (`dm-setting`).** In Dial Settings, choose the `Menu Bar` tab and turn `Desktop memory` off. Then `$D prefs settings.showDesktopMemory` gives `0`, and `$D windows` has no `-20` row. Turn it back on, and the pref gives `1` and the row returns. Not driven yet.
- **Drag and snap (`dm-snap`).** Run `app_drag` from the object's center to a point near the display's top-left. After release, `$D windows` shows it in the top-left corner, and `$D prefs settings.desktopMemoryCorner` gives `topLeft`. Not driven yet.
- **Right-click menu (`dm-menu`).** Background computer-use refuses context menus, so this needs full-screen control, which the user must approve. Choosing `Hide Desktop Memory` should make the pref `0` and remove the window. Not driven yet.
- **Shortcut (`dm-shortcut`).** This is only meaningful when the real Dial isn't running. Press ⌃⌥⌘M. The `-20` row goes away and the `DESKTOP MEMORY OFF` flash appears under the copy's menu bar item. Press it again and the row returns with `DESKTOP MEMORY ON`. Not driven yet.

## Gotchas

- While the copy runs there are two objects, and both default to the bottom-right, with the copy's on top. To tell them apart on screen, stop the copy, run `$D set-pref settings.desktopMemoryCorner string topLeft`, and launch again. Don't do that before verifying `dm-snap` or the default corner.
- A click and a VoiceOver press take different paths: the AppKit host view handles the mouse (click versus drag), and the SwiftUI element has its own press action. Proving one doesn't prove the other.
- The real Dial normally owns ⌃⌥⌘M, so pressing it toggles the user's own object. Don't verify `dm-shortcut` while the real Dial runs.
- `dm-states-live` needs someone to sign in to Spotify inside Dial Verify. Until then, report those states as blocked.
- The window sits below every app window, so a full-screen screenshot rarely shows it. Capture the window itself with `app_screenshot` (or `$D shot desktop <name>` when the shell has Screen Recording).
