---
name: "Dial"
description: "A private Y2K music memory device for Spotify history."
colors:
  ground: "#070E14"
  surface: "#12161B"
  subtle: "#0F1316"
  hairline: "#252A30"
  accent-cyan: "#1FB6FF"
  accent-pink: "#FF4DD8"
  lcd-green: "#B5BA91"
  slime-shell: "#B8FF38"
  aqua-shell: "#25C7FF"
  ember-shell: "#FF672F"
  button-yellow: "#EEC83C"
  text-primary: "#E8EBED"
  text-muted: "#898F98"
typography:
  display:
    fontFamily: "GeistMono-Medium, ui-monospace, SFMono-Regular, Menlo, monospace"
    fontSize: "20px"
    fontWeight: 500
    lineHeight: 1.1
    letterSpacing: "0"
  title:
    fontFamily: "GeistMono-Medium, ui-monospace, SFMono-Regular, Menlo, monospace"
    fontSize: "16px"
    fontWeight: 500
    lineHeight: 1.15
    letterSpacing: "0"
  body:
    fontFamily: "GeistMono-Regular, ui-monospace, SFMono-Regular, Menlo, monospace"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.25
    letterSpacing: "0"
  caption:
    fontFamily: "GeistMono-Regular, ui-monospace, SFMono-Regular, Menlo, monospace"
    fontSize: "11px"
    fontWeight: 400
    lineHeight: 1.2
    letterSpacing: "0"
  label:
    fontFamily: "GeistPixel-Square, GeistMono-Medium, ui-monospace, monospace"
    fontSize: "9px"
    fontWeight: 500
    lineHeight: 1
    letterSpacing: "1.2px"
rounded:
  pixel: "2px"
  pixel-cell: "1.5px"
  printed: "3px"
  tiny: "4px"
  media: "6px"
  control: "8px"
  transport-top: "4px"
  transport-foot: "8px"
  panel: "10px"
  lcd: "12px"
  device: "28px"
spacing:
  hairline: "1px"
  xs: "2px"
  sm: "4px"
  md: "6px"
  lg: "8px"
  xl: "10px"
  xxl: "12px"
  screen-pad: "14px"
components:
  brand-wordmark:
    asset: "Dial/Resources/Brand/dial-wordmark-chrome.png"
    description: "Canonical chrome DIAL wordmark with two integrated star decals."
    background: "transparent"
    usage: "Primary setup/onboarding mark and brand lockup source."
  brand-app-icon:
    asset: "Dial/Resources/Brand/dial-app-icon.png"
    description: "Canonical macOS app icon: dark translucent plastic squircle with two large chrome sparkle marks from the wordmark."
    background: "transparent"
    usage: "Bundle AppIcon source and Dock fallback whenever no album artwork is available."
  popup-shell:
    backgroundColor: "{colors.ground}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.device}"
    width: "360px"
    height: "360px"
  lcd-panel:
    backgroundColor: "{colors.subtle}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.panel}"
    padding: "7px 14px"
  badge-chip:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.accent-cyan}"
    rounded: "{rounded.printed}"
    padding: "4px 8px"
  pet-lcd:
    backgroundColor: "{colors.lcd-green}"
    textColor: "{colors.ground}"
    rounded: "{rounded.media}"
    size: "60px"
  menu-bar-widget:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.control}"
    height: "22px"
---

# Design System: Dial

## 1. Overview

**Creative North Star: "Pocket Music Shrine"**

Dial is a tiny physical music memory device living inside macOS. The interface should feel like a translucent Y2K keychain object with a serious utility layer inside it: part Digivice, part Tamagotchi, part hi-fi readout, part Raycast-quality menu bar tool.

The app is not a Spotify clone, not a mini-player, and not a public stats dashboard. Every surface should answer one question: what does this song mean to me? The main HUD stays dense and functional. The pet, room, artifacts, and generated sprites carry the emotional identity.

