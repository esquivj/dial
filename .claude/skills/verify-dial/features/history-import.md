# History import

Dial imports Spotify's Extended Streaming History, the `Streaming_History_Audio_*.json` or `endsong_*.json` files from a Spotify data export, into its local archive. It keeps every row, skips included. Stats, ranks and badges count only `counted_plays`: rows of at least 30 s, or at least half of a known track duration. Importing the same files again adds nothing.

## Sub-features

- `import-headless`: `--import <folder>` imports every matching file, prints per-file and total counts, and exits.
- `import-settings`: General › Listening history › `Import Folder` picks the export folder and shows the result in the row's subtitle.
- `import-dedup`: re-importing rows already in the archive adds 0. The unique key is `(played_at, track_uri, ms_played)`.
- `import-counted`: skips under 30 s land in `plays` but not in `counted_plays`.
- `import-refuse-running`: the headless import refuses while Dial runs.
- `import-no-files`: a folder with no matching files exits 1 and changes nothing.

## How to get to it (user POV)

- In a terminal, with Dial quit: `Dial.app/Contents/MacOS/Dial --import <folder with the export's JSON files>`.
- In Dial Settings › General › Listening history, choose `Import Folder` (its help reads "Select the folder from Spotify's Extended Streaming History export.") and pick the folder. The subtitle changes from "No history folder imported." to "Last import: N plays".

## Driving it with dialctl

Preconditions:

- Dial Verify is built and stopped (`$D stop`).

- **Fresh import (`import-headless`, `import-counted`).** Run `$D launch --fresh --seed`. The seed step prints a `→ DB:` path inside `.build/verify/home/`, then `[ 1/1] Streaming_History_Audio_verify.json: 120 inserted (120 parsed)` and `✓ Done … 120 new plays`, and `cli-01-import.exit` holds 0. Then `$D db "SELECT (SELECT count(*) FROM plays) plays, (SELECT count(*) FROM counted_plays) counted, (SELECT count(*) FROM imports_log) imports"` gives 120, 108 and 1.
- **Newest play.** Run `$D db "SELECT t.name, datetime(c.played_at, 'unixepoch') AS utc FROM counted_plays c JOIN tracks t ON t.uri = c.track_uri ORDER BY c.played_at DESC LIMIT 1"`. It gives `Verify Track 01`, five minutes before the seed ran (UTC).
- **Refused while running (`import-refuse-running`).** With the copy running, run `$D cli --import .build/verify/home/seed`. It exits 1 with `✗ Dial is already running (PID …). Quit it first:`, and `plays` doesn't change.
- **Dedup (`import-dedup`).** Run `$D stop`, then `$D cli --import .build/verify/home/seed`. It prints `0 inserted (120 parsed)` and `deduped: 120`, and `plays` is still 120.
- **No files (`import-no-files`).** Run `mkdir -p .build/verify/home/empty && $D cli --import .build/verify/home/empty`. It exits 1 with `No endsong_*.json or Streaming_History_Audio_*.json files in …`.
- **Settings import (`import-settings`).** This needs UI control: computer-use on `com.dial.Dial.verify`, with the user's grant. Open Dial Settings › General, choose `Import Folder`, and pick `.build/verify/home/seed` in the open panel. Proof: the subtitle reads `Last import: 0 plays` after the seeded baseline, or the new count on a home without that seed, and `imports_log` gains a row. Not driven yet.

## Gotchas

- The import refuses while the copy runs, and so does `$D seed`. Its message suggests `killall Dial`: never run that. It would also kill the user's real Dial. Use `$D stop`.
- Only files whose names start with `Streaming_History_Audio_` or `endsong_` are read. Other files in the folder are ignored.
- Never import a real Spotify export to prove something: real exports are personal data. The made-up seed covers the import path.
- `--seed` puts its file in `<home>/seed/`, so that folder exists only in homes seeded by this version of `dialctl`.
- Compare the numbers stats show with `counted_plays`, not `plays`.
