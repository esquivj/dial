# Dial History

Dial collects Spotify history. This interface lets other apps read that saved history through a stable JSON contract, without Spotify credentials or permission to write to Dial.

## Find it

- Human and agent entry point: `~/Music/Dial/README.md`
- Local discovery: `~/Music/Dial/manifest.json`
- Command: `~/.local/bin/dial-history`
- Local API: `http://127.0.0.1:8765`
- Cloud URL: `cloud_base_url` (also the preferred `remote_base_url`) in the local manifest
- Remote discovery: `GET <cloud-base-url>/.well-known/dial-history`
- API description: authenticated `GET /openapi.json`

The discovery file tells a consumer where the API, command, docs, and **separate Dial History read token** live. The HTTP discovery response has no local paths or credentials. Give a new app the discovery file or private base URL once; it can discover the available routes from there. There is no global network discovery or automatic configuration of unrelated apps.

## Quick start

```sh
dial-history status
dial-history plays --limit 5
dial-history plays --since 2026-10-01 --until 2026-11-01 --source recent
dial-history top artists --since 2026-01-01 --min-ms 30000 --limit 10
dial-history top tracks --since 2026-01-01 --min-ms 30000 --limit 10
dial-history export "$HOME/Music/Dial/exports/$(date -u +%Y%m%dT%H%M%SZ)"
```

All commands print JSON. `--db /path/history.sqlite` before the command reads an exported snapshot. The app does not need to be running to read its archive; it does need to run and remain connected to Spotify to collect new plays.

Every data response includes `schema_version`, `read_at`, `freshness`, and `notes`. Use `/v1/status` before interpreting any ranking. A recent successful sync does **not** prove that older history is complete.

## API v1

| Method and route | Meaning |
| --- | --- |
| `GET /.well-known/dial-history` | Discovery and semantics; no listening records; no authentication |
| `GET /openapi.json` | API description; bearer token required |
| `GET /v1/status` | Source coverage, monthly records, missing months, metadata and freshness |
| `GET /v1/plays` | Saved plays with track/artist metadata and duration provenance |
| `GET /v1/top/artists` | Rank by saved record count, attributed to first credited artist |
| `GET /v1/top/tracks` | Rank by saved record count, grouped by exact Spotify track URI |

Data routes require `Authorization: Bearer <read token>`. No arbitrary SQL, database downloads, filesystem routes, writes, Spotify access tokens, or refresh tokens are exposed. Unknown routes return 404, bad queries 400, absent/wrong credentials 401, unavailable archives 503, and write methods 405. No cross-origin browser access is enabled: web apps should call from their backend and keep the read token server-side.

Play and ranking filters:

- `since`: inclusive UTC date or ISO timestamp with an explicit timezone.
- `until`: exclusive UTC date or ISO timestamp with an explicit timezone.
- `source`: `import`, `live`, or `recent`; omit to include all saved records.
- `min_ms`: filter on **stored** milliseconds, default 0. Imported skipped tracks are included by default. A 30-second threshold is an explicit consumer choice, not a claim about Spotify's counting rules.
- `limit`: 1–1000 for plays; 1–100 for rankings. Default 100.
- `cursor`: plays only. Reuse the same filters and the returned `next_cursor` until null.

Pagination orders by event time and ID descending. Page one fixes a maximum record ID so concurrent inserts/backfills don't shift the pages. Existing metadata may still change; use a snapshot for reproducible analysis. IDs belong to this archive, not to Spotify, and are not portable across independently imported archives. Cursor pagination is for traversal, not a change-data feed: rescan/export to pick up metadata repairs, deletions, and historical imports.

## What the data actually means

The grain is **a record saved by Dial**. Dial performs its own deduplication; the interface does not silently merge or remove more records. Rankings are not Spotify affinity rankings or a guarantee of unique completed listens.

| `source` | `stored_ms_played` | Timestamp |
| --- | --- | --- |
| `import` | Measured duration from Spotify Extended Streaming History | Export event timestamp |
| `live` | Playback progress observed when Dial counted the play; may be partial | Estimated start time |
| `recent` | Track-duration estimate used by Dial's recent-play reconciler | Spotify recently-played timestamp |

