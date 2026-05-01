# HUD Look Lock

Date locked: 2026-04-30

This is the canonical respawn point for the Dial HUD shell and overlay placement. If the HUD ever feels broken, shifted, pasted-on, or less like a real smoked-plastic object, restore this document before trying new design work.

## Locked Take

The current HUD is the target:

- A 440 x 440 smoked black translucent Y2K/Digivice-style plastic device.
- SwiftUI content sits inside image-generated hardware wells. It must feel inset into the shell, not drawn over a generic window.
- The generated shell must remain visible around the top rail, LCD well, side rails, transport well, screws, lips, seams, and bottom hardware.
- Black coverage belongs inside the generated chassis/underlay. Do not add big SwiftUI black rectangles on top of the shell.
- Smoke/classic is black, white, chrome, gray, and clear plastic only. No blue/cyan shell cast in the default material.
- Track title owns the hierarchy. Hardware should frame the music, not compete with it.

## Shell Fit Rule

Before any UI change inside the dropdown, inspect the active shell aperture first. The SwiftUI content must fit the generated hardware cutouts; it does not get to invent a taller card stack because a new feature wants a row.

For full-shell screens like Pet, Stats, and History:

- Start from `MarketingAssets/frame-system/hardware-blueprint.json` and `Dial.Layout.Dropdown`.
- Keep the shell lip, side rails, screws, seams, and bottom reflections visible.
- If a new row is added, merge or remove another row unless the user explicitly asks to reopen shell geometry.
- A recorded snapshot is not enough if the baseline was recorded after a broken layout. Check the screenshot against the physical cutout before accepting it.

## Do Not Move

Do not change these unless the user explicitly asks to reopen HUD geometry:

```swift
// Dial/DesignSystem/DialLayout.swift
enum Dropdown {
  static let width: CGFloat = 440
  static let height: CGFloat = 440
  static let contentWidth: CGFloat = 410
  static let contentHeight: CGFloat = 410
  static let cornerRadius: CGFloat = 36
  static let panelHorizontalPadding: CGFloat = 10
  static let hudScreenHorizontalPadding: CGFloat = 14
  static let outerTopPadding: CGFloat = 8
  static let hudTopChromeHeight: CGFloat = 37
  static let hudRailScreenGap: CGFloat = 8
  static let hudScreenHeightWithTransport: CGFloat = 246
  static let hudScreenHeightWithoutTransport: CGFloat = 348
  static let hudScreenTransportGap: CGFloat = 12
  static let hudTransportHeight: CGFloat = 74
  static let hudRailContentYOffset: CGFloat = 6
  static let hudBottomPaddingWithTransport: CGFloat = 17
  static let hudBottomPaddingWithoutTransport: CGFloat = 9
  static let fullScreenVerticalPadding: CGFloat = 9
  static let hudContentTopPadding: CGFloat = 24
  static let hudContentBottomPadding: CGFloat = 0
  static let shellSpacing: CGFloat = hudRailScreenGap
  static let outerBottomPadding: CGFloat = hudBottomPaddingWithTransport
}

enum StatusRail {
  static let contentWidth: CGFloat = 340
  static let railHeight: CGFloat = 34
  static let spacing: CGFloat = 6
  static let horizontalPadding: CGFloat = 16
  static let verticalPadding: CGFloat = 1
  static let ledSize: CGFloat = 5
  static let iconSize: CGFloat = 12
  static let hitSize: CGFloat = 27
}

enum Transport {
  static let stackSpacing: CGFloat = 6
  static let padding = EdgeInsets(top: 16, leading: 11, bottom: 0, trailing: 11)
  static let scrubberYOffset: CGFloat = 11
  static let buttonRowYOffset: CGFloat = 7
  static let panelHorizontalPadding: CGFloat = 10
  static let edgeButtonInset: CGFloat = 38
  static let clusterSpacing: CGFloat = 14
  static let iconHitSize: CGFloat = 40
  static let scrubberTimeWidth: CGFloat = 38
  static let scrubberSpacing: CGFloat = 8
  static let scrubberHeight: CGFloat = 13
  static let trackHeight: CGFloat = 4
  static let thumbRestingSize: CGFloat = 6
  static let thumbActiveSize: CGFloat = 8
  static let minButtonRowHeight: CGFloat = 32
  static let secondaryPillWidth: CGFloat = 36
  static let secondaryPillHeight: CGFloat = 26
  static let prominentPillWidth: CGFloat = 44
  static let prominentPillHeight: CGFloat = 30
}
```

