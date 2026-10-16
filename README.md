# Dial

A native macOS menubar companion for Spotify. Shows what you're playing, what it means to *you* (play counts, rank, rediscoveries, first listens), and tends a tiny pixel pet that grows from an egg as you listen.

## What's in it

- **Menubar strip** — tiny pixel pet + current track + 30-day play count. Pet bobs to BPM and reacts to events (first listen pops, rediscovery floats thought-dots, streak dances).
- **Dropdown HUD** (320×360) — instrument-panel readouts: `PLAYS · YTD`, `RANK · 7D`, contextual badge chip, artist rank, last-60-min session timeline, transport controls.
- **Pet system** — 6 life stages (egg → elder), blend XP from listening time + variety + streaks, 7 animated behaviors with priority resolution.
- **Local SQLite store** — every counted play, plus tracks/artists/imports_log/pet_state. WAL journal mode, 500 ms busy timeout.
- **Spotify OAuth (PKCE)** — Keychain-stored tokens, auto-refresh on 401.
- **Extended Streaming History import** — drop your Spotify export folder on Settings; the importer is idempotent and caps imported XP at the companion threshold so a decade of history can't instantly max the pet.

## Read your listening history from other apps

Dial's saved archive has a separate read-only interface for apps and agents:
[`integrations/dial_history/README.md`](integrations/dial_history/README.md).
It provides a JSON command, authenticated local and cloud APIs, coverage information,
and portable SQLite snapshots. The cloud copy stays readable while the Mac sleeps.
After installation, start with
`~/Music/Dial/manifest.json` or `dial-history status`.

## Build & run

Requirements:

- macOS 14 (Sonoma) or later
- Xcode 15.3 or later
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

```bash
git clone <this-repo> && cd dial
./scripts/setup.sh        # installs deps check + generates Dial.xcodeproj from project.yml
open Dial.xcodeproj       # ⌘R to run
```

The Xcode project is generated from `project.yml` (committed) — never edit `Dial.xcodeproj` by hand. After adding new Swift files, re-run `xcodegen generate`.

## Spotify Developer setup

1. Register an app at <https://developer.spotify.com/dashboard>.
2. Add `dial://callback` as a redirect URI.
3. Copy the Client ID. For local dev, paste it into `project.yml` under `targets.Dial.info.properties.SpotifyClientID` and re-run `xcodegen generate`.
4. The Client Secret is **not** needed (PKCE flow). If you have one, store it in `.env.local` (gitignored).

## Tests

```bash
xcodebuild -project Dial.xcodeproj -scheme Dial -destination 'platform=macOS' test
```

Currently 73 tests covering store, aggregations, auth, polling, pet engine, sprite rendering, and end-to-end flow.

## Manual QA

See `docs/qa-checklist.md`.

## Design / plan docs

- Spec: `docs/superpowers/specs/2026-04-24-dial-design.md`
- Plan: `docs/superpowers/plans/2026-04-24-dial.md`
