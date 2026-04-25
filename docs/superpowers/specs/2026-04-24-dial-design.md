# Dial — Design Document

**Status:** Draft
**Date:** 2026-04-24
**Owner:** Juan Esquivel

## Overview

Dial is a native macOS menubar HUD for Spotify. It lives in the status bar as an ambient strip and opens a compact 320×360 dropdown showing what's playing *and what that track is to you* — how many times you've played it, where it ranks in your rotation, whether it's a first listen, a rediscovery, or on a streak.

It treats personal listening history as an instrument readout: amber numerals on instrument black, compact and glance-able, with live state.

## Goals

- **Ambient.** Always present in the menubar, never in the way. Opens in under 100ms.
- **Personal.** Every reading is about *you* — your counts, your ranks, your rediscoveries. Not global stats.
- **Historically rich from day one.** Supports importing Spotify's Extended Streaming History export so "haven't heard since 2019" works the day the export arrives.
- **Alive.** A pixel-pet mascot lives in the menubar strip — grows from an egg as you listen, reacts to what's playing, gets excited on first listens, goes dormant if neglected.
- **Native feel.** No Electron. Tiny memory footprint. Proper macOS idioms (NSStatusItem, NSPopover, SF Symbols, Keychain, Core Image blur).

## Non-goals

- Not a Spotify remote control beyond basic transport (play/pause/prev/next). Dial is a readout, not a player.
- Not multi-account or multi-user.
- Not cross-platform. macOS only.
- Not a social product. No sharing, no accounts beyond Spotify OAuth.
- Not a full stats dashboard. The menubar dropdown is the whole surface. A "History" and "Stats" drill-down are stubbed links; their full designs are out of scope for this spec.

## User experience

### Menubar strip (always visible)

The strip lives in `NSStatusItem` and has four display states. The activity indicator on the left is the **pixel pet** (see Pixel Pet subsystem below), not a generic equalizer — its stage, pose, and beat-sync animation are driven by `PetViewModel`.

| State | Visual | Copy |
|---|---|---|
| Playing | Pet sprite (beat-sync) + track title + `·<plays30d>` count | `[🐱] Chamber of Reflection ·24` |
| First listen | Pet sprite (excited, eyes wide) + amber `NEW` label + track title | `[🐱!] NEW So Hot You're Hurting…` |
| Collapsed (narrow menubar) | Pet sprite + play count only | `[🐱] ·24` |
| Paused | Pet sprite (sitting, eyes closed) + "Paused" | `[🐱z] Paused` |

The strip auto-collapses if available menubar width falls below a threshold (other apps claiming space). Click opens the dropdown. Scroll-over the strip cycles prev/next track (optional, behind a Settings toggle).

### Dropdown (320×360, opens on click)

Opens as `NSPopover` (or `MenuBarExtra` in SwiftUI 5, depending on OS target). Content is stacked top to bottom:

1. **Status rail** (1px amber hairline + 28px bar): the pixel pet (rendered at 2×, ~24px) sits on the left + `NOW PLAYING` label + `MM:SS / MM:SS` progress on the right. The pet's animation state matches the menubar-strip sprite exactly (single source of truth).
2. **Track hero** (72px): 52px album art + track title + "Artist · Album".
3. **Readouts row** (68px, divided into 2 columns):
   - `PLAYS · 30D` — big amber mono numeral + small delta (`↑ 3` / `NEW`)
   - `RANK · 7D` — big amber mono numeral with `#` + small delta (`↑ 5` / `DEBUT`)
4. **Badge row** (36px): one contextual chip + descriptive line.
5. **Artist context** (48px): `ARTIST` label + rank pill + artist name + lifetime plays.
6. **Session timeline** (40px): `LAST 60 MIN` label + N-track count + horizontal bar chart of the last hour's tracks (width = duration, opacity scaled to recency, current track full amber with glow).
7. **Controls bar** (40px): prev / play-pause / next (left) + `HISTORY` / `STATS` links (right, open drill-down windows — stubbed).

### Badge states

The badge row is one chip per state. Only one can be active at a time, prioritized in this order:

1. **FIRST LISTEN** (amber) — track count = 1 in lifetime. "You've never played this before."
2. **REDISCOVERED** (dim ivory) — gap since previous play ≥ 90 days. "Haven't heard since `<month year>`."
3. **ON STREAK** (warning orange) — track is in your top 5 most-played of the last 7 days AND plays-30d ≥ 10. "Most-played track this week."
4. **NONE** — no chip, badge row collapses to 0px.

