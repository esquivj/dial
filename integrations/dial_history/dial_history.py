#!/usr/bin/env python3
"""Dial History v1: credential-free readers for Dial's local listening archive."""
import argparse
import base64
import contextlib
import datetime as dt
import hashlib
import hmac
import json
import os
from pathlib import Path
import shutil
import sqlite3
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

VERSION = "1.0.0"
DB = Path.home() / "Library/Application Support/Dial/dial.sqlite"
HOME = Path.home() / "Music/Dial"
RUNTIME = Path.home() / "Library/Application Support/DialHistory"
TOKEN = RUNTIME / "read-token"
PORT = 8765
SOURCES = {
    "import": {"duration_basis": "spotify_export_measured", "timestamp_basis": "spotify_export_event_time"},
    "live": {"duration_basis": "observed_progress_at_count", "timestamp_basis": "estimated_play_start"},
    "recent": {"duration_basis": "track_duration_estimate", "timestamp_basis": "spotify_recently_played_time"},
}
NOTE = "Saved records, not a guarantee of complete Spotify history. Missing periods are unknown listening. No extra deduplication is applied. Only imported ms_played is measured listening duration."
TABLES = {
    "plays": "id INTEGER PRIMARY KEY, played_at INTEGER NOT NULL, track_uri TEXT NOT NULL, ms_played INTEGER NOT NULL, source TEXT NOT NULL",
    "tracks": "uri TEXT PRIMARY KEY, name TEXT, album_name TEXT, album_art_url TEXT, duration_ms INTEGER, artists_json TEXT",
    "artists": "uri TEXT PRIMARY KEY, name TEXT, genres_json TEXT, image_url TEXT",
    "artist_identity_aliases": "source_uri TEXT PRIMARY KEY, source_name TEXT NOT NULL, normalized_name_key TEXT NOT NULL, canonical_uri TEXT NOT NULL, canonical_name TEXT NOT NULL, confidence REAL NOT NULL, reason TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL",
    "recent_play_sync_state": "id INTEGER PRIMARY KEY, last_played_at_ms INTEGER NOT NULL, last_synced_at INTEGER NOT NULL, last_response_count INTEGER NOT NULL, last_response_saturated INTEGER NOT NULL, consecutive_saturated INTEGER NOT NULL, last_inserted_count INTEGER NOT NULL",
}


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def iso(value):
    return None if value is None else dt.datetime.fromtimestamp(value, dt.timezone.utc).isoformat().replace("+00:00", "Z")


def timestamp(value):
    if value is None:
        return None
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
        if len(value) == 10:
            parsed = parsed.replace(tzinfo=dt.timezone.utc)
        if parsed.tzinfo is None:
            raise ValueError("Use a date (UTC) or a timestamp with a timezone.")
        # Preserve fractional boundaries; SQLite compares these with stored
        # integer seconds without rounding an extra event into or out of a range.
        result = parsed.timestamp()
        return int(result) if result.is_integer() else result
    except (ValueError, OverflowError) as exc:
        raise ValueError("Invalid date: use YYYY-MM-DD or an ISO timestamp with timezone.") from exc


def discovery():
    return {"name": "Dial History", "schema_version": VERSION, "access": "read_only",
            "description": "Saved Spotify listening records collected by Dial",
            "authentication": "Authorization: Bearer <Dial History read token>",
            "routes": {"status": "/v1/status", "plays": "/v1/plays", "top_artists": "/v1/top/artists", "top_tracks": "/v1/top/tracks", "schema": "/openapi.json"},
            "time": "UTC; since inclusive, until exclusive", "source_semantics": SOURCES,
            "notes": NOTE}


@contextlib.contextmanager
def connect(path):
    path = Path(path).expanduser().resolve()
    # mode=ro must remain present: never create a missing DB or run Dial migrations.
    conn = sqlite3.connect(path.as_uri() + "?mode=ro", uri=True, timeout=3)
    conn.row_factory = sqlite3.Row
    try:
        conn.execute("PRAGMA query_only = ON")
        conn.execute("BEGIN")
        required = {"plays": {"id", "played_at", "track_uri", "ms_played", "source"},
                    "tracks": {"uri", "name", "album_name", "duration_ms", "artists_json"}}
        for table, columns in required.items():
            actual = {r["name"] for r in conn.execute(f"PRAGMA table_info({table})")}
            if not columns <= actual:
                raise ValueError("Unsupported Dial database schema; update the reader.")
        yield conn
    finally:
        conn.close()