Use the generated brand board as the art-direction source: translucent plastic shells, LCD-green pixel rooms, chrome decals, yellow rubber buttons, cyan readouts, pink badge moments, black hardware grounds. Do not copy the full poster composition into the dropdown. Translate it into a compact native product.

**Final Wordmark:** `Dial/Resources/Brand/dial-wordmark-chrome.png` is the canonical Dial wordmark. It is a silver/chrome italic `DIAL` decal with two integrated chrome star marks, transparent background, and readable edge detail for dark and light surfaces. Do not substitute the cyan pixel text as the primary brand mark. Do not use generated variants with black reflection bands or missing-alpha holes through the chrome face.

**Final App Icon:** `Dial/Resources/Brand/dial-app-icon.png` is the canonical macOS icon and no-album Dock fallback. It uses a quiet dark translucent plastic squircle with the two chrome star marks from the wordmark as the only hero. Do not use a full chrome field, white arc, pet LCD, or text in the app icon. Album art can replace it when a track is playing; the fallback should stay branded, not pet/LCD/noise.

**Key Characteristics:**
- Physical, personal, precise.
- Dense but crafted, with fixed zones and strong baselines.
- Solid minimal signal over glow.
- Pixel art belongs to pets, badges, artifacts, room objects, and LCD scenes.
- Functional chrome stays clean, thick, template-based, and readable.
- The best future version feels like a private object with memory, not another music widget.

## 2. Colors

The palette is dark hardware plus powered LCD color. Cyan is live signal, pink is memory/discovery, LCD green is the pet and room world, and shell colors are reserved for skins or marketing assets.

### Primary
- **Powered Cyan** (`#1FB6FF`): active playback, current selection, readout values, spectrum bars, progress fill, primary status.
- **Hot Memory Pink** (`#FF4DD8`): first listens, new artists, rare discovery moments, liked state, badge emphasis.

### Secondary
- **LCD Green Glass** (`#B5BA91`): pet LCDs, room backgrounds, artifact screens, generated pixel scenes. This is world color, not generic success color.
- **Slime Shell** (`#B8FF38`): translucent device skin, marketing art, future skin picker. Use sparingly inside product UI.
- **Aqua Shell** (`#25C7FF`): alternate shell skin and blue hardware moments.
- **Ember Shell** (`#FF672F`): alternate shell skin. Do not let it become the default product accent.
- **Rubber Button Yellow** (`#EEC83C`): physical toy button references, onboarding/device previews, not normal app buttons.

### Neutral
- **Tinted Ground** (`#070E14`): outer chassis and app background. Never use pure black.
- **Recessed Surface** (`#12161B`): controls, panels, readouts, and popover interiors.
- **Deep Subtle Surface** (`#0F1316`): LCD panel fill and lower hierarchy surfaces.
- **Hardware Hairline** (`#252A30`): dividers and low-contrast panel borders.
- **Cool Text Primary** (`#E8EBED`): primary readable text.
- **Cool Text Muted** (`#898F98`): labels and secondary metadata. Keep this contrast high enough for tiny UI.

### Named Rules

**The Cyan Rarity Rule.** Cyan marks active state, current playback, or meaningful data. It is not decoration.

**The Pink Memory Rule.** Pink is for personal memory moments: first listen, new artist, liked, rare discovery. Do not use pink for generic hover or filler.

**The LCD World Rule.** LCD green is reserved for the pet, room, artifacts, and generated pixel scenes. Do not turn the whole HUD green.

**The No Purple Gradient Rule.** Purple-blue gradients, gradient text, blurry blobs, and generic glassmorphism are off-brand.

## 3. Typography

**Display Font:** Geist Mono Medium  
**Body Font:** Geist Mono Regular  
**Label/Pixel Font:** Geist Pixel Square

**Character:** The type should feel like a clean instrument panel, not a retro costume. Geist Mono carries useful text and data. Geist Pixel is a tiny printed/LCD accent layer for stamps, shell copy, badges, and labels.

