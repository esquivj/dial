# Desktop memory

A small piece of Dial hardware that lives on the desktop: the current album in a smoke-gel frame, with one LCD line saying what the track means to you. It answers `PRODUCT.md`'s "album-art presence as a dedicated macOS object" (the Sleeve reference, see `docs/references/sleeve.md`) without turning Dial into a mini-player.

Status: v1, 2026-10-19. Change this file first when a decision here changes.

## What it is, and isn't

- It is a memory object. The album art is the hero, and the LCD says why this track matters (the same memory the track-change pop-up shows) or, failing that, how often you've played it this year.
- It is not a remote. No transport, scrubber or spectrum. Clicking it opens the HUD, which already has the controls.
- It sits under every app window, like something on your desk. It never floats over your work and never takes focus.

## Anatomy

One size in v1: a 216 × 288 pt object (plus a 20 pt shadow margin on every side of the window).

- **Chassis:** smoke-gel plastic (`dialChassisPlastic`) at `Dial.Radius.device`, 12 pt padding.
- **Album art:** 192 pt square in the media frame (`dialMediaFrame`, `Dial.Radius.media`). At this size the HUD's small corner glare reads as a pale block, so the frame turns it off and the cover gets a soft diagonal sheen instead.
- **LCD well:** the same recessed LCD as the memory pop-up (`LCDReadoutWell`: scanlines, recessed screen, `lcdPanel`), 62 pt tall, 10 pt below the art. The memory pop-up and the desktop object share this part, so they read as the same device.
- **Contact shadow:** a soft black shadow under the chassis so it sits on the wallpaper. The window itself has no system shadow.

## LCD content

Three rows, one line each with tail truncation (the One-Line Rule).

**Row 1, the stamp**, first match wins:

1. The track has a pop-up memory: the same kinds and the same Settings switches as memory pop-ups (first listen, new artist, rediscovered, deep cut, 10th/50th/100th play, anniversary). Badge sprite and stamp as in `MemoryPopupView`, e.g. `REDISCOVERED`. Stamp colors follow the HUD badge mapping: pink for first listen and new artist, the cartridge accent for rediscovered and deep cut, primary text for milestones.
2. Otherwise, the year-to-date readout `TRACK · YTD`, in the cartridge accent.

When paused, a muted `PAUSED` tag sits at the right end of this row.

Streaks, repeats and album runs stay in the HUD, as they do for pop-ups: they describe the session, not a memory.

**Row 2, the memory line:** the pop-up's line (`Last played Mar 2023`), or `12 plays this year` (`1 play this year`, `First play this year`), in primary text.

**Row 3, the track:** `Title · Artist` in muted text. If that doesn't fit, it shows the title alone rather than ending in `· …`.

## States

| State | Art | Row 1 | Row 2 | Row 3 |
|---|---|---|---|---|
| Playing | full | memory or `TRACK · YTD` | memory line | `Title · Artist` |
| Paused | 55% | same, plus `PAUSED` at the right | memory line | `Title · Artist` |
| New track, memory still loading | full | `NOW PLAYING` (accent) | title | artist |
| Not playing, last track known | 40% | `NOT PLAYING` (muted) | last title | last artist |
| Not playing, nothing known (fresh launch) | Dial app icon | `NOT PLAYING` (muted) | empty | empty |
| Artwork missing or failed | music-note fallback (as `TrackHero`) | unchanged | unchanged | unchanged |

When Spotify stops or quits, the object keeps the last track, dimmed, so it never pops in and out.

A new track's memory (badge, plays, last played) lands a moment after the track itself. Until `AppCoordinator.aggregatesTrackUri` matches the track, the LCD says only `NOW PLAYING`, so the previous track's memory never shows on the new one.

## Placement and window