def tables(conn):
    return {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}


def freshness(conn):
    row = conn.execute("SELECT MAX(played_at) AS last, MAX(id) AS high FROM plays").fetchone()
    info = {"last_record_at": iso(row["last"]), "max_record_id": row["high"], "last_recent_sync_at": None,
            "recent_sync_possibly_truncated": None, "source_kind": "live_database"}
    present = tables(conn)
    if "recent_play_sync_state" in present:
        state = conn.execute("SELECT * FROM recent_play_sync_state WHERE id=1").fetchone()
        if state:
            info.update(last_recent_sync_at=iso(state["last_synced_at"]),
                        recent_sync_possibly_truncated=bool(state["last_response_saturated"]))
    if "dial_history_snapshot" in present:
        snapshot = conn.execute("SELECT captured_at FROM dial_history_snapshot LIMIT 1").fetchone()
        info.update(source_kind="snapshot", snapshot_captured_at=snapshot[0] if snapshot else None)
    return info


def envelope(conn, **data):
    return {"schema_version": VERSION, "read_at": now(), "freshness": freshness(conn), "notes": NOTE, **data}


def status(conn):
    by_source = []
    for r in conn.execute("SELECT source,COUNT(*) AS records,MIN(played_at) AS first,MAX(played_at) AS last FROM plays GROUP BY source"):
        by_source.append({"source": r["source"], "records": r["records"], "first_record_at": iso(r["first"]), "last_record_at": iso(r["last"])})
    monthly = [dict(r) for r in conn.execute("SELECT strftime('%Y-%m',played_at,'unixepoch') AS month,COUNT(*) AS records,COUNT(DISTINCT date(played_at,'unixepoch')) AS observed_days FROM plays GROUP BY month ORDER BY month")]
    missing = []
    if monthly:
        year, month = map(int, monthly[0]["month"].split("-"))
        present = {r["month"] for r in monthly}
        last = monthly[-1]["month"]
        while f"{year:04}-{month:02}" <= last:
            key = f"{year:04}-{month:02}"
            if key not in present:
                missing.append(key)
            month += 1
            if month == 13:
                year, month = year + 1, 1
    meta = dict(conn.execute("SELECT COUNT(*) AS tracks,SUM(name IS NULL OR name='') AS missing_track_names FROM tracks").fetchone())
    return envelope(conn, coverage={"complete": False, "timezone": "UTC", "records": sum(r["records"] for r in by_source),
                    "by_source": by_source, "months": monthly, "months_without_records_between_first_and_last": missing,
                    "missing_period_meaning": "unknown, not zero listening"}, metadata=meta)


def filters(params):
    since, until = timestamp(params.get("since")), timestamp(params.get("until"))
    if since is not None and until is not None and since >= until:
        raise ValueError("since must precede until.")
    source = params.get("source")
    if source is not None and source not in SOURCES:
        raise ValueError("source must be import, live, or recent.")
    try:
        minimum = int(params.get("min_ms", 0))
    except (TypeError, ValueError) as exc:
        raise ValueError("min_ms must be an integer.") from exc
    if not 0 <= minimum <= 2**63 - 1:
        raise ValueError("min_ms must be a nonnegative 64-bit integer.")
    normalized = {"since": since, "until": until, "source": source, "min_ms": minimum}
    where, args = ["p.ms_played >= ?"], [minimum]
    for key, operator in [("since", ">="), ("until", "<")]:
        if normalized[key] is not None:
            where.append(f"p.played_at {operator} ?")
            args.append(normalized[key])
    if source:
        where.append("p.source = ?")
        args.append(source)
    return normalized, where, args


def limit(params, maximum=1000):
    try:
        value = int(params.get("limit", 100))
    except (TypeError, ValueError) as exc:
        raise ValueError("limit must be an integer.") from exc
    if not 1 <= value <= maximum:
        raise ValueError(f"limit must be between 1 and {maximum}.")
    return value