Palette recap: amber `#FFB547`, warning orange `#E8522A`, dim ivory `#E6E2D6`.

### Settings window

Accessed via right-click on the menubar strip → "Settings…". A single, scrollable pane:

- **Spotify account** — connect / disconnect button, current user display.
- **History import** — drag-and-drop zone for the `Spotify Extended Streaming History` folder, or a "Choose folder…" button. Shows import progress bar and last-imported-at timestamp.
- **Polling** — toggle, interval slider (3s–15s).
- **Scroll to skip** — toggle for scroll-over-strip → prev/next.
- **About / quit**.

### Onboarding (first run)

1. Welcome screen (modal) — explains what Dial does, requests Spotify connect.
2. OAuth flow (ASWebAuthenticationSession) — user grants scopes.
3. Post-auth screen — prompts: "Want richer history day one? Request your Spotify Extended Streaming History — takes 5–30 days. We'll import it when you have it." Links to Spotify's privacy page.
4. Done — strip appears in menubar, polling begins.

## Technical architecture

### Language & frameworks

- **Swift 5.10+**, **SwiftUI** for all views, **AppKit** bridges where needed (NSStatusItem, NSPopover).
- **Xcode project**, deployment target: macOS 14 (Sonoma) — lets us use `MenuBarExtra` and `@Observable`.
- **Packages (SwiftPM):**
  - `GRDB.swift` — SQLite wrapper for local storage.
  - `KeychainAccess` — token storage.
  - That's it. No Alamofire, no heavy deps — `URLSession` is fine.

### Process model

Single-process app. No helper processes. The menubar icon starts polling on login (via a LaunchAgent plist) and keeps it alive while the strip is visible.

### Modules

```
Dial/
├── App/                  # @main, AppDelegate, StatusBarController
├── Auth/                 # OAuth (PKCE) + Keychain token store
├── Spotify/              # API client: current-playing, track metadata, audio-features
├── Polling/              # PollingService (Combine/AsyncStream-based)
├── History/              # Extended Streaming History importer
├── Store/                # GRDB DB, migrations, DAOs
├── Aggregations/         # SQL views / queries for readouts
├── Pet/                  # Pixel pet: XP engine, stage transitions, behavior resolver, sprite data
├── ViewModels/           # @Observable view models
├── Views/
│   ├── MenubarStrip/     # The status item SwiftUI view
│   ├── Dropdown/         # The popover content
│   ├── PixelSprite/      # The pet renderer (SwiftUI Canvas, 14×14 pixel arrays)
│   └── Settings/         # The settings window
└── DesignSystem/         # Colors, fonts, components (Chip, Readout, etc.)
```

Each module exposes a small interface and depends only on the layers below it. `Store` does not know about `Spotify`; `Aggregations` reads from `Store`.

### Auth flow

- **PKCE OAuth 2.0** via `ASWebAuthenticationSession`.
- **Scopes:** `user-read-currently-playing`, `user-read-playback-state`, `user-modify-playback-state` (for transport controls), `user-read-recently-played`. Note: `/audio-features` (used for beat-sync BPM) requires no user scope — just the app token.
- **Token storage:** access + refresh in macOS Keychain via `KeychainAccess`, keyed by account.
- **Refresh:** `SpotifyClient` auto-refreshes on 401.

### Live polling

- `PollingService` owns an `AsyncStream<PlaybackEvent>` that emits:
  - `.playing(TrackInfo)` when the current track changes.
  - `.paused` / `.resumed`
  - `.progress(percent)` every tick for the strip's progress indicator.
- Polls `/me/player/currently-playing` every 3s by default.
- **Dedup:** a track "counts as a play" once it's been playing for ≥ 30s *or* has reached 50% of its duration, whichever comes first — matches Spotify's own "stream" definition.
- On each counted play, writes a row to `plays` and triggers an `Aggregations.refresh()`.

### History import

- **Input:** the `Spotify Extended Streaming History` folder the user receives from Spotify's data export. The importer accepts both the current naming (`Streaming_History_Audio_YYYY_N.json`) and the legacy `endsong_N.json` format.
- **Importer:** streams each file with `JSONDecoder`, inserts in batches of 1000 via a single transaction.
- **De-dup key:** `(ts, ms_played, master_metadata_track_name, spotify_track_uri)`. Re-importing the same export is idempotent.
- **Track metadata enrichment:** after import, the importer walks distinct `spotify_track_uri` values that aren't in the `tracks` table and fetches them via the Spotify `tracks` API in batches of 50 (rate-limited at 5 req/sec).

