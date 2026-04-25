# Dial QA Checklist

Manual smoke tests to run before tagging a release. Pair with `xcodebuild test` for the automated layer.

## First-run / onboarding

- [ ] App launches with no Dock icon; status-bar pet (egg) visible at top-right.
- [ ] Settings opens via `⌘,` and shows "Connect Spotify" button.
- [ ] OAuth completes; force-expire the access token (clear it via Keychain Access) and confirm the next API call refreshes silently — no extra modal.

## Live polling

- [ ] Play a track in Spotify; within ~3 s the strip updates with the title.
- [ ] Pause Spotify → strip switches to "Paused" + pet sits down with droopy ears.
- [ ] Reach 30 s of a play → `PLAYS · 30D` ticks up by 1 in the dropdown.
- [ ] Skip to a brand-new track → dropdown shows `FIRST LISTEN` chip; pet plays exclamation animation.

## Badges

- [ ] Brand-new track → `FIRST LISTEN` (amber chip).
- [ ] Replay a track that was last heard 90+ days ago (seed via SQLite if needed) → `REDISCOVERED` (ivory chip).
- [ ] Run a track to ≥10 plays in 30 d AND rank 7d ≤ 5 → `ON STREAK` (orange chip).
- [ ] Verify priority: when a track qualifies for multiple badges, only the highest-priority one shows (`firstListen > rediscovered > onStreak`).

## Pet

- [ ] Fresh install: stage = `egg`.
- [ ] Cross 500 XP (~8 hours of unique-artist listening) → `hatching`.
- [ ] Cross 1 000 XP → `hatchling`.
- [ ] First-listen event pops the exclamation animation; settles back to `idle` within ~400 ms.
- [ ] Stop listening for 7+ days → pet enters `dormant` (lying down, fading Z's).
- [ ] Resume listening → pet returns to `idle` immediately.
- [ ] Verify elder is locked: even with 100 K+ XP, stage stays at `companion` until 30 calendar days have passed since install.

## Beat sync

- [ ] Play a high-BPM track (e.g. 140 BPM) → pet bobs visibly faster than at 80 BPM.
- [ ] Toggle pause → bob halts.

## Menubar strip

- [ ] When playing: strip shows pet sprite + track title + `·<plays30d>` count.
- [ ] When narrow (other menubar apps consume space): strip auto-collapses to pet + `·<count>`.
- [ ] When paused: strip shows "Paused" in muted ivory.
- [ ] No layout jitter when track title length changes substantially.

## Dropdown (320×360)

- [ ] Status rail: amber hairline + pet (2× scale) + "NOW PLAYING" + progress timer.
- [ ] Track hero: 52 px album art + title + artist · album.
- [ ] Readouts row: PLAYS · 30D and RANK · 7D as big amber numerals; deltas in tiny mono.
- [ ] Badge row: hidden when none of the three triggers fire.
- [ ] Artist context: `#N · 7D` rank + lifetime count.
- [ ] Session timeline: bars for last 60 min, current bar full amber + glow.
- [ ] Controls: ⏮ ⏯ ⏭ work; HISTORY / STATS labels visible (drill-downs are stubbed in v1).

## History import

- [ ] Drop a Spotify Extended Streaming History folder onto Settings → "Last import: N rows" appears.
- [ ] Re-import same folder → `0` new rows (idempotent).
- [ ] Verify imported XP capped at 25 000 (companion threshold) regardless of history size.
- [ ] Test both filename formats: `endsong_*.json` and `Streaming_History_Audio_*.json`.

## Regression

- [ ] All `xcodebuild test` cases pass (currently 57).
- [ ] Snapshot tests pass on a fresh `xcodegen generate` + clean build.
- [ ] Spot-check stats in dropdown vs. SQLite via `sqlite3 ~/Library/Application\ Support/Dial/dial.sqlite`.
- [ ] Quit + relaunch → state survives (XP, stage, streak persist).

## Edge cases

- [ ] Spotify is not running → strip shows "Nothing playing" in muted ivory.
- [ ] Token expired → next poll auto-refreshes; no modal.
- [ ] Rate limit (429) hit → backoff with no crash; strip shows muted dot indicator (when implemented).
- [ ] Malformed import file → skipped row count visible in `imports_log.notes`.