def artists(value, aliases):
    try:
        raw = json.loads(value or "[]")
    except (ValueError, TypeError):
        return [], "invalid"
    if not isinstance(raw, list):
        return [], "invalid"
    items = []
    for a in raw:
        if not isinstance(a, dict):
            continue
        uri = a.get("uri") if isinstance(a.get("uri"), str) else None
        name = a.get("name") if isinstance(a.get("name"), str) else None
        alias = aliases.get(uri)
        items.append({"uri": alias["canonical_uri"] if alias else uri,
                      "name": alias["canonical_name"] if alias else name,
                      "original_uri": uri, "identity_basis": "dial_alias" if alias else "stored_metadata"})
    return items, "available" if items else "missing"


def alias_map(conn):
    if "artist_identity_aliases" not in tables(conn):
        return {}
    return {r["source_uri"]: dict(r) for r in conn.execute("SELECT source_uri,canonical_uri,canonical_name FROM artist_identity_aliases")}


def play_record(row, aliases):
    artist_list, quality = artists(row["artists_json"], aliases)
    source = row["source"]
    return {"id": row["id"], "played_at": iso(row["played_at"]), "played_at_unix": row["played_at"],
            "track": {"uri": row["track_uri"], "name": row["name"], "album": row["album_name"],
                      "duration_ms": row["duration_ms"], "artists": artist_list, "artist_metadata": quality},
            "source": source, "stored_ms_played": row["ms_played"],
            **SOURCES.get(source, {"duration_basis": "unknown", "timestamp_basis": "unknown"})}


def plays(conn, params):
    normalized, where, args = filters(params)
    size = limit(params)
    fingerprint = hashlib.sha256(json.dumps(normalized, sort_keys=True).encode()).hexdigest()[:16]
    watermark = conn.execute("SELECT COALESCE(MAX(id),0) FROM plays").fetchone()[0]
    cursor = params.get("cursor")
    if cursor:
        try:
            if len(cursor) > 1024:
                raise ValueError()
            data = json.loads(base64.urlsafe_b64decode(cursor.encode()))
            if data["filters"] != fingerprint or any(type(data[k]) is not int or not 0 <= data[k] <= 2**63 - 1 for k in ["time", "id", "max_id"]):
                raise ValueError()
            watermark = data["max_id"]
            where.append("(p.played_at < ? OR (p.played_at = ? AND p.id < ?))")
            args += [data["time"], data["time"], data["id"]]
        except (ValueError, KeyError, TypeError) as exc:
            raise ValueError("Invalid cursor or filters changed between pages.") from exc
    where.append("p.id <= ?")
    args.append(watermark)
    rows = conn.execute("SELECT p.*,t.name,t.album_name,t.duration_ms,t.artists_json FROM plays p LEFT JOIN tracks t ON t.uri=p.track_uri WHERE " + " AND ".join(where) + " ORDER BY p.played_at DESC,p.id DESC LIMIT ?", args + [size + 1]).fetchall()
    more = len(rows) > size
    rows = rows[:size]
    next_cursor = None
    if more:
        last = rows[-1]
        next_cursor = base64.urlsafe_b64encode(json.dumps({"time": last["played_at"], "id": last["id"], "max_id": watermark, "filters": fingerprint}).encode()).decode()
    aliases = alias_map(conn)
    return envelope(conn, filters=normalized, items=[play_record(r, aliases) for r in rows], next_cursor=next_cursor,
                    pagination={"order": "played_at_desc,id_desc", "max_record_id": watermark,
                                "consistency": "new inserts excluded after page one; use an export for a fixed snapshot"})


def top(conn, params, kind):
    normalized, where, args = filters(params)
    size = limit(params, 100)
    rows = conn.execute("SELECT p.track_uri,COUNT(*) AS records,t.name,t.artists_json FROM plays p LEFT JOIN tracks t ON t.uri=p.track_uri WHERE " + " AND ".join(where) + " GROUP BY p.track_uri,t.name,t.artists_json", args).fetchall()
    aliases, items = alias_map(conn), {}
    for r in rows:
        artist_list, _ = artists(r["artists_json"], aliases)
        if kind == "tracks":
            key = r["track_uri"]
            items[key] = {"uri": key, "name": r["name"], "artists": artist_list, "records": r["records"]}
        else:
            primary = artist_list[0] if artist_list else {"uri": None, "name": None}
            key = primary["uri"] or ("name:" + primary["name"].casefold() if primary["name"] else "unknown")
            item = items.setdefault(key, {"uri": primary["uri"], "name": primary["name"], "records": 0})
            item["records"] += r["records"]
    ordered = sorted(items.values(), key=lambda x: (-x["records"], x["uri"] or x["name"] or ""))[:size]
    return envelope(conn, filters=normalized, metric="saved_record_count", artist_attribution="first credited artist; Dial aliases resolved",
                    identity="exact track URI; releases are not merged", items=[{"rank": i + 1, **x} for i, x in enumerate(ordered)])