### Local database (SQLite / GRDB)

Schema:

```sql
CREATE TABLE plays (
  id INTEGER PRIMARY KEY,
  played_at INTEGER NOT NULL,     -- unix seconds
  track_uri TEXT NOT NULL,
  ms_played INTEGER NOT NULL,
  source TEXT NOT NULL,            -- 'live' | 'import'
  UNIQUE(played_at, track_uri, ms_played)
);
CREATE INDEX plays_by_track ON plays(track_uri, played_at);
CREATE INDEX plays_by_time  ON plays(played_at);

CREATE TABLE tracks (
  uri TEXT PRIMARY KEY,
  name TEXT,
  album_name TEXT,
  album_art_url TEXT,
  duration_ms INTEGER,
  artists_json TEXT               -- [{name,uri},...]
);

CREATE TABLE artists (
  uri TEXT PRIMARY KEY,
  name TEXT,
  genres_json TEXT,
  image_url TEXT
);

CREATE TABLE imports_log (
  id INTEGER PRIMARY KEY,
  imported_at INTEGER NOT NULL,
  source_path TEXT,
  rows_inserted INTEGER
);
```

### Aggregations (the "readouts")

Defined as SQL views and queries on GRDB's value observation, so the UI subscribes and auto-updates when `plays` changes.

- **`plays_30d(track_uri)`** — `COUNT(*) WHERE track_uri = ? AND played_at > now - 30d`
- **`rank_7d(track_uri)`** — `ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) WHERE played_at > now - 7d`
- **`artist_rank_7d(artist_uri)`** — same, grouped by primary artist
- **`last_heard_before(track_uri, window)`** — `MAX(played_at) WHERE track_uri = ? AND played_at < now - window`; null → REDISCOVERED if window = 90d
- **`first_listen(track_uri)`** — `NOT EXISTS (SELECT 1 FROM plays WHERE track_uri = ? AND source = 'import')` AND `COUNT(live) = 1`
- **`on_streak(track_uri)`** — `plays_30d >= 10 AND rank_7d <= 5`
- **`last_60_min_tracks()`** — ordered list of distinct plays in the last hour for the timeline bar

All aggregations are cached in an in-memory `@Observable AggregationsCache` and recomputed incrementally when a new play arrives.

### Pixel Pet (mascot subsystem)

A pixel pet lives in the menubar strip and the dropdown's status rail. It hatches from an egg and grows through 6 life stages as you listen. It reacts to playback events (first listens, rediscoveries, pauses) and sleeps if you go quiet for 7+ days. Rendered as a 14×14 amber silhouette on instrument black — classic Game Boy tamagotchi, tuned to the vehicle-dashboard palette.

**Life stages (by XP threshold):**

| Stage | XP | Sprite signature |
|---|---|---|
| Egg | 0 | Closed oval |
| Hatching | 500 | Egg cracked, two eyes peeking, shell pieces floating |
| Hatchling | 1,000 | Small creature, 2 legs, 2 eyes, no ears |
| Juvenile | 5,000 | One ear, learning a smile |
| Companion | 25,000 | Full adult: two ears, eyes, smile, feet |
| Elder | 100,000 | Eyebrows, mustache, wise silhouette |

**XP formula (blend):**

Every play that crosses the dedup threshold awards XP:

```
base_xp     = ms_played / 60_000                # 1 XP per minute
variety_xp  = 50 if first_play_of_artist  else
              25 if first_play_of_album   else 0
streak_mult = min(1 + (streak_days - 2) * 0.25, 2.0)   # active when streak >= 3 days
xp_awarded  = (base_xp + variety_xp) * streak_mult
```

A *streak day* is a day with at least one dedup-qualified play. Missing a day resets the streak to 0.

**Retroactive XP from history import:**

Imported history contributes XP up to a cap at the **Companion** threshold (25,000 XP). Elder is **locked** until at least 30 calendar days have elapsed since first install. This prevents a decade-long import from instantly maxing the pet — you get a satisfying pre-seed, but the final stage is earned in real time.

**Behaviors (animation states):**

