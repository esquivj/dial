# Dial — notes for coding agents

Dial is a native macOS menubar companion for Spotify (SwiftUI + AppKit, macOS 14+). It shows the current track with personal stats, keeps a local SQLite archive of every play, and runs a pixel pet that grows as you listen. Product intent: `PRODUCT.md`. Visual system: `DESIGN.md`.

## Commands

Use `scripts/dev.sh`. It regenerates the Xcode project, builds into one DerivedData folder (`.build/DerivedData`), and prints a short summary.

```bash
scripts/dev.sh build                        # Debug build; prints unique warnings
scripts/dev.sh test                         # full suite; prints pass/fail and failing tests
scripts/dev.sh test PetEngineTests          # one class (or Class/test_method)
scripts/dev.sh snapshot                     # visual regression tests only
scripts/dev.sh record                       # re-record visual baselines (see below)
scripts/dev.sh install                      # build, replace /Applications/Dial.app, relaunch
```

First time on a machine: `brew install xcodegen`, then `scripts/create-cert.sh` once. Every build is signed with the self-signed "Dial Local Dev" cert (`project.yml`), so macOS keeps the Screen Recording grant across rebuilds. Without it, builds fail to sign. (`security find-identity -v` reports 0 valid identities for it because it's self-signed; that's expected. `dev.sh` checks with `security find-certificate`.)

Full logs are in `.build/logs/`. Don't pass your own `-derivedDataPath` to a new folder; one shared folder keeps builds incremental and the repo small.

## Where things live

| Folder | What it owns |
|---|---|
| `Dial/App` | App entry, `AppDelegate` (CLI flags like `--import`, `--backfill`, `--perf-automation`), `StatusBarController` + `DropdownPanel` (the 440×440 borderless panel) |
| `Dial/Spotify`, `Dial/Auth` | Web API client, rate-limit gate, desktop playback observer; PKCE OAuth with Keychain tokens |
| `Dial/Polling` | `PollingService` turns playback state into events; `DedupRule` decides when a play counts |
| `Dial/History` | Extended Streaming History import (`Importer`, `EndsongFile`), recently-played reconciliation, metadata enrichment/backfill |
| `Dial/Store` | GRDB `DatabaseStack`, `Migrations` (v1…v15), `DAO/` and `Models/` |
| `Dial/Aggregations` | All stats SQL (`StatsQueries`, `PlayAggregations`), badges (`BadgeResolver`), sound themes, track/artist identity merging |
| `Dial/Pet` | `PetEngine` (records plays, XP, stages, tricks), behaviors, streaks |
| `Dial/Audio` | Screen-audio capture + FFT for the spectrum visualizer |
| `Dial/ViewModels` | `AppCoordinator` wires everything together and owns app state; per-surface view models |
| `Dial/Views/Dropdown` | The HUD: `DropdownView` plus `StatusRail`, `TrackHero`, `ReadoutsRow`, `ControlsBar` (these change together), and the Pet/Stats/History screens |
| `Dial/Views/MenubarStrip`, `Views/Settings`, `Views/PixelSprite` | Menubar strip, Settings window, bulldog sprite |
| `Dial/DesignSystem` | Tokens and themes (`Dial+Tokens`), layout constants (`DialLayout`), gel/CRT materials, hardware images |
| `Dial/Resources` | Fonts and PNG assets; bundled via explicit entries in `project.yml` |
| `DialTests` | XCTest, mirroring the folders above; `VisualRegressionTests` holds the screenshot tests |
| `integrations/dial_history` | Separate Python read-only API/CLI over the archive (its own README and tests) |
| `scripts/` | `dev.sh`, `install.sh`, `create-cert.sh`, `setup.sh`, `generate-hardware-assets.py`; the rest are one-off art scripts |

## Rules that must hold

- **The HUD shape is locked.** Read `HUD_LOOK_LOCK.md` before any change inside the dropdown. Don't change `Dial.Layout.Dropdown` sizes, the shell art, or element placement unless the user explicitly asks. Never fix a shell or art problem by moving UI. The panel and its snapshots are 440×440, and the rounded shell fills that square edge to edge by design.
- **`project.yml` is the source of truth.** `Dial.xcodeproj` is generated and gitignored. `dev.sh` regenerates it, so new Swift files are picked up automatically. New resource folders must be added to `project.yml` with `buildPhase: resources`, or they silently won't ship.
- **Migrations are append-only.** Add `v16_…` at the end of `Migrations.swift`; never edit a shipped migration.
- **Play counting** has four layers:
  1. `DedupRule`: a live play counts at ≥30 s or ≥50% of the track.
  2. `PollingService`: counts once per track change.
  3. `PetEngine.recordPlay`: dedups `live` and `recent` plays against nearby rows.
  4. The unique `(played_at, track_uri, ms_played)` index.

  `Importer` inserts streaming-history rows directly, with no threshold, and stats count every row. This is a known open question, so don't "fix" it without asking.
- **Theme ids are not display names:** `ember` displays as "Magenta", and `classic` as "Smoke Gel".

## Verifying a UI change without a human

1. `scripts/dev.sh snapshot`. Renders are compared with the PNGs in `DialTests/Snapshots/VisualRegression/`, and every render is exported to `.build/snapshots/<name>.png`. **Open the render you changed.** A pass alone doesn't prove much: the 0.2% pixel tolerance lets a changed label slip through.
2. On failure, open `.build/snapshot-failures/<name>.actual.png` next to `<name>.baseline.png`.
3. If the change is intended, run `scripts/dev.sh record`, **look at every changed PNG**, and get the user's OK before committing new baselines. A baseline recorded over a broken layout hides the breakage.

Snapshots are deterministic: fixtures use a fixed date (week of May 18, 2026), and the `dialFrozenDate` environment value pins sprite and overlay animation frames. If you add a `TimelineView` or a clock-driven animation, read `dialFrozenDate` so snapshots stay stable. The default Smoke (`classic`) theme has no HUD baseline yet.

## Searching

Use `rg` (respects `.gitignore`) and always pass a path: `rg PollingService Dial`. Avoid `find .` and plain `grep -r` from the repo root. Ignored folders (`tmp/`, `output/`, `.build/`, `.claude/`) can hold large build products and copies of the source.

## Known gaps

- Swift 5.10 language mode. Turning on strict concurrency surfaces about 140 warnings, mostly in `AppCoordinator` and `StatusBarController`.
- `.github/workflows/ci.yml` has never run: there is no git remote, and CI doesn't create the signing cert.
- `docs/superpowers/` is the original v1 spec/plan and is historical: colours, fonts and sizes there are outdated.