def query(path, route, params=None):
    params = params or {}
    allowed = {"since", "until", "source", "min_ms", "limit", "cursor"}
    if set(params) - allowed:
        raise ValueError("Unknown query parameter.")
    with connect(path) as conn:
        if route == "/v1/status":
            if params:
                raise ValueError("status has no query parameters.")
            return status(conn)
        if route == "/v1/plays":
            return plays(conn, params)
        if route in ("/v1/top/artists", "/v1/top/tracks"):
            if "cursor" in params:
                raise ValueError("top rankings do not accept cursors.")
            return top(conn, params, route.rsplit("/", 1)[-1])
    raise LookupError("Unknown route.")


def export_snapshot(path, output):
    output = Path(output).expanduser().resolve()
    if output.exists():
        raise ValueError("Export destination already exists; choose a new directory.")
    output.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".dial-export-", dir=output.parent))
    try:
        with connect(path) as src, contextlib.closing(sqlite3.connect(staging / "history.sqlite")) as dst, dst:
            captured = now()
            existing = tables(src)
            for table, schema in TABLES.items():
                dst.execute(f"CREATE TABLE {table} ({schema})")
                if table not in existing:
                    continue
                columns = [r[1] for r in dst.execute(f"PRAGMA table_info({table})")]
                select = ",".join(columns)
                marks = ",".join("?" for _ in columns)
                source_rows = src.execute(f"SELECT {select} FROM {table}")
                while batch := source_rows.fetchmany(1000):
                    dst.executemany(f"INSERT INTO {table} ({select}) VALUES ({marks})", [tuple(r) for r in batch])
            dst.execute("CREATE INDEX plays_by_time ON plays(played_at,id)")
            dst.execute("CREATE INDEX plays_by_track ON plays(track_uri,played_at)")
            dst.execute("CREATE TABLE dial_history_snapshot (schema_version TEXT,captured_at TEXT)")
            dst.execute("INSERT INTO dial_history_snapshot VALUES (?,?)", (VERSION, captured))
            summary = status(src)
        db_file = staging / "history.sqlite"
        os.chmod(db_file, 0o600)
        manifest = {**discovery(), "snapshot_captured_at": captured, "database": "history.sqlite", "sha256": hashlib.sha256(db_file.read_bytes()).hexdigest(), "coverage": summary["coverage"]}
        (staging / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        shutil.copyfile(__file__, staging / "dial_history.py")
        readme = Path(__file__).with_name("README.md")
        if readme.exists():
            shutil.copyfile(readme, staging / "README.md")
        for file in staging.iterdir():
            os.chmod(file, 0o600)
        staging.rename(output)
        return {"schema_version": VERSION, "directory": str(output), "records": summary["coverage"]["records"], "snapshot_captured_at": captured}
    except BaseException:
        shutil.rmtree(staging)
        raise


def openapi():
    query_parameters = [{"name": k, "in": "query", "schema": {"type": "string"}} for k in ["since", "until", "source", "min_ms", "limit", "cursor"]]
    paths = {}
    for route in discovery()["routes"].values():
        if route == "/openapi.json":
            continue
        params = [] if route.endswith("status") else query_parameters if route.endswith("plays") else query_parameters[:-1]
        paths[route] = {"get": {"parameters": params, "responses": {"200": {"description": "Versioned JSON envelope with freshness and data", "content": {"application/json": {"schema": {"type": "object"}}}}, "400": {"description": "Invalid filters"}, "401": {"description": "Read token required"}, "503": {"description": "Archive unavailable"}}}}
    return {"openapi": "3.0.3", "info": {"title": "Dial History", "version": VERSION, "description": NOTE}, "security": [{"readToken": []}],
            "components": {"securitySchemes": {"readToken": {"type": "http", "scheme": "bearer"}}}, "paths": paths}


def make_handler(path, token, loader=None):
    class Handler(BaseHTTPRequestHandler):
        server_version = "DialHistory/1"

        def setup(self):
            super().setup()
            self.connection.settimeout(10)

        def log_message(self, *_):
            pass  # Do not log listening filters, headers, or credentials.

        def respond(self, code, payload):
            data = json.dumps(payload, ensure_ascii=False).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if len(self.path) > 4096:
                return self.respond(414, {"error": "URL too long"})
            parsed = urlsplit(self.path)
            if parsed.path == "/.well-known/dial-history" and not parsed.query:
                return self.respond(200, discovery())
            if len(token) < 32:
                return self.respond(503, {"error": "Read service is not configured"})
            provided = self.headers.get("Authorization", "")
            if not hmac.compare_digest(provided.encode(), ("Bearer " + token).encode()):
                return self.respond(401, {"error": "Dial History read token required"})
            try:
                if parsed.path == "/openapi.json" and not parsed.query:
                    return self.respond(200, openapi())
                if parsed.path not in discovery()["routes"].values():
                    return self.respond(404, {"error": "Unknown route"})
                pairs = parse_qs(parsed.query, keep_blank_values=True, max_num_fields=8)
                if any(len(v) != 1 for v in pairs.values()):
                    raise ValueError("Duplicate query parameters are not supported.")
                params = {k: v[0] for k, v in pairs.items()}
                payload = loader(parsed.path, params) if loader else query(path, parsed.path, params)
                self.respond(200, payload)
            except ValueError as exc:
                self.respond(400, {"error": str(exc)})
            except (sqlite3.Error, OSError):
                self.respond(503, {"error": "Archive unavailable; retry or check Dial History status locally"})
            except LookupError:
                self.respond(404, {"error": "Unknown route"})

        def reject_write(self):
            self.respond(405, {"error": "Read-only service; use GET"})

        do_POST = do_PUT = do_PATCH = do_DELETE = do_OPTIONS = reject_write

    return Handler


def make_server(path, token, port):
    if len(token) < 32:
        raise ValueError("Read token must have at least 32 characters.")
    Handler = make_handler(path, token)

    class Server(ThreadingHTTPServer):
        daemon_threads = True
        # SSH/Tailscale/HTTPS proxy provides remote transport; never listen publicly.
        def __init__(self):
            self.slots = threading.BoundedSemaphore(8)
            super().__init__(("127.0.0.1", port), Handler)

        def process_request(self, request, client_address):
            if not self.slots.acquire(blocking=False):
                self.shutdown_request(request)
                return
            try:
                super().process_request(request, client_address)
            except BaseException:
                self.slots.release()
                raise

        def process_request_thread(self, request, client_address):
            try:
                super().process_request_thread(request, client_address)
            finally:
                self.slots.release()

    return Server()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=DB, help="Read live Dial or a portable snapshot (always read-only)")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("discover")
    sub.add_parser("status")
    sub.add_parser("schema")
    for name in ("plays", "top"):
        cmd = sub.add_parser(name)
        for flag in ("since", "until", "source", "min-ms", "limit"):
            cmd.add_argument("--" + flag)
        if name == "plays":
            cmd.add_argument("--cursor")
        else:
            cmd.add_argument("kind", choices=["artists", "tracks"])
    export = sub.add_parser("export")
    export.add_argument("output", type=Path, help="New destination directory")
    serve = sub.add_parser("serve")
    serve.add_argument("--port", type=int, default=PORT)
    serve.add_argument("--token-file", type=Path, default=TOKEN)
    args = parser.parse_args()
    try:
        if args.command == "discover":
            data = discovery()
        elif args.command == "schema":
            data = openapi()
        elif args.command == "export":
            data = export_snapshot(args.db, args.output)
        elif args.command == "serve":
            token = args.token_file.read_text().strip()
            with make_server(args.db, token, args.port) as server:
                server.serve_forever()
            return
        else:
            route = "/v1/" + args.command + ("/" + args.kind if args.command == "top" else "")
            params = {k: v for k, v in vars(args).items() if k in {"since", "until", "source", "min_ms", "limit", "cursor"} and v is not None}
            data = query(args.db, route, params)
        print(json.dumps(data, indent=2, ensure_ascii=False))
    except (ValueError, sqlite3.Error, OSError) as exc:
        print(json.dumps({"error": str(exc)}), file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
