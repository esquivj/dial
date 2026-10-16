import contextlib
import datetime as dt
import importlib.util
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import urllib.request
import urllib.error

sys.path.insert(0, str(Path(__file__).parents[1]))
import dial_history as dial
from cloud_store import SnapshotReader, CloudUnavailable, MANIFEST, PREFIX
from cloud_sync import prepare, publish, prune


class FakeBlob:
    def __init__(self):
        self.objects = {}
        self.calls = []
        self.fail_put = None
        self.fail_get = False

    def __enter__(self):
        return self

    def __exit__(self, *_):
        pass

    def get(self, path, **options):
        assert options['access'] == 'private'
        self.calls.append(('get', path))
        if self.fail_get:
            raise OSError('simulated storage failure')
        return SimpleNamespace(content=self.objects[path], status_code=200)

    def put(self, path, content, **options):
        assert options['access'] == 'private'
        self.calls.append(('put', path))
        if path == self.fail_put:
            raise OSError('interrupted upload')
        self.objects[path] = content


class CloudTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.db = self.root / 'source.sqlite'
        with contextlib.closing(sqlite3.connect(self.db)) as db, db:
            for table, schema in dial.TABLES.items():
                db.execute(f'CREATE TABLE {table} ({schema})')
            db.execute("INSERT INTO tracks VALUES ('spotify:track:a','A','Album',NULL,180000,'[]')")
            db.execute("INSERT INTO plays VALUES (1,1790809200,'spotify:track:a',33000,'live')")
            db.execute('CREATE TABLE credentials(secret TEXT)')
            db.execute("INSERT INTO credentials VALUES ('NEVER_LEAVE_MAC')")
        self.blob = FakeBlob()

    def tearDown(self):
        self.temp.cleanup()

    def snapshot(self, name='build'):
        directory = self.root / name
        directory.mkdir()
        return prepare(self.db, directory)

    def test_cloud_roundtrip_matches_local_and_carries_capture_time(self):
        manifest, packed = self.snapshot()
        self.assertTrue(publish(self.blob, manifest, packed))
        reader = SnapshotReader(lambda: self.blob, self.root / 'cache')
        cloud = reader.query('/v1/plays', {})
        local = dial.query(self.db, '/v1/plays')
        self.assertEqual(cloud['items'], local['items'])
        self.assertEqual(cloud['freshness']['source_kind'], 'snapshot')
        self.assertEqual(cloud['cloud']['snapshot_captured_at'], manifest['captured_at'])
        self.assertNotIn(b'NEVER_LEAVE_MAC', reader.path.read_bytes())
        with dial.connect(reader.path) as db:
            self.assertNotIn('credentials', dial.tables(db))

    def test_publish_failure_keeps_old_pointer(self):
        manifest, packed = self.snapshot()
        self.blob.objects[MANIFEST] = b'previous-good-pointer'
        self.blob.fail_put = manifest['pathname']
        with self.assertRaises(OSError):
            publish(self.blob, manifest, packed)
        self.assertEqual(self.blob.objects[MANIFEST], b'previous-good-pointer')
        self.blob.fail_put = MANIFEST
        with self.assertRaises(OSError):
            publish(self.blob, manifest, packed)
        self.assertEqual(self.blob.objects[MANIFEST], b'previous-good-pointer')

    def test_same_content_skips_upload_but_metadata_and_deletions_sync(self):
        manifest, packed = self.snapshot()
        again, again_packed = self.snapshot('again')
        self.assertFalse(publish(self.blob, again, again_packed, manifest))
        with contextlib.closing(sqlite3.connect(self.db)) as db, db:
            db.execute("UPDATE tracks SET name='Repaired'")
        repaired, _ = self.snapshot('repaired')
        self.assertNotEqual(repaired['content_fingerprint'], manifest['content_fingerprint'])
        with contextlib.closing(sqlite3.connect(self.db)) as db, db:
            db.execute('DELETE FROM plays')
        removed, _ = self.snapshot('removed')
        self.assertNotEqual(removed['content_fingerprint'], repaired['content_fingerprint'])

    def test_corrupt_snapshot_and_external_paths_rejected(self):
        manifest, packed = self.snapshot()
        publish(self.blob, manifest, packed)
        self.blob.objects[manifest['pathname']] = b'bad'
        reader = SnapshotReader(lambda: self.blob, self.root / 'cache')
        with self.assertRaises(CloudUnavailable):
            reader.query('/v1/status', {})
        bad = {**manifest, 'pathname': 'https://example.com/secret'}
        self.blob.objects[MANIFEST] = json.dumps(bad).encode()
        self.blob.calls = []
        with self.assertRaises(CloudUnavailable):
            reader.query('/v1/status', {})
        self.assertEqual(self.blob.calls, [('get', MANIFEST)])

    def test_failed_refresh_serves_known_snapshot_with_explicit_warning(self):
        manifest, packed = self.snapshot()
        publish(self.blob, manifest, packed)
        reader = SnapshotReader(lambda: self.blob, self.root / 'cache', refresh_seconds=0)
        good = reader.query('/v1/status', {})
        self.blob.fail_get = True
        fallback = reader.query('/v1/status', {})
        self.assertTrue(fallback['cloud']['refresh_failed'])
        self.assertEqual(good['coverage'], fallback['coverage'])
        self.assertEqual(good['cloud']['last_storage_check_at'], fallback['cloud']['last_storage_check_at'])

    def test_new_generation_replaces_cache_after_verification(self):
        manifest, packed = self.snapshot()
        publish(self.blob, manifest, packed)
        reader = SnapshotReader(lambda: self.blob, self.root / 'cache', refresh_seconds=0)
        reader.query('/v1/status', {})
        old = reader.path
        with contextlib.closing(sqlite3.connect(self.db)) as db, db:
            db.execute("INSERT INTO plays VALUES (2,1790809300,'spotify:track:a',45000,'live')")
        new, new_packed = self.snapshot('new')
        publish(self.blob, new, new_packed, manifest)
        result = reader.query('/v1/status', {})
        self.assertEqual(result['coverage']['records'], 2)
        self.assertFalse(old.exists())
        self.assertEqual(len(list((self.root / 'cache').glob('*.sqlite'))), 1)

    def test_unauthenticated_cloud_requests_never_touch_storage(self):
        reader = SnapshotReader(lambda: self.blob, self.root / 'cache')
        server = ThreadingHTTPServer(('127.0.0.1', 0), dial.make_handler(None, 'a'*48, reader.query))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with self.assertRaises(urllib.error.HTTPError) as caught:
                urllib.request.urlopen('http://127.0.0.1:' + str(server.server_port) + '/v1/plays')
            caught.exception.close()
            self.assertEqual(caught.exception.code, 401)
            self.assertEqual(self.blob.calls, [])
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_prune_keeps_current_previous_recent_and_unrelated_objects(self):
        old = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=1)
        recent = dt.datetime.now(dt.timezone.utc)
        names = [PREFIX + c*64 + '.sqlite.gz' for c in 'abcd']
        objects = [SimpleNamespace(pathname=n, uploaded_at=old if i < 3 else recent) for i,n in enumerate(names)]
        objects.append(SimpleNamespace(pathname=PREFIX + 'user-note.txt', uploaded_at=old))
        deleted=[]
        self.blob.iter_objects=lambda **_: objects
        self.blob.delete=deleted.append
        prune(self.blob, {'pathname': names[0]}, {'pathname': names[1]})
        self.assertEqual(deleted,[names[2]])

    def test_vercel_rewrite_keeps_discovery_auth_and_filters(self):
        manifest, packed = self.snapshot()
        publish(self.blob, manifest, packed)
        entry = Path(__file__).parents[1] / 'cloud/api/index.py'
        spec = importlib.util.spec_from_file_location('cloud_entry', entry)
        module = importlib.util.module_from_spec(spec)
        with patch.dict('os.environ', {'DIAL_HISTORY_READ_TOKEN': 'a'*48}):
            spec.loader.exec_module(module)
        module.reader.client_factory = lambda: self.blob
        server = ThreadingHTTPServer(('127.0.0.1',0),module.handler)
        thread = threading.Thread(target=server.serve_forever,daemon=True)
        thread.start()
        base = 'http://127.0.0.1:' + str(server.server_port) + '/api/index?__dial_path='
        try:
            with urllib.request.urlopen(base+'.well-known/dial-history&path=.well-known/dial-history') as response:
                self.assertEqual(json.load(response)['schema_version'],dial.VERSION)
            with self.assertRaises(urllib.error.HTTPError) as caught:
                urllib.request.urlopen(base+'v1/plays')
            self.assertEqual(caught.exception.code,401)
            caught.exception.close()
            request=urllib.request.Request(base+'v1/plays&path=v1/plays&source=live&limit=1',headers={'Authorization':'Bearer '+'a'*48})
            with urllib.request.urlopen(request) as response:
                result=json.load(response)
            self.assertEqual(len(result['items']),1)
            self.assertEqual(result['filters']['source'],'live')
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
            import shutil
            shutil.rmtree(module.reader.cache)


if __name__ == '__main__':
    unittest.main()