### Hierarchy
- **Display** (500, 20px, 1.1): readout values and major numeric data.
- **Title** (500, 16px, 1.15): current track title and primary HUD text.
- **Body** (400, 12px, 1.25): secondary UI text and settings copy.
- **Caption** (400, 11px, 1.2): artist, album, helper copy, compact descriptions.
- **Label** (500, 9px, 1.0, 1.2px tracking, uppercase): section stamps, badge labels, stat labels, shell markings.

### Named Rules

**The No Fake Retro Rule.** Do not put every word in pixel type. Pixel type is seasoning. Useful reading stays Geist Mono.

**The Track First Rule.** In the main HUD, the track title owns the hierarchy. Artist and album support it. Badges explain why the track matters.

**The One-Line Rule.** Main HUD metadata should be one line each with tail truncation. Long text should never push the pet, heart, readouts, or spectrum out of alignment.

## 4. Elevation

Dial uses material layering, not generic card shadows. Depth comes from translucent plastic, recessed LCD panels, black contact shadows, hairline strokes, scanlines, and controlled white highlights. Colored glow is not the elevation system.

### Shadow Vocabulary
- **Chassis Plastic:** dark ground, vertical white top tint at `0.035`, bottom shade at `0.30`, radial corner shade at `0.38`, black inner lip at `0.32`, white top stroke at `0.62`.
- **Recessed Panel:** surface fill, white stroke at `0.30`, top sheen at `0.24`, inner shadow at `0.42`, lower shade at `0.14`.
- **Transport Tray:** quieter than normal panels: stroke `0.22`, top sheen `0.16`, inner shadow `0.32`.
- **Raised Gel:** white top fill `0.13`, bottom fill `0.035`, edge `0.30`, sheen `0.42`, black contact shadow `0.28`.
- **Printed Chip:** fill `0.045`, edge `0.22`. This should feel inked onto the device, not raised.

### Named Rules

**The Plastic Rule.** Plastic is described by white highlights, dark contact shadows, subtle translucency, and real shape. Cyan glow everywhere turns the app into mall-kiosk nonsense.

**The Recess Rule.** LCD panels and transport controls sit into the device. Use inner shadow and hairline strokes before adding external shadows.

**The Scanline Rule.** Scanlines belong inside LCD surfaces only. Do not put scanlines on menus, settings forms, or normal text areas.

## 5. Components

### Popup Shell
- **Shape:** continuous device shell, `28px` radius.
- **Size:** default dropdown is `360px` by `360px`.
- **Material:** chassis plastic with tinted black ground, subtle dust texture, white top rim, black inner lip.
- **Rule:** the shell should feel molded. If it reads like a rounded app popover, sharpen or simplify it.

### LCD Panel
- **Shape:** `10px` panel radius, `12px` for stronger LCD wells.
- **Background:** `#0F1316` or LCD green when it contains the pet/room world.
- **Behavior:** supports scanlines, crisp pixel sprites, and dense readouts.
- **Rule:** content inside an LCD can be weird and pixelated. The surrounding controls should stay clean.

### Transport Tray
- **Shape:** custom shield-bottom panel, `4px` top corners, `8px` bottom joins, shallow curved bottom.
- **Controls:** gel transport buttons use capsules, cyan icons, and black contact shadows.
- **Spacing:** center cluster stays optically centered. Shuffle and repeat stay close enough to feel part of the tray, not pinned to the edge.
- **Rule:** the tray is hardware. Do not make it a normal rounded rectangle.

### Menu Bar Widget
- **Modes:** icon-only, album art plus text, and expanded now-playing strip.
- **Text:** `Track Title · Artist`, one color, native density, no separate artist tint.
- **Sizing:** dynamic width, enough to avoid premature truncation, but not so wide it eats the menu bar.
- **Icon:** music/menu glyph should be white, thick, and legible at menu bar scale.
- **Rule:** Raycast sharpness, Dial personality. No pill that wastes horizontal space.

