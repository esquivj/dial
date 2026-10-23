# Multi-Mac history

Dial can run on more than one Mac: a first Mac that holds the archive, and a second Mac set up later. Each keeps its own `~/Library/Application Support/Dial/dial.sqlite` (`DatabaseStack.defaultURL()`), so the second Mac starts with no history and the two archives drift as both record. This doc maps what is per-Mac, what already converges, the options, and the design that was built.

Status: Phase 1 built, 2026-10-23, and used to seed a second Mac from the first. Next: the reverse merge, the rest of step 8. Change this file first when a decision here changes.

## The short version

- **Both Macs already record the same listens while Dial runs on both.** When the local Spotify app isn't playing, `PollingService` asks the Web API, which reports playback on any device on the account. The archives differ in three ways: the history from before the second Mac's install, gaps when one Mac sleeps through more than 50 tracks, and everything Dial derived from a partial archive.
- **Plays are the facts; almost everything else is derived** from them, against whatever that Mac knew at the time. Copying memories or pet XP between Macs carries their mistakes along. Tricks, which you teach, are the exception.
- **A merge that relies only on the unique index would double every listen both Macs saw.** Two Macs practically never produce the same `(played_at, track_uri, ms_played)` for one live listen.
- **The design:** an archive export and merge, run as a headless command (like `--import`). Use it to seed the second Mac, then to send the second Mac's plays back. Automate the exchange later, and only if running it by hand gets tedious.

## Why a new Mac's history goes wrong

A second Mac's first day shows the problem. Dial judges each play against an archive that began that day, so most plays earn First Listen or New Artist memories. The pet collects +50 New Artist bonuses for artists the first Mac has known for years. The first weekly memory counts only a handful of plays. None of this fixes itself: memories and XP are decided once, when a play is recorded.

## What is per-Mac today

| Data | Where | How Dial makes it | In a merge |
|---|---|---|---|
| Plays | `plays` | Live poll, recently-played sync, streaming-history import | Facts: union with twin matching |
| Track and artist metadata | `tracks`, `artists`, `artist_identity_aliases` | Poll and enrichment; aliases rebuilt by `ArtistIdentityRepair` | Union (fill blanks only), then rebuild aliases |
| Tag and enrichment caches | `raw_tags`, `normalized_tags`, `tag_enrichment_state`, `metadata_enrichment_state` | Spotify and Last.fm lookups | Union; saves thousands of API calls |
| Memories | `badge_events` | Decided once, when a play is recorded | Donor plus replay (below) |
| Pet | `pet_state` (one row) | XP added play by play | Pet rules (below) |
| Tricks | `pet_trick_unlocks` | Taught by you in the Pet screen | Union |
| Artifacts | `artifacts` | Derived from memories, tricks, weekly memories | Rebuild |
| Weekly memories | `weekly_memories` | Derived per week | Donor plus recompute |
| Recent-play cursor | `recent_play_sync_state` | This Mac's sync | Keep local |
| Import log | `imports_log` | Imports done on this Mac | Keep local |
| Last.fm queue | `lastfm_scrobbles` | This Mac's live plays | Never merged |
| Settings | `UserDefaults` (`settings.*`) | You | Never merged |
| Secrets | Files beside the database in Debug builds (`spotify-token.json`, `lastfm-api-key`, `lastfm-session-key`), Keychain otherwise | Sign-in | Never copied |

### Plays, and why the unique index can't merge two Macs

Each source stamps a play differently:

| `source` | `played_at` | `ms_played` |
|---|---|---|
| `live` | Estimated start: now minus progress at the moment Dial counted it | Progress when counted, usually about 30 s |
| `recent` | Spotify's recently-played time, when the play ended | Track duration (at least 30 s) |
| `import` | The export's `ts`, when the stream stopped | Measured |

- The same `recent` row fetched on both Macs is identical, so the unique index drops the copy. The same export imported on both Macs also dedups this way.
- The same listen counted live on both Macs gets two start estimates a few seconds apart and two progress values. The triples never match, so a merge through the index alone doubles every listen both Macs saw.
- Dial already has twin rules inside one archive. `PetEngine` skips a live play when a live play of the same track started within one track duration before it (600 s if the duration is unknown). It also skips a `recent` row whose live or imported twin sits in a window around it, and `counted_plays` (v18) hides any `recent` row that has such a twin.
- There is no rule that matches `import` rows to `live` rows. Importing a newer export over a stretch Dial recorded live double counts it today, on one Mac or two.
- Stats and memories read `counted_plays` (v16, v18), which drops imported skips and hidden `recent` twins.