Do not sum all three sources as exact listening time. Fields `duration_basis` and `timestamp_basis` travel with every play. Missing names/artists remain null or empty and are marked in `artist_metadata`. Imported synthetic artist IDs may be resolved using Dial's artist aliases; each artist retains `original_uri` and `identity_basis`. Different releases with different track URIs remain separate.

`status.coverage.months_without_records_between_first_and_last` means **unknown listening**, not zero. Partial months and days with no rows are not guaranteed complete either. As verified on October 11, 2026, the archive has 195,504 records, imports from November 2015 through April 24, 2026, later live/recent observations, and no saved records for July–September 2026. These figures are a dated check; query status for current facts.

## Use from another app

Python, directly on this Mac, without handling a credential:

```python
import json, subprocess
from pathlib import Path
manifest = json.loads((Path.home() / "Music/Dial/manifest.json").read_text())
result = subprocess.run([manifest["command"], "plays", "--limit", "10"],
                        check=True, capture_output=True, text=True)
plays = json.loads(result.stdout)
```

Python, through the authenticated API:

```python
import json, urllib.request
from pathlib import Path
manifest = json.loads((Path.home() / "Music/Dial/manifest.json").read_text())
token = Path(manifest["token_file"]).read_text().strip()
request = urllib.request.Request(manifest["local_base_url"] + "/v1/plays?limit=10",
                                 headers={"Authorization": "Bearer " + token})
with urllib.request.urlopen(request, timeout=10) as response:
    plays = json.load(response)
```

For a remote consumer, configure the cloud base URL and read token on its backend. The read token grants access to the whole saved listening archive; it grants no Spotify account control. No Spotify credential needs to leave this Mac.

## Cloud apps and Vercel

The cloud service uses the same v1 routes and query code as the local reader. It runs in a dedicated `dial-history` Vercel project and reads a compressed SQLite snapshot from a **private** Blob store. Your web app's backend needs only `DIAL_HISTORY_URL` and `DIAL_HISTORY_READ_TOKEN`. Use `cloud_base_url` and `cloud_access.token_file` from the local discovery manifest to configure them. The cloud read key is separate from the local API key and from the Blob write credential. Never expose either key in browser JavaScript or a `NEXT_PUBLIC_` variable.

```js
// Server-side code, usable from Vercel or another HTTPS-capable backend.
const response = await fetch(`${process.env.DIAL_HISTORY_URL}/v1/plays?limit=10`, {
  headers: { Authorization: `Bearer ${process.env.DIAL_HISTORY_READ_TOKEN}` },
  cache: 'no-store',
});
if (!response.ok) throw new Error(`Dial History: ${response.status}`);
const history = await response.json();
```

The Mac publisher runs at login and once an hour while awake. It exports only the five allowed tables, uploads an immutable compressed snapshot, then changes the current-snapshot pointer. Interrupted uploads retain the previous snapshot. Identical content skips the upload; backfills, metadata repairs, deletions, and sync-state changes are included on the next sync. The current and previous cloud snapshots are retained, along with a two-hour grace period for in-flight reads; older generated copies are cleaned up.

Cloud queries work while this Mac sleeps, using the last successful upload. Every data response includes `cloud.snapshot_captured_at`, `cloud.last_storage_check_at`, and `cloud.refresh_failed`, alongside the original archive freshness and coverage. A warm function checks storage at most once a minute. If a refresh fails, it can serve its last verified snapshot with `refresh_failed: true`; a cold function without a valid snapshot returns 503. Uploading today's archive does not fill its historical gaps.

Sync state is at `~/Library/Application Support/DialHistory/cloud-sync-state.json`. Run the `cloud_access.sync_command` array in the local manifest for an immediate upload. Stop automatic syncing with `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.juanos.dial-history-cloud-sync.plist`; this leaves the last cloud snapshot available. Remove that LaunchAgent to prevent sync at next login. The local API and Dial keep working independently.

