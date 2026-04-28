# Product

## Register

product

## Users

Dial is for a single power user who listens to Spotify constantly on macOS and wants the menubar to become a personal music instrument panel. The user is already in other apps, often coding or working, and wants quick ambient context without opening Spotify or a dashboard.

The job is not just controlling playback. The job is understanding what the current track means in the user's own listening history: first listen, rediscovery, rare deep cut, repeat behavior, rank, recency, and pet progression.

## Product Purpose

Dial is a native macOS menubar companion for Spotify. It turns live playback and local listening history into a compact personal HUD, with contextual badges, YTD plays, weekly rank, last-played recency, a real-time spectrum, liked-song controls, history import, stats, and a pixel pet that grows through listening.

Dial should become a private music memory device. Not a mini-player. Not a stats dashboard. Not a public product. A tiny Y2K handheld shrine where your Spotify history becomes a pet, room, artifacts, and now-playing memories.

Success means the user can glance at the menubar or dropdown and immediately learn something personal about the current song. Dial should feel like a tiny object with memory, not another streaming widget.

## Brand Personality

Physical, personal, precise.

Dial should feel like a pocketable music device from an alternate timeline: part Digivice, part Tamagotchi, part hi-fi readout, part Raycast-quality macOS utility. It can be playful, but it should never feel childish. It can be retro, but it should not become costume nostalgia.

The tone is direct and useful. The UI can have personality through behavior, pet reactions, badges, material, and rhythm, not through explanatory text.

## Anti-references

Avoid obvious AI interface tells:

- Cyan-on-dark glow used everywhere with no hierarchy
- Purple-blue gradients, gradient text, blurry decorative blobs, and generic glassmorphism
- Dashboard-template metric cards stacked for the sake of filling space
- Redundant labels that restate visible data
- Fake chores or fake gamification disconnected from listening
- Overly large decorative chrome that steals space from track context
- Tiny controls that look polished but are annoying to hit
- Stock Spotify clone UI

Specific product references to respect, not copy blindly:

- Raycast: menubar text density, native sharpness, immediate utility
- Sleeve: album-art presence as a dedicated macOS object
- Classic Tamagotchi and Digivice hardware: small physical screen, toy-like life, pixel charm
- Linear and Figma: restraint, clear hierarchy, no wasted UI

## Design Principles

1. Make the current track more personal.
   Every primary surface should answer: what does this song mean to me?

2. Treat the HUD like hardware.
   Layout, curvature, material, controls, and spacing should feel physically intentional. If a shape looks decorative but not functional, cut it.

3. Keep the pet listening-driven.
   Pet states, bond, energy, discovery, tricks, and evolution must come from real playback behavior. No chore simulator.

4. Preserve glanceability.
   Menubar and HUD surfaces should reveal the important thing in one look. Drill-down screens can explain, but the main view should not lecture.

5. Make density feel crafted.
   The app is small by nature. Use tight grids, fixed zones, strong baselines, and carefully tuned spacing instead of expanding the window or adding filler.

6. Prefer solid, minimal signal over glow.
   Color should mark state and meaning. Material can have depth, but glare, bloom, and sheen must stay controlled.

## Accessibility & Inclusion

Target WCAG AA contrast for small text and controls. Use high enough contrast for muted metadata, especially in the menubar and tiny HUD labels.

Respect reduced motion. Pet reactions, track transitions, progress motion, and spectrum animation should degrade cleanly without breaking state feedback.

Hit targets should be larger than their visual icons where possible. The app is mouse-first, but tiny controls in the menubar and dropdown still need forgiving interaction zones.

Do not encode meaning through color alone. Badges, pet states, liked state, playback state, and permission states need shape, label, icon, or behavior support.