### Both Macs record the same listens

`PollingService` reads the local Spotify app when it is playing. When the app is idle or closed, it asks `/me/player`, which reports playback on any device. So while Dial runs and is online on both Macs, each one counts what you play on the other, and on your phone. That makes the overlapping time easy to merge. It also causes two problems:

- **Double scrobbles.** `AppCoordinator.finishCountedPlay` hands every counted live play to `LastFMScrobbler`, whichever device played it. If Last.fm is connected on both Macs, one listen is scrobbled twice, with timestamps a few seconds apart. This needs no merge to happen.
- **A shared rate limit.** Both Macs call Spotify through the same app (client ID), and Spotify rate-limits per app. A merge should carry metadata and tags so the second Mac doesn't re-enrich every track in the history. A new Mac may not have a Last.fm API key for tag lookups at all.

### Memories are decided once

`BadgeResolver.recordMemories` runs when a play is recorded and judges it against the archive at that moment. Nothing re-judges a memory later except cleanup migrations (v8 and v14 deleted false New Artist and First Listen memories). Each memory has a unique `scope_key`:

- Once ever: `first_listen:<track>`, `new_artist:<artist>`, `deep_cut:<track>`, `play_10:<track>` (also 50 and 100)
- Per period: `anniversary:<track>:<year>`, `on_streak:<track>:<week>`
- Per listen: `rediscovered:<track>:<played_at>`, `repeat_track:<track>:<played_at>`, `album_mode:<artist>:<album>:<played_at>`

So memories made from a partial archive stay wrong, and copying rows between Macs imports the other Mac's mistakes too. A union by `scope_key` has two more faults. A per-listen memory gets two keys a few seconds apart, so one moment shows twice. And a milestone keeps whichever row arrived first, not the real 10th play. The resolver's queries also assume the play being judged is the newest one in the table: `repeat_track` and `album_mode` read the latest rows, and the lifetime counts include every row. You can't re-judge an old play in place.

### The pet is a running total

- `pet_state` adds XP per counted play (`XPFormula`: minutes played, +50 for a new artist, +25 for a new album, a streak multiplier up to 2×). Stage follows XP, and Elder unlocks only 30 days after `installed_at`. Imports add base XP only, capped at 25,000 (Companion).
- The streak moves one play at a time (`StreakCalendar`). A play older than the current anchor resets it, so older plays can't be fed in afterwards.
- XP isn't a function of the archive. v2 kept the XP of the duplicate plays it deleted, and v8 and v14 left XP alone when they removed false memories. Recomputing XP from plays would land on a different number, possibly a lower stage. So a merge never recomputes the whole pet and never lowers XP.

### Tricks, artifacts and weekly memories

- **Tricks** are taught by you (`PetTrickUnlocksDAO.unlock` from the Pet screen), not derived, so they have to travel.
- **Artifacts** are fully derived: `ArtifactsDAO.syncFromMemoriesAndTricks` keeps the earliest memory per kind, plus tricks and weekly mementos, with `INSERT OR IGNORE`. `source_badge_event_id` is a local row id. They're safe to delete and rebuild.
- **Weekly memories**: `WeeklyMemoriesDAO.ensureRecentWeeks` recomputes the current week and fills in missing weeks from the last 12. It never recomputes a finished week, so a new Mac's first weekly memory stays wrong until something recomputes it.

### Last.fm

- The queue lives in each Mac's `lastfm_scrobbles`. `play_id` is unique and references `plays` with `ON DELETE CASCADE`, and `enqueue` accepts only `live` plays. The session key belongs to that Mac.
- Any design must leave the queue alone. It must never let a play that arrived from another Mac reach the queue, and it must never delete a local play, because that cascades to its scrobble row. One Mac scrobbles; the other doesn't.

### Settings and secrets

Settings are per-Mac on purpose: menu bar width, desktop memory corner and display all differ between Macs. Each Mac signs in to Spotify and Last.fm on its own. Copying the whole `Dial` folder would give both Macs one Spotify refresh token and one Last.fm session.