Source and setup: `cloud/` contains the Vercel adapter; `prepare_cloud.py` creates an allowlisted `cloud-build/` directory containing code, never listening data. Provision a private Blob store and supply `BLOB_READ_WRITE_TOKEN` plus `DIAL_HISTORY_READ_TOKEN` as Vercel secrets before deploying. The publisher uses owner-only `cloud-config.json` with its separate Blob credential. After the initial upload and HTTPS verification, `install_cloud.py --base-url <verified-url>` installs the publisher and updates discovery. The SDK is pinned to `vercel==0.11.6` in an isolated Python environment. A cold cloud function downloads the compressed snapshot once; subsequent reads reuse its local cache. Storage and transfer use your Vercel plan's allowances.

To revoke cloud readers, replace the cloud read key in the Vercel project's `DIAL_HISTORY_READ_TOKEN`, redeploy the API, update the owner-only local `cloud-read-token` file, and distribute the replacement only to intended app backends. Rotating the local API's `read-token` does not revoke the separate cloud key. The Blob upload credential is never needed by consuming apps.

## Remote access and offline use

The service always binds to `127.0.0.1`. Put an authenticated private transport, such as Tailscale Serve or an SSH tunnel, in front of it. Do not expose the Python listener directly to the internet. A live remote query needs this Mac awake and reachable. A cloud web application's backend needs network access to that private endpoint or a hosted snapshot of its own.

The optional direct connection to the live Mac uses Tailscale Serve on HTTPS port 8443. Read `private_network_base_url` and `private_network_access` in the discovery manifest (or `remote_base_url` and `remote_access` before cloud setup). A client must be on the same tailnet with access to this device, and must separately provide the local Dial History read token. Tailscale supplies transport; it does not replace the read token. No public Funnel endpoint is configured. Ordinary cloud apps should use the cloud API above.

On this Mac, Tailscale DNS is currently disabled. The HTTPS proxy and certificate were verified with an explicit mapping to its Tailscale IP, without disabling TLS verification. Remote clients using Tailscale DNS can resolve the private hostname; clients with that setting disabled need an explicit hostname-to-Tailscale-IP mapping. The local API does not depend on Tailscale DNS. Connection from a separate remote machine remains unverified.

Inspect remote routing with `/Applications/Tailscale.app/Contents/MacOS/Tailscale serve status`. Disable this route with `/Applications/Tailscale.app/Contents/MacOS/Tailscale serve --https=8443 off`; this leaves the local API available. The route survives a reader restart or reinstall. If this Mac's Tailscale name or address changes, update the local discovery manifest and remote clients.

`export` creates a portable directory with `history.sqlite`, `manifest.json`, this reader, and these docs. The exported database is freshly constructed from five allowed tables. It excludes pets, badges, import paths/logs, application preferences, tokens, and other internal tables. It never copies a live SQLite file without its WAL. The manifest records coverage, capture time, and a SHA-256 digest. Exports are snapshots taken on demand; they do not update themselves.

On another machine with Python 3.10 or later:

```sh
python3 dial_history.py --db history.sqlite status
python3 dial_history.py --db history.sqlite plays --limit 10
```

To serve a transferred snapshot behind that machine's existing HTTPS/private proxy, create a separate read token on that machine and run `python3 dial_history.py --db history.sqlite serve --token-file /private/path/read-token`. Do not reuse or transfer Spotify credentials.

## Installation and maintenance

Run `python3 integrations/dial_history/install.py` from the repo. It copies this small interface into `~/Library/Application Support/DialHistory`, installs `~/.local/bin/dial-history`, writes the discovery files to `~/Music/Dial`, and registers `com.juanos.dial-history` as a user LaunchAgent. The HTTP reader restarts at login and after a crash. It reads the current database on every query; there is no export worker or new Spotify poller.

The service and files are private to this macOS user. To revoke API clients, stop the service, replace `read-token` with a new random token of at least 32 characters, and restart the service. Restart is required after changing the token. Local command users already have the operating system permission needed to read the archive.

Stop: `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.juanos.dial-history.plist`. This leaves history and exports intact. Remove that LaunchAgent to prevent launch at next login. Tests: `python3 -m unittest discover -s integrations/dial_history/tests -v`.

Implementation references: [Python SQLite URI read-only connections](https://docs.python.org/3/library/sqlite3.html#how-to-work-with-sqlite-uris), [Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve).