### Badges
- **Shape:** printed chip, `3px` radius, compact padding, mono/pixel label.
- **Color:** discovery badges usually cyan, first/new artist and pattern moments can be pink, milestones can use text-primary or special artifact color.
- **Icon Rule:** badge icons are generated pixel assets, black-on-transparent template PNGs, tinted in code.
- **Behavior:** badges should tell the user something personal about the current track. They are not achievements for their own sake.
- **Future Direction:** badge memories should also unlock artifacts.

### Readouts
- **Shape:** one shared raised rail with `8px` corners and internal dividers.
- **Content:** Plays YTD, Rank 7D, Last Played.
- **Typography:** labels use pixel label, values use mono numeric text.
- **Rule:** readouts should feel like hardware cells, not dashboard cards.

### Icons
- **Functional Chrome:** use `DialIcon` template PNGs from `Dial/Resources/Icons`. These are clean utility glyphs, not pixel art.
- **Pixel Art:** reserve for pet sprites, badges, artifacts, room objects, and LCD scenes.
- **Rendering:** functional icons can interpolate normally. Pixel sprites must use nearest-neighbor rendering.
- **Rule:** do not mix random icon families. If a new utility icon is needed, create a matching template PNG or use the existing icon pipeline.

### Generated Sprites
- **Required For:** new artifacts, room objects, badge art, pet cosmetics, room backgrounds, shrine visuals.
- **Format:** PNG, transparent background for objects and artifacts, black-on-transparent when tintable.
- **Scale:** generate at `128x128` or `256x256`, display smaller with nearest-neighbor interpolation.
- **Sheets:** prefer master sprite sheets, then slice into individual files for consistency.
- **Rule:** no new SwiftUI doodle art for collectible visuals.

### Pet Room
- **Direction:** PetView should become `ROOM`: an LCD pixel room first, then bond/action and evolution below.
- **Scene:** room background uses LCD green, black pixel art, scanlines, and simple object silhouettes.
- **Objects:** plant, stereo, shelf, lamp, framed album, rug, window, CRT/console, trophy shelf.
- **Artifacts:** first listen spark charm, new artist token, rediscovered cassette, deep cut gem, streak flame, repeat loop, album stack, play trophies, anniversary piece.
- **Rule:** pet states and room unlocks must come from real listening behavior. No fake chores.

### Settings
- **Role:** a technical tuning surface, not a brand showcase.
- **Controls:** use native-feeling toggles, sliders, segmented controls, and compact previews.
- **Rule:** settings can expose real values, but should not become a wall of unexplained knobs.

## 6. Do's and Don'ts

### Do:
- **Do** make the current track more personal on every primary surface.
- **Do** treat the HUD like hardware: fixed zones, real curvature, material logic, and functional spacing.
- **Do** keep the main HUD restrained. Let the pet, room, artifacts, and generated assets carry the emotional weight.
- **Do** use `#1FB6FF` for live signal and meaningful data, not decoration.
- **Do** use `#FF4DD8` for memory and discovery moments.
- **Do** keep muted text at or above the current `#898F98` contrast level.
- **Do** use `28px` for the device shell, `10px` to `12px` for LCD panels, `8px` for controls, `6px` for media, `3px` to `4px` for printed UI.
- **Do** render pixel assets with nearest-neighbor interpolation.
- **Do** generate new collectibles through imagegen sprite assets.
- **Do** make pet bond, energy, discovery, tricks, evolution, room objects, and artifacts listening-driven.

### Don't:
- **Don't** build a Spotify clone.
- **Don't** make Dial feel like a mini-player first. It is a private music memory device.
- **Don't** use cyan-on-dark glow everywhere with no hierarchy.
- **Don't** use purple-blue gradients, gradient text, blurry decorative blobs, or generic glassmorphism.
- **Don't** add dashboard-template metric cards just to fill space.
- **Don't** use redundant labels that restate visible data.
- **Don't** add fake chores or fake gamification disconnected from listening.
- **Don't** let decorative chrome steal space from track context.
- **Don't** make tiny controls look polished but annoying to hit.
- **Don't** create new collectible art as SwiftUI shapes when it should be a generated sprite.
- **Don't** turn the generated board into a literal screen layout. Use it as art direction, then preserve product density.
