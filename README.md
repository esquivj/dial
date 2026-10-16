# Dial

A native macOS menubar companion for Spotify. Shows what you're playing, what it means to *you* (play counts, rank, rediscoveries, first listens), and tends a tiny pixel pet that grows from an egg as you listen.

## What's in it

- **Menubar strip** — tiny pixel pet + current track + 30-day play count. Pet bobs to BPM and reacts to events (first listen pops, rediscovery floats thought-dots, streak dances).
- **Dropdown HUD** (440×440 smoked-plastic device, shape locked in `HUD_LOOK_LOCK.md`) — track hero with badge chip and pet window, readouts `TRACK · YTD`, `RANK · 7D`, `LAST · PLAYED`, live spectrum visualizer, transport controls. Pet, Stats and History screens open from the top rail.
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
./scripts/create-cert.sh  # once per machine: the "Dial Local Dev" signing cert every build uses
./scripts/dev.sh build    # generates Dial.xcodeproj from project.yml and builds
./scripts/dev.sh install  # build, copy to /Applications/Dial.app, relaunch
```

The Xcode project is generated from `project.yml` (committed) — never edit `Dial.xcodeproj` by hand. `dev.sh` regenerates it on every run; if you work in Xcode directly, run `xcodegen generate` after adding files. Coding agents: start with `AGENTS.md`.

## Spotify Developer setup

1. Register an app at <https://developer.spotify.com/dashboard>.
2. Add `dial://callback` as a redirect URI.
3. Copy the Client ID. For local dev, paste it into `project.yml` under `targets.Dial.info.properties.SpotifyClientID` and re-run `xcodegen generate`.
4. The Client Secret is **not** needed (PKCE flow). If you have one, store it in `.env.local` (gitignored).

## Tests

```bash
./scripts/dev.sh test       # full suite (store, aggregations, auth, polling, pet engine, views)
./scripts/dev.sh snapshot   # visual regression screenshots only
```

Screenshot baselines live in `DialTests/Snapshots/VisualRegression/`. Re-record with `./scripts/dev.sh record` only after checking the new images; see `AGENTS.md`.

## Manual QA

See `docs/qa-checklist.md`.

## Design / plan docs

- Current design system: `DESIGN.md`; HUD shape lock: `HUD_LOOK_LOCK.md`; product intent: `PRODUCT.md`.
- Original v1 spec and plan (historical; colours, fonts and sizes are outdated): `docs/superpowers/`.