- **Level:** a borderless, non-activating panel at window level −20, `CGWindowLevelForKey(.backstopMenu)`. That is above the desktop and its icons and below every app window.
- **Behavior:** `[.canJoinAllSpaces, .stationary, .ignoresCycle]`. It shows on every Space, stays put in Mission Control and Show Desktop, and never becomes key or main.
- **Anchors:** the four corners of a display's visible area (inside the menu bar and Dock), inset 20 pt. Default: bottom-right of the main display, away from where desktop icons start.
- **Moving:** drag it anywhere; on release it snaps to the nearest corner of the display it was dropped on. Dial remembers the corner and the display; if that display is gone, it uses the main display.
- **Click:** opens the HUD, the same as clicking the menu bar item.
- **Right-click:** a menu with Open Dial and Hide Desktop Memory (turns the setting off).
- **Shortcut:** ⌃⌥⌘M shows or hides it from any app (see Settings below).

## Theme, motion, accessibility

- Follows the HUD theme, like memory pop-ups (`AppCoordinator.readoutTheme`).
- Track changes crossfade art and text in 0.22 s (as `TrackHero`); the snap animates in 0.2 s. Both are instant with Reduce Motion.
- No timers, meters or progress: it redraws only when the track, play state or memory changes.
- One VoiceOver element: "Rediscovered: Last played Mar 2023. Kiss Me Thru the Phone · Soulja Boy", button trait, hint "Opens Dial."
- State is never color alone: stamps are words (plus a sprite for memories), and paused or not playing are words plus dimming.

## Settings and shortcut

Menu Bar › Display, next to Live Dock artwork: **Desktop memory**, "Keep the current album and what it means to you on your desktop, under your windows." On by default.

General › Shortcuts: **Show / hide desktop memory** flips that switch from any app. Default ⌃⌥⌘M (M for memory), on the same ⌃⌥⌘ chord as Dial's other shortcuts; it can be re-recorded or cleared like them. Each press flashes the new state in words under the menu bar item: `DESKTOP MEMORY ON`, or `DESKTOP MEMORY OFF` in muted text. The object sits under your windows, so when they cover it the flash is the only sign the press worked. As with every shortcut flash, there's none while the HUD is open.

## Not in v1

Transport or hover controls, free placement, a second size, hiding from screen recordings, per-Space positions.

## Verification

- Unit tests for the LCD content rules and for snapping (nearest corner, visible-area insets, missing display).
- Unit tests for the shortcut: its default, routing, and the flash for each state.
- Visual baseline `dial-desktop-memory`: every state above on a light and a dark desktop.
- In the running app: under all windows, on every Space, steady through Mission Control and Show Desktop, drag and snap on both displays, click opens the HUD, right-click hides it, ⌃⌥⌘M hides and shows it with a flash.

## Code map

| File | Role |
|---|---|
| `Dial/ViewModels/DesktopMemoryContent.swift` | Pure: which lines and state to show |
| `Dial/Views/DesktopMemory/DesktopMemoryView.swift` | The object's SwiftUI view and `DesktopMemoryMetrics` |
| `Dial/App/DesktopMemoryPlacement.swift` | Pure: corners, snapping, which display a drop lands on |
| `Dial/App/DesktopMemoryController.swift` | Panel, observation, artwork, drag, menu |
| `Dial/Views/MemoryPopup/LCDReadoutStrip.swift` | `LCDReadoutWell`, the LCD both objects share |
| `Dial/ViewModels/AppCoordinator.swift` | `aggregatesTrackUri`: which track the loaded memory belongs to |
| `Dial/ViewModels/SettingsViewModel.swift` | `showDesktopMemory`, `desktopMemoryCorner`, `desktopMemoryDisplayID` |
| `Dial/Hotkeys/HotkeySettings.swift` | `HotkeyAction.toggleDesktopMemory`: the shortcut's title and default |
| `Dial/ViewModels/HotkeyActionRouter.swift` | Runs the shortcut and picks the flash |
| `Dial/App/StatusBarController.swift` | `startHotkeys`: gives the router the `showDesktopMemory` switch |
| `Dial/Views/MemoryPopup/HotkeyFlashView.swift` | `desktopMemoryOn` and `desktopMemoryOff` flashes |

Tests: `DesktopMemoryContentTests`, `DesktopMemoryPlacementTests`, the desktop memory cases in `SettingsViewModelTests`, `HotkeyActionRouterTests` and `HotkeySettingsTests`, and `VisualRegressionTests.test_desktopMemoryRendersStates`.