## What already converges

**Live observation.** Any listen made while Dial is running and online on both Macs lands in both archives as a `live` row.

**`RecentPlaysReconciler`.** Spotify's recently-played endpoint returns only the last 50 tracks: music only, each played at least 30 s.

- On an empty archive Dial makes one request and gets the last 50 plays. On a new Mac, that's all the history it starts with.
- After that it repairs gaps at launch, on wake, when the network returns, and every 10 minutes, but only within those 50 plays. A longer gap is flagged as possibly truncated.
- Its rows go through `PetEngine.recordPlay` as live plays: full XP, every memory kind. That's how a fresh archive collects false First Listens.

**`Importer`.** Spotify's Extended Streaming History covers the whole account, every device, as far back as the account goes.

- You request it from Spotify's privacy page. It can take up to 30 days to arrive, and it ends on the day you asked.
- Imported plays earn only milestone and anniversary memories, and base XP within the 25,000 cap.
- Importing the same files on both Macs produces identical rows, so later merges dedup them for free.
- Without an import-to-live twin rule, importing a newer export on the first Mac would double count the live plays it recorded since its last import.

**How far a second Mac gets on its own.** With the first Mac's old export files re-imported, it has everything up to that export, plus everything since its own install. It would still be missing:

- The first Mac's live plays between that export and the second Mac's install. They exist only in the first Mac's archive, and in any Spotify export requested later.
- The pet's real growth: imports stop at Companion.
- Your tricks, and every rediscovery, deep cut and first-listen memory from the past.
- Correct versions of its own false memories, which would stay wrong.

## Options

### 1. Copy the first Mac's database once

Take a consistent snapshot on the first Mac (`sqlite3 dial.sqlite "VACUUM INTO '…'"` works while Dial runs; a Finder copy of `dial.sqlite` without its `-wal` can miss recent writes). Quit Dial on the second Mac, swap the file in, delete the old `-wal` and `-shm`, and relaunch.

- **Plays:** the second Mac gets everything the first Mac has. Its own plays since install are lost, except the ones the first Mac also saw and the last 50, which recent sync fetches again.
- **Afterwards:** the archives fork. Nothing repairs later drift, and a second copy would wipe the second Mac's own plays.
- **Pet, memories, artifacts, tricks:** identical at copy time, then two pets that grow apart.
- **Last.fm:** the copy brings the first Mac's pending queue rows. If Last.fm is ever connected on the second Mac, they're sent a second time unless they're cleared from the copy first.
- **Effort:** about an hour for a script. **Risk:** low as a one-off, destructive if repeated.

### 2. Export and merge (chosen)

One Mac writes a read-only snapshot of its archive. The other merges it: plays go in through twin matching, metadata and tricks are unioned, and derived state is rebuilt with Dial's own rules. The Merge rules section has the details.

- **Plays:** union, no doubles, repeatable in both directions.
- **Pet:** the donor's XP plus XP for the plays it lacked. XP never goes down, and the two pets end up matching.
- **Memories and artifacts:** the donor's up to the first play it lacked, then replayed with `BadgeResolver` on the merged plays. Both Macs end up with the same memories.
- **Last.fm:** the queue is untouched, and merged plays can't be queued.
- **Live dedup:** the twin rules mirror the existing live, recent and import windows.
- **Effort:** 2–3 days for Phase 1. **Risk:** medium, because it's new code over the whole archive. A backup before every merge, a dry run, the headless-only first version, and replay-equivalence tests keep it contained.

### 3. A shared or synced database

**iCloud Drive or Dropbox.** Each Mac gets its own copy of the file, and the service syncs each changed file on its own, at its own pace. SQLite's locks and the WAL's shared memory work only between processes on one machine, so neither Mac knows the other is writing. Dial keeps the database open the whole time it runs, so there's never a safe moment to swap the file.

- A WAL database is three files (`dial.sqlite`, `-wal`, `-shm`), and they can arrive out of step. The other Mac then opens a main file that doesn't match its log and reads missing or corrupt pages ("database disk image is malformed").
- Two Macs writing produce conflict copies (`dial 2.sqlite`) that Dial never reads, or the last upload wins and the other Mac's plays since its last download vanish. Turning WAL off doesn't change that.
- "Optimize Mac Storage" can evict the file to a placeholder while Dial expects it on disk.

