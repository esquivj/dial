# Multi-Mac history

One Mac exports its listening archive with `--export-archive`, and another merges it with `--merge-archive`. The merge adds the plays the receiving Mac lacks, each with `plays.origin` naming the Mac that recorded it. A dry run reports what would change and changes nothing, a real merge backs the database up first, and merging the same archive again adds nothing. Spec: `docs/design/multi-mac-history.md`.

## Sub-features

- `mm-export` writes an archive (a SQLite snapshot with one `dial_archive_info` row) and prints its play count and Mac name.
- `mm-dry-run` prints the full merge report and changes nothing, even while Dial runs.
- `mm-refuse-running` refuses a real merge while Dial runs.
- `mm-merge` adds the missing plays with `origin` set, logs one `archive_merges` row, and backs up to `Dial/Backups/dial-before-merge-<time>.sqlite` first.
- `mm-repeat` adds 0 plays when the same archive is merged again. It still takes a backup and logs a row, as the spec says ("It's safe to run again").
- `mm-scrobble-guard` keeps merged plays out of the Last.fm queue: `lastfm_scrobbles` is untouched.
- `mm-refuse-same-mac` refuses an archive exported on this Mac (`ArchiveError.sameMac`). Not driven yet.

## How to get to it (user POV)

- On the sending Mac, run `Dial.app/Contents/MacOS/Dial --export-archive <file>`, then move the file over (AirDrop).
- On the receiving Mac, run `Dial.app/Contents/MacOS/Dial --merge-archive <file> --dry-run`, then quit Dial and run it again without `--dry-run`.
- v1 has no UI for this; it is headless only.

## Driving it with dialctl

Preconditions:

- The baseline: Dial Verify launched with `--fresh --seed`, so 120 plays, none with an origin, and no merges.
- No `.build/verify/home-macb` left from an earlier run (`seed --fresh` below replaces it).

- **Make Mac B's history.** Stop the copy and seed a second home with its own catalog. Run `$D stop`, then `DIAL_VERIFY_HOME=.build/verify/home-macb $D seed --fresh --plays 40 --label "Mac B"`. It prints `40 synthetic plays (35 full, 5 skips)`, a `→ DB:` path inside `home-macb`, and `✓ Done … 40 new plays`.
- **Export (`mm-export`).** Run `ART=$($D evidence)`, then `DIAL_VERIFY_HOME=.build/verify/home-macb $D cli --export-archive "$ART/mac-b.dialarchive"`. It exits 0 with `✓ Wrote …/mac-b.dialarchive: 40 plays from <this Mac's name>`.
- **Stand in for the other Mac.** A Mac can only export under its own hardware id, and a merge refuses that id (`mm-refuse-same-mac`). Restamp the exported file. This is the one simulated step: `sqlite3 "$ART/mac-b.dialarchive" "UPDATE dial_archive_info SET mac_id = '00000000000b0b0b', mac_name = 'Verify Mac B'"`.
- **Record the before state.** Run `$D launch`. Then run `$D db "SELECT (SELECT count(*) FROM plays) plays, (SELECT count(*) FROM plays WHERE origin IS NOT NULL) merged, (SELECT count(*) FROM archive_merges) merges, (SELECT count(*) FROM lastfm_scrobbles) scrobbles" | tee "$ART/mm-before.txt"` and `ls -l ".build/verify/home/Library/Application Support/Dial" | tee -a "$ART/mm-before.txt"`. You should see 120, 0, 0 and 0, and no `Backups` folder.
- **Dry run while Dial runs (`mm-dry-run`).** Run `$D cli --merge-archive "$ART/mac-b.dialarchive" --dry-run`. It exits 0. The report includes `Snapshot from Verify Mac B: 40 plays` and `Plays: 40 added (import 40), 0 already here`, and ends with `✓ Dry run: nothing changed. Run again without --dry-run to merge.` Run the before query and listing again: the counts are unchanged and there is still no `Backups` folder.
- **Refused while running (`mm-refuse-running`).** Run `$D cli --merge-archive "$ART/mac-b.dialarchive"`. It exits 1 with `✗ Dial is already running (PID …). Quit it first, or add --dry-run.`, and the counts don't change.
- **Merge (`mm-merge`, `mm-scrobble-guard`).** Run `$D stop`, then `$D cli --merge-archive "$ART/mac-b.dialarchive"`. It exits 0 with `✓ Merged. Backup: …/Dial/Backups/dial-before-merge-<time>.sqlite`. Check the results:
  - The before query now gives 160, 40, 1 and 0.
  - `$D db "SELECT source_mac_name, plays_added, donor FROM archive_merges"` gives `Verify Mac B | 40 | here`.
  - `$D db "SELECT DISTINCT origin FROM plays WHERE origin IS NOT NULL"` gives `00000000000b0b0b`.
  - The backup file exists.
- **Repeat (`mm-repeat`).** Run the same merge again. It exits 0 with `Plays: 0 added, 40 already here`. There are now two backups and two `archive_merges` rows, and still 160 plays.
- **Dial reads the merged archive.** Run `$D launch`, then `$D doctor`. Doctor reports `database at v19_multi_mac: 160 plays, 143 counted`, which is this Mac's 108 plus Mac B's 35.

## Gotchas

- A real merge refuses while any process with the same bundle id is running, so stop the copy first. The real Dial doesn't block the copy, because its bundle id is different.
- Restamping `dial_archive_info` is the only simulated step; everything after it is the real merge path. Leave `play_count` alone: the merge checks it against the snapshot's plays.
- To re-run the journey, start again from `launch --fresh --seed` and `seed --fresh`, or the expected counts shift.
- The merge report also replays memories and the pet ("Memories 3 → 4 … Pet 374 XP egg → 491 XP egg" on 2026-11-01). Those numbers depend on the date, so check that the lines are there, not their exact values.
- The export writes this Mac's computer name into `dial_archive_info.mac_name`. Evidence stays in `.build/`, which is gitignored; never commit an archive.
