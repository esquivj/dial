"""Load a private, immutable cloud snapshot and reuse the local query contract."""
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import tempfile
import threading
import time

import dial_history as dial

MANIFEST = "dial-history/current.json"
PREFIX = "dial-history/snapshots/"
MAX_PACKED = 64 * 1024 * 1024
MAX_DATABASE = 512 * 1024 * 1024


class CloudUnavailable(OSError):
    pass


def validate_manifest(value):
    if not isinstance(value, dict) or value.get("format") != "dial-history-snapshot-v1":
        raise CloudUnavailable("Unsupported cloud snapshot")
    for key in ("sha256", "compressed_sha256", "content_fingerprint"):
        if not re.fullmatch(r"[0-9a-f]{64}", str(value.get(key, ""))):
            raise CloudUnavailable("Invalid cloud snapshot digest")
    if value.get("pathname") != PREFIX + value["compressed_sha256"] + ".sqlite.gz":
        raise CloudUnavailable("Invalid snapshot pathname")
    for key, maximum in (("bytes", MAX_DATABASE), ("compressed_bytes", MAX_PACKED)):
        if type(value.get(key)) is not int or not 0 < value[key] <= maximum:
            raise CloudUnavailable("Invalid snapshot size")
    if type(value.get("records")) is not int or value["records"] < 0:
        raise CloudUnavailable("Invalid snapshot count")
    try:
        dial.timestamp(value["captured_at"])
    except (ValueError, TypeError, KeyError, AttributeError) as exc:
        raise CloudUnavailable("Invalid capture time") from exc
    return value


def blob_bytes(client, path, maximum, fresh=False):
    try:
        result = client.get(path, access="private", use_cache=not fresh, timeout=30)
        if result is None or result.status_code != 200:
            raise CloudUnavailable("Snapshot is not available")
        content = result.content  # Pinned vercel 0.11.6 returns bytes for sync get().
        if len(content) > maximum:
            raise CloudUnavailable("Snapshot exceeds size limit")
        return content
    except CloudUnavailable:
        raise
    except Exception as exc:
        # SDK exceptions may include internal URLs or credentials; never expose them.
        raise CloudUnavailable("Cloud storage request failed") from exc


class SnapshotReader:
    def __init__(self, client_factory, cache_dir=None, refresh_seconds=60):
        self.client_factory = client_factory
        self.cache = Path(cache_dir or tempfile.mkdtemp(prefix="dial-cloud-"))
        self.cache.mkdir(parents=True, exist_ok=True)
        self.cache.chmod(0o700)
        self.refresh_seconds = refresh_seconds
        self.lock = threading.RLock()
        self.checked = 0
        self.checked_at = None
        self.path = None
        self.manifest = None
        self.refresh_failed = False

    def refresh(self):
        if self.path and time.monotonic() - self.checked < self.refresh_seconds:
            return
        self.checked = time.monotonic()
        try:
            with self.client_factory() as client:
                manifest = validate_manifest(json.loads(blob_bytes(client, MANIFEST, 16384, fresh=True)))
                if not self.manifest or manifest["sha256"] != self.manifest["sha256"]:
                    packed = blob_bytes(client, manifest["pathname"], MAX_PACKED)
                    if len(packed) != manifest["compressed_bytes"] or hashlib.sha256(packed).hexdigest() != manifest["compressed_sha256"]:
                        raise CloudUnavailable("Compressed snapshot failed verification")
                    path = self.cache / (manifest["sha256"] + ".sqlite")
                    staging = path.with_suffix(".partial")
                    try:
                        total, digest = 0, hashlib.sha256()
                        with gzip.GzipFile(fileobj=io.BytesIO(packed)) as source, staging.open("wb") as target:
                            staging.chmod(0o600)
                            while chunk := source.read(1024 * 1024):
                                total += len(chunk)
                                if total > manifest["bytes"]:
                                    raise CloudUnavailable("Expanded snapshot exceeds size limit")
                                digest.update(chunk)
                                target.write(chunk)
                        if total != manifest["bytes"] or digest.hexdigest() != manifest["sha256"]:
                            raise CloudUnavailable("Snapshot failed verification")
                        with dial.connect(staging) as db:
                            if dial.tables(db) != set(dial.TABLES) | {"dial_history_snapshot"}:
                                raise CloudUnavailable("Unexpected snapshot tables")
                            if db.execute("PRAGMA quick_check").fetchone()[0] != "ok":
                                raise CloudUnavailable("Invalid snapshot database")
                            capture = db.execute("SELECT captured_at FROM dial_history_snapshot").fetchone()[0]
                            count = db.execute("SELECT COUNT(*) FROM plays").fetchone()[0]
                            if capture != manifest["captured_at"] or count != manifest["records"]:
                                raise CloudUnavailable("Snapshot metadata does not match")
                        staging.replace(path)
                    finally:
                        staging.unlink(missing_ok=True)
                    old = self.path
                    self.path = path
                    if old and old != path:
                        old.unlink(missing_ok=True)
                self.manifest = manifest
                self.checked_at = dial.now()
                self.refresh_failed = False
        except Exception as exc:
            self.refresh_failed = True
            if self.path is None:
                raise CloudUnavailable("No verified snapshot is available") from exc

    def query(self, route, params):
        # Hold through the read so a simultaneous refresh cannot delete its file.
        with self.lock:
            self.refresh()
            result = dial.query(self.path, route, params)
            result["cloud"] = {"mode": "private_snapshot", "snapshot_captured_at": self.manifest["captured_at"],
                               "last_storage_check_at": self.checked_at, "refresh_failed": self.refresh_failed,
                               "freshness_note": "Reads the last uploaded snapshot; check capture time and archive coverage."}
            return result