Important: `hudRailContentYOffset = 6` is an optical correction. Do not "fix" it back to geometric center just because the math looks uneven.

## Hardware Blueprint

`MarketingAssets/frame-system/hardware-blueprint.json` must remain aligned to the SwiftUI constants:

```json
{
  "version": 1,
  "scale": 2,
  "canvas": { "width": 440, "height": 440, "radius": 36 },
  "content": { "x": 15, "y": 15, "width": 410, "height": 410, "radius": 30 },
  "shell": { "x": 2, "y": 2, "width": 436, "height": 436, "radius": 36 },
  "rail": { "x": 50, "y": 25, "width": 340, "height": 34, "radius": 10 },
  "hudLcd": { "x": 24, "y": 68, "width": 392, "height": 246, "radius": 10 },
  "hudTransport": { "x": 24, "y": 326, "width": 392, "height": 74, "radius": 8 },
  "hudNoTransportLcd": { "x": 24, "y": 68, "width": 392, "height": 348, "radius": 10 },
  "fullLcd": { "x": 24, "y": 24, "width": 392, "height": 392, "radius": 11 },
  "occlusion": {
    "outerLip": 14,
    "apertureLip": 5,
    "transportLip": 5
  }
}
```

## Layer Order

`Dial/Views/Dropdown/DropdownView.swift` should layer hardware like this:

1. `shell-\(skin)-chassis`
2. `shell-\(skin)-wells-*` at theme-specific opacity
3. SwiftUI HUD contents
4. `shell-\(skin)-apertures-*`
5. `shell-\(skin)-reflections`

Current wells opacity:

```swift
case .classic: return 0.42
case .slime:   return 0.34
case .aqua:    return 0.30
case .ember:   return 0.32
```

There should be no `shell-*-backplate-*` image layer and no large SwiftUI blackplate over the shell. The dark fill that prevents desktop bleed is baked into `shell-*-chassis`.

## Asset Generation Rules

`scripts/generate-hardware-assets.py` is the source for the shell asset split.

Keep these rules:

- Trim every generated asset to the real shell silhouette. No black pixels outside the shell.
- Preserve transparent exterior outside the shell.
- Bake dark socket fills into the chassis under the render, not over the SwiftUI UI.
- Keep aperture/reflection layers above content so the shell feels like real plastic sitting over inset panels.
- Keep wells subtle. They are texture and LCD depth, not a replacement for the shell render.
- Do not let desktop/background imagery show through the rail, LCD well, or transport well.

The current socket underlap values are part of the lock:

```python
rail bottom underlap: 10
lcd bottom underlap: 16
transport bottom underlap: 13
```

## Visual Checklist

Before calling the HUD "fixed", check this against a screenshot:

- Outer shell reaches the full 440 x 440 footprint and has no stray black pixels outside the plastic.
- Top rail sits inside the upper plastic bay, not halfway through bolts or seams.
- Middle LCD content has left/right breathing room and does not cover too much side plastic.
- Transport scrubber and buttons have separation; the scrubber is not kissing the button row.
- Bottom transport well sits inside the shell, with plastic still visible below and around it.
- No old SwiftUI rounded container outline floats over the generated shell.
- No desktop/background stripes leak through the rail, main LCD, transport, or bottom socket.
- Buttons keep the good gel look: black/chrome, rounded, small, and not blown out.
- Shell detail is visible but not noisy. If it disappears, the SwiftUI overlay is too heavy.

## Verification Commands

For a shell-only restore, regenerate assets first:

```bash
python3 scripts/generate-hardware-assets.py
```

Build the app:

```bash
xcodebuild -project Dial.xcodeproj -scheme Dial -configuration Debug build
```

Install/relaunch the local app:

```bash
rm -rf /Applications/Dial.app
/usr/bin/ditto ~/Library/Developer/Xcode/DerivedData/Dial-dovdrsveecvppcfpkxbonieehptx/Build/Products/Debug/Dial.app /Applications/Dial.app
open -a /Applications/Dial.app
```

Only run `xcodegen generate` if resource files are added or removed from the project definition. Normal shell regeneration should not require project regeneration.

## If It Breaks

The recovery order is:

1. Restore the `Dial.Layout.Dropdown`, `StatusRail`, and `Transport` constants above.
2. Restore `MarketingAssets/frame-system/hardware-blueprint.json`.
3. Regenerate hardware assets with `scripts/generate-hardware-assets.py`.
4. Verify the HUD screenshot against the visual checklist.

Do not "fix" a shell issue by moving UI placement. That is how this got painful.