| Behavior | Trigger | Animation |
|---|---|---|
| `idle` | Music playing, no special event | Gentle 2s bob; blink every 5–8s |
| `beat_sync` | Music playing with known BPM (via `/audio-features`) | Bob cadence = 60/BPM seconds |
| `first_listen` | `first_listen` aggregation fires | 400ms: exclamation mark pops above, eyes widen, ears up; settles back to idle |
| `rediscovered` | `rediscovered` aggregation fires | 600ms: trailing thought dots, wistful half-smile; settles back |
| `paused` | Playback paused | Sits, droopy ears, eyes closed, single Z floats |
| `dormant` | No dedup-qualified plays for ≥ 7 days | Lies down, three fading Z's; returns to `idle` on next play |
| `level_up` | Stage threshold crossed | 1.2s: radial amber glow + sprite cross-fades from old stage to new |

**Behavior priority** (highest first): `level_up` > `first_listen` > `rediscovered` > `paused` > `dormant` > `beat_sync` > `idle`.

**Sprite storage & rendering:**

Sprites are compile-time Swift arrays of 14×14 ints (one per `(stage, behavior)` pair), not image assets. A `PixelSprite` SwiftUI view renders them via `Canvas`:

```swift
struct PixelSprite: View {
  let pixels: [[Int]]        // 14×14, 0 = transparent, 1 = amber, 2 = ivory, 3 = shadow
  let pixelSize: CGFloat     // 1 for menubar strip (~16px total), 2 for dropdown (~32px)
  // renders via Canvas { ctx, size in ... }
}
```

Beat sync and other animations use `withAnimation` + a `@State` offset; no Core Animation layer juggling needed at this scale.

**Storage:**

```sql
CREATE TABLE pet_state (
  id INTEGER PRIMARY KEY CHECK (id = 1),     -- singleton row
  xp INTEGER NOT NULL DEFAULT 0,
  stage TEXT NOT NULL DEFAULT 'egg',
  hatched_at INTEGER,                        -- when xp first crossed 500
  last_play_at INTEGER,
  streak_days INTEGER NOT NULL DEFAULT 0,
  streak_anchor_date TEXT,                   -- YYYY-MM-DD of streak start
  elder_unlocked_at INTEGER,                 -- set after 30d live use; null until then
  installed_at INTEGER NOT NULL              -- unix seconds; anchors elder-unlock window
);
```

XP is recomputed incrementally inside the same transaction that inserts a `plays` row. Streak is evaluated by a lightweight job at 03:00 local time (checks yesterday had a play; if not, resets). Behavior state is pure-derived from playback event + last-play-at, not stored.

**Accessibility:**

The pet is decorative. VoiceOver reads the strip as "Dial — playing [track] by [artist]." The Settings window exposes the pet status as text: "Pet: Companion, 27,420 XP, 12-day streak."

### State / ViewModel layer

- `NowPlayingViewModel` (`@Observable`) — current track + all readouts for the dropdown.
- `MenubarStripViewModel` — current track + play count + state (playing/paused/new).
- `PetViewModel` — current stage + active behavior + XP progress; shared between menubar strip and dropdown so the pet animates in sync across both surfaces.
- `SettingsViewModel` — account, import progress, polling config, pet stats.
- ViewModels are the only surface Views read from; they subscribe to `PollingService` events, `AggregationsCache` values, and `PetEngine` state.

### Visual direction (mood: vehicle dashboard)

- **Ground:** `#0B0C0F` (instrument black)
- **Surface:** `#17181C` (matte dash)
- **Primary accent:** `#FFB547` (amber LED)
- **Secondary accent:** `#E8522A` (warning orange)
- **Text:** `#E6E2D6` (dim ivory)
- **Muted:** `#6B6E74` (brushed aluminum)
- **Type:** IBM Plex Mono for numerals and labels, IBM Plex Sans for track/artist names.
- **Motion:** amber readouts flicker briefly on value change (200ms). New-track transition cross-fades album art (300ms) and readouts (150ms staggered).
- **Window chrome:** no visible chrome — popover uses `.acceptsFirstMouse`, `.removesMaterial`, dark vibrancy.

### Design tokens (shipped as Swift constants)

```swift
enum Dial {
  enum Color {
    static let ground   = Color(hex: 0x0B0C0F)
    static let surface  = Color(hex: 0x17181C)
    static let amber    = Color(hex: 0xFFB547)
    static let orange   = Color(hex: 0xE8522A)
    static let ivory    = Color(hex: 0xE6E2D6)
    static let muted    = Color(hex: 0x6B6E74)
  }
  enum Font {
    static let monoLabel   = Font.custom("IBMPlexMono-Regular", size: 9)
    static let monoValue   = Font.custom("IBMPlexMono-Medium",  size: 28)
    static let monoSmall   = Font.custom("IBMPlexMono-Regular", size: 10)
    static let sansTitle   = Font.custom("IBMPlexSans-Medium",  size: 14)
    static let sansCaption = Font.custom("IBMPlexSans-Regular", size: 11)
  }
}
```

