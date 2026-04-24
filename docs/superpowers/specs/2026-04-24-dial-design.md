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
- **Native feel.** No Electron. Tiny memory footprint. Proper macOS idioms (NSStatusItem, NSPopover, SF Symbols, Keychain, Core Image blur).

## Non-goals

- Not a Spotify remote control beyond basic transport (play/pause/prev/next). Dial is a readout, not a player.
- Not multi-account or multi-user.
- Not cross-platform. macOS only.
- Not a social product. No sharing, no accounts beyond Spotify OAuth.
- Not a full stats dashboard. The menubar dropdown is the whole surface. A "History" and "Stats" drill-down are stubbed links; their full designs are out of scope for this spec.

## User experience

### Menubar strip (always visible)

The strip lives in `NSStatusItem` and has four display states:

| State | Visual | Copy |
|---|---|---|
| Playing | Amber 3-bar equalizer + track title + `·<plays30d>` count | `▍▍▍ Chamber of Reflection ·24` |
| First listen | Amber pulse dot + `NEW` label + track title | `● NEW So Hot You're Hurting…` |
| Collapsed (narrow menubar) | Equalizer bars + play count only | `▍▍▍ ·24` |
| Paused | Gray pause glyph + "Paused" | `❙❙ Paused` |

The strip auto-collapses if available menubar width falls below a threshold (other apps claiming space). Click opens the dropdown. Scroll-over the strip cycles prev/next track (optional, behind a Settings toggle).

### Dropdown (320×360, opens on click)

Opens as `NSPopover` (or `MenuBarExtra` in SwiftUI 5, depending on OS target). Content is stacked top to bottom:

1. **Status rail** (1px amber hairline + 20px bar): `NOW PLAYING` label + pulse dot + `MM:SS / MM:SS` progress on the right.
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
├── Spotify/              # API client: current-playing, track metadata
├── Polling/              # PollingService (Combine/AsyncStream-based)
├── History/              # Extended Streaming History importer
├── Store/                # GRDB DB, migrations, DAOs
├── Aggregations/         # SQL views / queries for readouts
├── ViewModels/           # @Observable view models
├── Views/
│   ├── MenubarStrip/     # The status item SwiftUI view
│   ├── Dropdown/         # The popover content
│   └── Settings/         # The settings window
└── DesignSystem/         # Colors, fonts, components (Chip, Readout, etc.)
```

Each module exposes a small interface and depends only on the layers below it. `Store` does not know about `Spotify`; `Aggregations` reads from `Store`.

### Auth flow

- **PKCE OAuth 2.0** via `ASWebAuthenticationSession`.
- **Scopes:** `user-read-currently-playing`, `user-read-playback-state`, `user-modify-playback-state` (for transport controls), `user-read-recently-played`.
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

### State / ViewModel layer

- `NowPlayingViewModel` (`@Observable`) — current track + all readouts for the dropdown.
- `MenubarStripViewModel` — current track + play count + state (playing/paused/new).
- `SettingsViewModel` — account, import progress, polling config.
- ViewModels are the only surface Views read from; they subscribe to `PollingService` events and `AggregationsCache` values.

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
Poll response → diff against last observed track → if same track: update progress → if different: apply dedup rule → when crossed threshold, insert `plays` row → refresh `AggregationsCache` → publish to ViewModels → views animate change.

## Edge cases & error handling

- **No Spotify running** — poll returns 204. Strip shows "Nothing playing" in muted ivory. No badge row.
- **Token expired** — `SpotifyClient` auto-refreshes; on refresh failure, strip shows "Reconnect" (click opens Settings).
- **Rate limit (429)** — exponential backoff starting at 5s, cap at 60s. Strip shows a small dim dot instead of the equalizer.
- **Malformed import file** — skip the file, log to `imports_log.notes`, continue. Show count of successes + failures in toast.
- **Clock skew between import and live** — `played_at` is authoritative; ties broken by insertion order.
- **Track has no `spotify_track_uri`** (old podcast entries, local files) — skip for aggregations, still counted in `plays` with `source = 'import'`.
- **Empty history** (no import, first hour after install) — badges naturally evaluate to FIRST LISTEN for every new track. Show an info note in the dropdown for the first 24h: "History is still building — import your Spotify export for richer badges."

## Testing strategy

- **Unit tests** — pure logic: dedup rule, aggregation queries against a seeded in-memory SQLite, badge priority resolver.
- **Integration tests** — fake Spotify server (stubbed URLProtocol) → PollingService → Store → Aggregations → ViewModel. Assert that after N poll ticks with scripted responses, the ViewModel reports the expected readouts.
- **Import test** — a committed fixture of ~200 synthetic `endsong` rows; assert idempotent re-import, correct track/artist derivation, transaction rollback on invalid row.
- **Snapshot tests** — SwiftUI previews captured as PNGs for each badge state, compared on CI (`swift-snapshot-testing`).
- **Manual QA checklist** — documented in `docs/qa-checklist.md` (written as part of the plan).

## Open questions

- **Scroll-over-strip for skip** — useful or too easy to trigger by accident? Behind a toggle for now, default off.
- **`MenuBarExtra` vs `NSStatusItem` + `NSPopover`** — `MenuBarExtra` is cleaner but has constraints on dynamic width for the strip. Plan will prototype both in v0 and pick.
- **Artwork caching** — for `last_60_min` timeline, do we cache album art locally? Probably yes, 50MB LRU cache in `~/Library/Caches/Dial/artwork`.
- **Dark/light mode** — Dial is dark-only (instrument aesthetic). Confirmed — no light-mode variant.

## Out of scope (explicit)

- The full "History" and "Stats" drill-down windows. The dropdown links to them but the windows themselves are a separate spec.
- Apple Music, YouTube Music, or any source other than Spotify.
- Notifications / alerts (e.g. "you just hit 1000 plays of X").
- Sharing, exports, screenshots.
- iOS, iPad, web.
