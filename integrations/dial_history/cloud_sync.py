#!/usr/bin/env python3
"""Publish allowed history tables to private Vercel Blob. Never reads Spotify auth."""
import argparse
import datetime as dt
import fcntl
import gzip
import hashlib
import json
import os
import re
from pathlib import Path
import sys
import tempfile

import dial_history as dial
from cloud_store import MANIFEST, PREFIX, validate_manifest

CONFIG = dial.RUNTIME / "cloud-config.json"
STATE = dial.RUNTIME / "cloud-sync-state.json"


def atomic_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, name = tempfile.mkstemp(prefix=".dial-state-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as out:
            json.dump(data, out, indent=2)
            out.write("\n")
        Path(name).replace(path)
    finally:
        Path(name).unlink(missing_ok=True)


def fingerprint(path):
    digest = hashlib.sha256()
    with dial.connect(path) as db:
        # Excludes only the capture marker. Backfills, metadata repairs, deletions,
        # and sync-state changes all invalidate this fingerprint.
        for table in dial.TABLES:
            digest.update(table.encode())
            for row in db.execute(f"SELECT * FROM {table} ORDER BY 1"):
                digest.update(json.dumps(list(row), separators=(",", ":"), ensure_ascii=False).encode())
                digest.update(b"\n")
    return digest.hexdigest()


def prepare(db, directory):
    directory = Path(directory)
    exported = dial.export_snapshot(db, directory / "export")
    source = directory / "export/history.sqlite"
    packed = directory / "history.sqlite.gz"
    with source.open("rb") as reader, packed.open("wb") as raw, gzip.GzipFile(fileobj=raw, mode="wb", filename="", mtime=0, compresslevel=6) as writer:
        while chunk := reader.read(1024 * 1024):
            writer.write(chunk)
    packed.chmod(0o600)
    compressed_digest = hashlib.sha256(packed.read_bytes()).hexdigest()
    manifest = validate_manifest({"format": "dial-history-snapshot-v1", "schema_version": dial.VERSION,
                "captured_at": exported["snapshot_captured_at"], "records": exported["records"],
                "sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "bytes": source.stat().st_size,
                "compressed_sha256": compressed_digest, "compressed_bytes": packed.stat().st_size,
                "pathname": PREFIX + compressed_digest + ".sqlite.gz", "content_fingerprint": fingerprint(source)})
    atomic_json(directory / "cloud-manifest.json", manifest)
    return manifest, packed


def publish(client, manifest, packed, previous=None):
    if previous and previous.get("content_fingerprint") == manifest["content_fingerprint"]:
        return False
    # Immutable file first, pointer second. A failed upload never replaces the
    # last good pointer. Only this dedicated publisher writes this store prefix.
    client.put(manifest["pathname"], packed.read_bytes(), access="private", content_type="application/gzip",
               add_random_suffix=False, overwrite=True, cache_control_max_age=60)
    client.put(MANIFEST, json.dumps(manifest).encode(), access="private", content_type="application/json",
               add_random_suffix=False, overwrite=True, cache_control_max_age=60)
    return True


def prune(client, current, previous=None):
    """Keep the current/previous snapshot and a two-hour in-flight grace period."""
    keep = {current["pathname"], (previous or {}).get("pathname")}
    cutoff = dt.datetime.now(dt.timezone.utc) - dt.timedelta(hours=2)
    for blob in client.iter_objects(prefix=PREFIX):
        if (blob.pathname not in keep and re.fullmatch(re.escape(PREFIX) + r"[0-9a-f]{64}\.sqlite\.gz", blob.pathname)
                and blob.uploaded_at < cutoff):
            client.delete(blob.pathname)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=dial.DB)
    parser.add_argument("--config", type=Path, default=CONFIG)
    parser.add_argument("--state", type=Path, default=STATE)
    parser.add_argument("--prepare", type=Path, help="Prepare locally in a new directory; no upload")
    args = parser.parse_args()
    if args.prepare:
        args.prepare.mkdir(mode=0o700, parents=True, exist_ok=False)
        manifest, _ = prepare(args.db, args.prepare)
        print(json.dumps({"prepared": str(args.prepare), "records": manifest["records"], "compressed_bytes": manifest["compressed_bytes"]}))
        return
    args.state.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    lock_fd = os.open(str(args.state) + ".lock", os.O_WRONLY | os.O_CREAT, 0o600)
    with os.fdopen(lock_fd, "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        previous = json.loads(args.state.read_text()) if args.state.exists() else {}
        try:
            if args.config.stat().st_mode & 0o077:
                raise ValueError("Cloud config must have owner-only permissions")
            config = json.loads(args.config.read_text())
            token = config["blob_read_write_token"]
            if not token.startswith("vercel_blob_rw_"):
                raise ValueError("A dedicated Blob read/write token is required")
            from vercel.blob import BlobClient
            with tempfile.TemporaryDirectory(prefix="dial-cloud-sync-") as folder:
                manifest, packed = prepare(args.db, folder)
                with BlobClient(token=token) as client:
                    changed = publish(client, manifest, packed, previous.get("published"))
                    published = manifest if changed else previous["published"]
                    prior_snapshot = previous.get("published") if changed else previous.get("previous_published")
                    cleanup_failed = False
                    try:
                        prune(client, published, prior_snapshot)
                    except Exception:
                        cleanup_failed = True
                state = {"status": "synced" if changed else "unchanged", "last_attempt_at": dial.now(),
                         "last_success_at": dial.now(), "published": published, "previous_published": prior_snapshot,
                         "cleanup_failed": cleanup_failed}
                atomic_json(args.state, state)
                print(json.dumps({"status": state["status"], "records": published["records"], "captured_at": published["captured_at"]}))
        except Exception as exc:
            atomic_json(args.state, {**previous, "status": "error", "last_attempt_at": dial.now(), "error_type": type(exc).__name__})
            print(json.dumps({"status": "error", "error_type": type(exc).__name__, "hint": "Check private cloud config, network, and Blob access; previous snapshot is retained."}), file=sys.stderr)
            raise SystemExit(1)


if __name__ == "__main__":
    main()