## Key flows

### First open after install
AppDelegate → check Keychain → no token → present onboarding → OAuth → store tokens → poll once → populate ViewModel → strip shows current track.

### Import run
User drops folder → validate filenames (`endsong_*.json`) → begin transaction → stream-parse each file → batch-insert plays → commit → collect distinct track URIs → batch-fetch metadata → upsert `tracks` + `artists` → close with `imports_log` row → dismiss Settings drag-zone, show "Imported 47,293 plays" toast.

### Normal tick
Poll response → diff against last observed track → if same track: update progress → if different: apply dedup rule → when crossed threshold, in a single transaction: insert `plays` row, award pet XP, update `pet_state` (including any stage transition) → refresh `AggregationsCache` → publish to ViewModels → strip/dropdown animate change, pet plays its contextual behavior (first listen, rediscovered, or beat sync).

## Edge cases & error handling

- **No Spotify running** — poll returns 204. Strip shows "Nothing playing" in muted ivory. No badge row.
- **Token expired** — `SpotifyClient` auto-refreshes; on refresh failure, strip shows "Reconnect" (click opens Settings).
- **Rate limit (429)** — exponential backoff starting at 5s, cap at 60s. Strip shows a small dim dot instead of the equalizer.
- **Malformed import file** — skip the file, log to `imports_log.notes`, continue. Show count of successes + failures in toast.
- **Clock skew between import and live** — `played_at` is authoritative; ties broken by insertion order.
- **Track has no `spotify_track_uri`** (old podcast entries, local files) — skip for aggregations, still counted in `plays` with `source = 'import'`.
- **Empty history** (no import, first hour after install) — badges naturally evaluate to FIRST LISTEN for every new track. Show an info note in the dropdown for the first 24h: "History is still building — import your Spotify export for richer badges."

## Testing strategy

- **Unit tests** — pure logic: dedup rule, aggregation queries against a seeded in-memory SQLite, badge priority resolver, pet XP formula (base/variety/streak math), stage-transition thresholds, behavior priority resolver.
- **Integration tests** — fake Spotify server (stubbed URLProtocol) → PollingService → Store → Aggregations + PetEngine → ViewModel. Assert that after N poll ticks with scripted responses, the ViewModel reports the expected readouts AND the pet reports the expected stage + behavior.
- **Import test** — a committed fixture of ~200 synthetic `endsong` rows; assert idempotent re-import, correct track/artist derivation, transaction rollback on invalid row, retroactive XP capped at Companion threshold.
- **Streak test** — scripted calendar of synthetic play days; assert streak increments, resets on gap, multiplier applies correctly.
- **Snapshot tests** — SwiftUI previews captured as PNGs for each badge state AND each (stage, behavior) pet sprite, compared on CI (`swift-snapshot-testing`).
- **Manual QA checklist** — documented in `docs/qa-checklist.md` (written as part of the plan).

## Open questions

- **Scroll-over-strip for skip** — useful or too easy to trigger by accident? Behind a toggle for now, default off.
- **`MenuBarExtra` vs `NSStatusItem` + `NSPopover`** — `MenuBarExtra` is cleaner but has constraints on dynamic width for the strip. Plan will prototype both in v0 and pick.
- **Artwork caching** — for `last_60_min` timeline, do we cache album art locally? Probably yes, 50MB LRU cache in `~/Library/Caches/Dial/artwork`.
- **Dark/light mode** — Dial is dark-only (instrument aesthetic). Confirmed — no light-mode variant.
- **Pet variant at elder stage** — does the elder form branch based on listening diversity (e.g., eclectic listener → different silhouette from genre loyalist)? Out of v1 scope but worth tracking as a v1.1 hook.
- **Pet cosmetic earning** — unlockable accessories (tiny hat, record around neck) at XP milestones? Also v1.1.

## Out of scope (explicit)

- The full "History" and "Stats" drill-down windows. The dropdown links to them but the windows themselves are a separate spec.
- Apple Music, YouTube Music, or any source other than Spotify.
- Notifications / alerts (e.g. "you just hit 1000 plays of X").
- Sharing, exports, screenshots.
- iOS, iPad, web.