**A file share from one of the Macs.** SQLite's documentation warns that locking over network filesystems is unreliable and that WAL doesn't work over them at all. The other Mac also couldn't record anything away from that network.

**CloudKit.** It needs an iCloud container entitlement, which needs a provisioning profile from a paid Apple Developer Program team. Dial signs with the self-signed "Dial Local Dev" certificate and `DEVELOPMENT_TEAM: ""` (`project.yml`), on purpose: `scripts/create-cert.sh` explains why it avoids the $99/year program. The same limit rules out `NSUbiquitousKeyValueStore` and Core Data with CloudKit. It would also mean rewriting the store layer.

If a shared file did work, both Macs would flush one Last.fm queue and send rows twice. **Effort:** minutes to set up. **Risk:** high, because it fails by losing or corrupting the archive.

### 4. Other routes

- **A fresh Spotify export on both Macs.** It gets every play up to the request date, including stretches neither Mac recorded. But it takes days to weeks, carries no memories, pet or tricks, and caps the pet at Companion. On the first Mac it double counts its live plays until `Importer` gets an import-to-live twin rule.
- **One Mac as the recorder.** If one Mac stays awake with Dial running, it records nearly every play on the account, phone included. Then most merges only need to run one way, toward the other Mac. This is a habit, not a feature, and it pairs well with option 2.
- **Single-writer snapshot files in a synced folder.** This automates option 2. Each Mac writes only its own snapshot file and merges the others'. Nothing in the synced folder is ever opened as a live database, so iCloud's failure modes don't apply. This is Phase 2 below.
- **The Dial History snapshot or API** (`integrations/dial_history`). It can publish plays, tracks, artists and aliases on a schedule, which could seed a second Mac's plays. But it carries no memories, pet, tricks or tags by design, and Dial would depend on a hosted service for its own data. It's not recommended as Dial's sync path.

### Side by side

| | 1. Copy once | 2. Export and merge | 3. Shared or synced database | 4. Spotify export |
|---|---|---|---|---|
| Plays on the second Mac | All of the first Mac's; its own only if the first Mac saw them | Union, no doubles | Lost writes, conflict copies, corruption | Everything to the export date |
| Drift afterwards | Never repaired | Repaired by the next merge | Not applicable | Until the next export |
| Pet | Copied, then two pets | One pet, never loses XP | Shared, if it worked | Capped at Companion |
| Memories, artifacts | Copied; the second Mac's replaced | Donor's, then replayed | Shared, if it worked | Milestones and anniversaries only |
| Last.fm | Pending rows sent twice unless cleared | Untouched | One queue sent from two Macs | Untouched |
| Effort | About an hour | 2–3 days (Phase 1) | Minutes | No code; days to weeks of waiting |
| Risk | Low once, destructive if repeated | Medium, contained | High | Medium: double counts on the first Mac |

## Recommendation

Build option 2, the archive merge, as a headless command first. Use it to seed the second Mac and to send the second Mac's own plays back to the first Mac. Add Settings buttons and automatic exchange only after a few manual merges have gone well.

Why this one:

- It's the only option that ends with one history, one pet and one set of memories on both Macs, and keeps them that way.
- It reuses Dial's own rules (`BadgeResolver`, `XPFormula`, `StatsQueries`, `ArtifactsDAO`) instead of writing a second copy of them.
- No Mac ever writes to a database another machine is using. The only thing that moves between Macs is a snapshot file, opened read-only.
- It needs no server and no paid program, and it works over any transport: AirDrop today, a synced folder later.
- It's safe to run again. It's idempotent, it takes a backup first, and a dry run shows what it will change.

Until merges run regularly:

- **Keep Last.fm on one Mac**, ideally the one that's awake most.
- **Keep Dial running on both Macs.** Every listen both Macs see is one less play for the merge to carry.
- **Don't import a newer Spotify export on the first Mac** until `Importer` has an import-to-live twin rule. It would double count the live plays.
- **Nothing on a new second Mac needs saving.** The merge keeps its plays and replaces its memories and pet.

## Merge rules

### The snapshot

