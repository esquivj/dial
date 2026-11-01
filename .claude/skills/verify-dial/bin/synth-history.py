#!/usr/bin/env python3
"""Write a synthetic Spotify Extended Streaming History file for Dial Verify.

Every name is made up ("Verify Track 01" by "Verify Artist A"), so the output
is never real listening data. The newest play ends five minutes before the
script runs and is always Verify Track 01, so "today" and "this week" have
data and a journey has one fixed fact to look for. About one play in ten is a
skip under 30 s, which counted_plays leaves out. The rest is deterministic
for a given --plays, --days and --label.

--label gives a second, separate catalog ("Verify Mac B Track 01", its own
track URIs and its own play pattern), for history that should not overlap
the default one, such as another Mac's.

  synth-history.py --out DIR/Streaming_History_Audio_verify.json [--plays 120] [--days 21] [--label NAME]

dialctl seed runs this and imports the result; see ../SKILL.md.
"""
import argparse
import json
import random
from datetime import datetime, timedelta, timezone


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", required=True)
    parser.add_argument("--plays", type=int, default=120)
    parser.add_argument("--days", type=int, default=21)
    parser.add_argument("--label", default="")
    args = parser.parse_args()

    rng = random.Random(f"dial-verify:{args.label}")
    name = f"Verify {args.label} " if args.label else "Verify "
    uri_prefix = ("Verify" + "".join(ch for ch in args.label if ch.isalnum()) + "Track")[:16]
    artists = [f"{name}Artist {letter}" for letter in "ABCDEF"]
    tracks = []
    for i in range(24):
        artist = artists[i % len(artists)]
        tracks.append({
            "uri": f"spotify:track:{uri_prefix}{i + 1:0{22 - len(uri_prefix)}d}",
            "name": f"{name}Track {i + 1:02d}",
            "artist": artist,
            "album": f"{name}Album {artist[-1]}{i // len(artists) % 2 + 1}",
        })
    weights = [1 / (i + 1) for i in range(len(tracks))]  # Track 01 plays most

    now = datetime.now(timezone.utc).replace(second=0, microsecond=0)
    average_gap = max(timedelta(days=args.days).total_seconds() / max(args.plays, 1), 300)
    ends_at = now - timedelta(minutes=5)
    rows = []
    for n in range(args.plays):
        track = tracks[0] if n == 0 else rng.choices(tracks, weights)[0]
        skipped = n > 0 and rng.random() < 0.1
        rows.append({
            "ts": ends_at.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "platform": "osx",
            "ms_played": rng.randint(4_000, 20_000) if skipped else rng.randint(150_000, 240_000),
            "spotify_track_uri": track["uri"],
            "master_metadata_track_name": track["name"],
            "master_metadata_album_artist_name": track["artist"],
            "master_metadata_album_album_name": track["album"],
            "reason_start": "trackdone",
            "reason_end": "fwdbtn" if skipped else "trackdone",
            "skipped": skipped,
            "shuffle": False,
            "offline": False,
        })
        ends_at -= timedelta(seconds=max(240, rng.uniform(0.5, 1.5) * average_gap))
    rows.reverse()

    with open(args.out, "w") as handle:
        json.dump(rows, handle, indent=1)
    full = sum(not row["skipped"] for row in rows)
    print(f"wrote {len(rows)} synthetic plays ({full} full, {len(rows) - full} skips) to {args.out}")


if __name__ == "__main__":
    main()