- `Dial --export-archive <file>` runs `VACUUM INTO`, which gives a consistent single file, includes what's still in the WAL, and is safe while Dial runs. It then adds a `dial_archive_info` table: Mac id and name, export time, the last migration applied, and the play count. The file is a plain SQLite database named `*.dialarchive`. No secrets live in the database, so none travel.
- **Mac id:** a hash of the hardware `IOPlatformUUID`, which stays the same for the life of the machine. It isn't stored in the database or `UserDefaults`, so neither a database copy nor Migration Assistant can clone it. The computer name is used for display.
- **A plain copy works too.** `sqlite3 dial.sqlite "VACUUM INTO '…'"` on the other Mac needs no new Dial there. It has no `dial_archive_info`, so pass `--source-name "<name>"`; its plays get the origin `unidentified:<name>`.
- **The merge refuses** a snapshot that fails `PRAGMA integrity_check`, one with migrations this build doesn't know ("Update Dial on this Mac first"), one from this same Mac, and a Dial History export (`integrations/dial_history`), which has plays but no memories or pet.

### Order of steps

`Dial --merge-archive <file> [--dry-run] [--source-name <name>]` only ever reads the archive. A real merge refuses to run while Dial is running, as `--import` does; a dry run is safe while it runs. The merge makes a working copy of the archive in `Dial/Merging/`, attaches a copy of the snapshot, and runs these steps on the working copy:

1. **Metadata:** union `tracks` and `artists` (fill blanks, never overwrite, except that real Spotify artist ids replace the synthetic ids imported history carries). Union the tag and enrichment tables; the newer `fetched_at` wins per key. Then run `ArtistIdentityRepair.rebuildAliases`.
2. **Plays:** walk the snapshot's plays oldest first. Skip any play that has a twin here; otherwise insert it with `origin` set to the Mac that first recorded it.
3. **Tricks:** union, keeping the earliest `unlocked_at` per trick.
4. **Donor and replay point:** choose them from the plays each side lacked.
5. **Memories:** keep the donor's memories from before the replay point, then replay the rest.
6. **Pet:** apply the pet rules.
7. **Weekly memories:** keep the donor's rows, and recompute those for weeks that end after the replay point with `StatsQueries.weeklyMemory`. The app fills in missing recent weeks itself.
8. **Artifacts:** delete them all and rebuild with `ArtifactsDAO.syncFromMemoriesAndTricks`.
9. **Log:** write one `archive_merges` row: when, which Mac, the snapshot's time, plays added, the donor and the replay point.

A dry run prints its report and deletes the working copy. A real merge goes on only if `PRAGMA integrity_check` passes, the play counts add up (plays before plus plays added equals plays after), and the archive hasn't changed since the working copy was taken. It then backs the archive up (`VACUUM INTO` to `Dial/Backups/dial-before-merge-<time>.sqlite`), deletes the archive's old `-wal` and `-shm`, and swaps the working copy in. The memory replay uses a second, throwaway copy, so no play in the archive is ever deleted or renumbered: deleting a play would cascade to its scrobble row. `VACUUM INTO` keeps `INTEGER PRIMARY KEY` ids, so play and queue ids survive the swap. If anything fails, `dial.sqlite` is left as it was.

### Twins

Twin matching treats two rows as one listen when they're for the same track and:

| Rows | Same listen when |
|---|---|
| Any two | Same `played_at`, `track_uri` and `ms_played` (the unique index) |
| `live` and `live` | Start times less than half the track's length apart, at most 60 s |
| `recent` and any non-`recent` row | The other row's time is in [t − d − 5 s, t + d), where t is the `recent` row's time (the v18 window) |
| Counted `import` and `live` | The live start is within the same half-length tolerance of the import's start: its time minus `ms_played` |
| `import` and `import`, `recent` and `recent` | The exact key only; the same export or fetch gives the same row |

Two Macs' start estimates for one live listen land seconds apart, and a replay starts a whole track later, so half the length tells them apart even for back-to-back repeats. An export row is stamped when the stream stopped and measures the time listened, so its listen started `ms_played` before its stamp. Imported skips (under 30 s and under half the track) never match. `d` is the track's duration in seconds (at least 30 s), or 600 s if unknown, as in `PetEngine`'s recent-play rule. An incoming play with a twin here is skipped, and the local row stays. The check covers rows the merge has just added, so a snapshot's own hidden `recent` duplicates don't come along. Every lookup is a range scan on `plays_by_track`.

### Donor and replay point

- `m_here` is the time of the earliest counted play this Mac lacked. `m_there` is the time of the earliest counted play here that the snapshot lacks, found with the same twin rules run the other way. A side that lacks nothing has m = ∞.
- **The donor** is the side with the later m: it knew everything the other did up to that point. **The replay point** `w` is the donor's m. If both are ∞, the archives already match and the merge stops after step 3.
- Run on either Mac, the same pair of archives gives the same donor and `w`, so a two-way merge converges.

| Seed | `m_here` | `m_there` | Donor | Replay from |
|---|---|---|---|---|
| On the second Mac, merging the first Mac's snapshot | The first Mac's first play | The second Mac's first play the first Mac missed | First Mac | That play: only the days since the second Mac's install |
| On the first Mac, merging the second Mac's snapshot | That same play | The first Mac's first play | First Mac (itself) | The same play |

**Replaying memories.** In a throwaway copy of the merged working copy, delete the plays from `w` on. Re-insert them oldest first, calling `BadgeResolver.recordMemories` for each: `.imported` for imports of at least 30 s and `.live` for the rest, the same calls `Importer` and `PetEngine` make. Each play is then the newest row when it's judged, exactly as when it was first recorded, and look-backs see the full merged history before it. Copy the throwaway copy's memories from `w` on into the working copy, replacing the ones there. The cost is one resolver pass per play after `w`, and the dry run prints the count.

### Pet rules

- `xp` = max(this Mac's XP, the donor's XP plus XP for the counted plays the donor lacked). Each lacked play is scored oldest first with `XPFormula`:
  - minutes played
  - +50 or +25 when the merged archive has no earlier play by that artist or from that album
  - the streak multiplier from the merged days
  - for imports, base XP only and within the 25,000 cap
- `streak_days`, `streak_anchor_date` and `last_play_at` are recomputed from the merged set of days with a counted non-import play.
- `installed_at`, `hatched_at` and `elder_unlocked_at` take the earliest value from either side. `stage` comes from `PetStageTable` (Elder only with `elder_unlocked_at`).
- After a two-way merge both pets match. The only exception is where `max` kept a slightly higher local XP. XP never goes down.

### What a merge never touches

`lastfm_scrobbles`, `recent_play_sync_state`, `imports_log`, settings and secrets. A merge never deletes a local play. Merged plays carry `origin`, and `ScrobbleQueueDAO.enqueue` also requires `origin IS NULL`. Today's code can't reach the queue with a merged play anyway; the check guards future paths.

## Build plan

### Phase 1: headless merge (done)

1. **Migration `v19_multi_mac`**, appended after v18: add `plays.origin TEXT` (NULL means recorded here) and an `archive_merges` table. Make `ScrobbleQueueDAO.enqueue` require `origin IS NULL`. Add migration and queue tests.
2. **`MacIdentity`:** the hashed `IOPlatformUUID` plus the computer name.
3. **`PlayTwinMatcher`:** each rule from the Twins table, as a pure decision plus an indexed lookup. Test each rule, including that back-to-back replays stay two plays.
4. **`ArchiveExporter`** and `--export-archive`: open the archive read-only so export works while Dial runs. Test that the snapshot opens on its own, carries `dial_archive_info`, and includes rows still in the WAL.
5. **`ArchiveMerger`** with `--merge-archive`, `--dry-run` and the automatic backup, in the step order above. `MemoryReplay` and `PetMerge` are separate, testable pieces.
6. **Merge tests:**
   - Split one play stream across two archives with gaps and record each side through `PetEngine`. Merge both ways. Both archives end with the same counted plays, the same memories as one archive that saw every play (ignoring ids and timestamps a few seconds apart), and the same pet XP.
   - Merging the same snapshot twice equals merging it once.
   - A round trip from Mac A to Mac B and back changes nothing.
   - Listens counted live on both Macs never double.
   - XP never decreases.
   - The scrobble queue is unchanged, and merged plays can't be queued.
   - Seed case: a one-day archive merged with a large one ends with the large one's memories plus the replayed day.
7. **Measure on real data:** run `--dry-run` against a copy of the first Mac's archive. If the numbers surprise, revisit the plan before step 8.
   - *Measured 2026-10-23* on a real archive. Merging the plays takes seconds. Replaying memories takes nearly all the time, at under a second per replayed play, with the pet, weekly memories, artifacts and checks included.
   - A separate re-implementation of the twin and pet rules matched the dry run's pet XP to within one play.
8. **Seed for real:** export on the first Mac, AirDrop the file, dry run on the second Mac, merge. Then export on the second Mac and merge on the first Mac. Check both Macs show the same Stats totals, memory and artifact counts, pet XP within a few points, the second Mac's false First Listens gone, and unchanged Last.fm queues.
   - *Second Mac seeded 2026-10-23*, with Dial quit. The integrity check passed afterwards, the Last.fm queue and recently-played cursor were untouched, and the backup is in `Dial/Backups/`.
   - A Dial build without v19 reopened the merged archive normally.
   - Still to do: the reverse merge, so the first Mac gets the plays only the second Mac heard.
9. **Docs:** add `Dial/Sync` and the merge rules to `AGENTS.md` (merges never touch `lastfm_scrobbles`; what `origin` means). Done.

### Phase 2: optional, after a few weeks of manual merges

10. **Settings › Spotify › Listening history:** "Export Archive…" and "Merge Archive…" next to Import Folder. The merge runs in the app on a background queue; the final write is one transaction.
11. **Automatic exchange:** each Mac writes its own compressed snapshot into a folder you choose (iCloud Drive by default) when it has new plays, at most every few hours. It merges any newer snapshot from another Mac, copying it out and validating it first. The snapshot size decides the cadence. If snapshots turn out too large, switch to monthly append-only play files per Mac.
12. **Last.fm across devices:** decode `device` from `/me/player` (Dial ignores it today). Scrobble a listen only on the Mac that played it, plus phone and speaker plays on the one Mac where "Scrobble other devices" is on. Test it live first, because the Spotify app on an idle Mac may mirror another device's playback.

### Follow-ups, separate from this work

- Give `Importer` the import-to-live twin rule, reusing `PlayTwinMatcher`, so a fresh Spotify export can fill gaps neither Mac recorded without double counting live plays.

## Not in v1

Live or real-time sync. Merging settings, Last.fm state or the recent-play cursor. Undo: restore the automatic backup instead. Recomputing the whole pet or every memory from scratch. More than two Macs: the rules allow it, but it's untested.

## Verification

- Unit tests from Phase 1 steps 1–6, including the replay-equivalence test, which is what proves the merge reuses Dial's rules faithfully.
- A dry run against a copy of the real archive before any real merge (step 7).
- After the seed (step 8), on both Macs: the same lifetime and year-to-date totals in Stats, the same memory and artifact counts, pet XP within a few points, no false First Listens from the second Mac's first day, and unchanged Last.fm queues.

## Code map

| File | Role |
|---|---|
| `Dial/Sync/MacIdentity.swift` | Per-Mac id and display name |
| `Dial/Sync/ArchiveExporter.swift` | `VACUUM INTO` plus `dial_archive_info`; `ArchiveInfo`, `ArchiveError`, `ArchiveFiles` |
| `Dial/Sync/PlayTwinMatcher.swift` | When two rows are one listen |
| `Dial/Sync/ArchiveMerger.swift` | Merge steps, backup, dry-run report |
| `Dial/Sync/MemoryReplay.swift` | Replays memories from `w` in a throwaway copy |
| `Dial/Sync/PetMerge.swift` | Pet rules |
| `Dial/Store/Migrations.swift` | `v19_multi_mac` |
| `Dial/Store/DAO/ScrobbleQueueDAO.swift` | `origin IS NULL` guard |
| `Dial/App/AppDelegate.swift` | `--export-archive`, `--merge-archive`, `--dry-run`, `--source-name` |

Tests: `MacIdentityTests`, `PlayTwinMatcherTests`, `ArchiveExporterTests`, `ArchiveMergerTests` (replay equivalence across all eight memory kinds, the seed case, the pet rules, idempotence and refusals), `ScrobbleQueueDAOTests`, and the v19 case in `DatabaseStackTests`.
