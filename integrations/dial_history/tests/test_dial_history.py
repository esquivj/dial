import contextlib
import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
import threading
import unittest
import urllib.error
import urllib.request

SPEC = importlib.util.spec_from_file_location("dial_history", Path(__file__).parents[1] / "dial_history.py")
dial = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(dial)


class HistoryTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.db = self.root / "source.sqlite"
        with contextlib.closing(sqlite3.connect(self.db)) as db, db:
            for name, schema in dial.TABLES.items():
                db.execute(f"CREATE TABLE {name} ({schema})")
            db.execute("CREATE TABLE private_credentials(secret TEXT)")
            db.execute("INSERT INTO private_credentials VALUES ('DO_NOT_EXPORT')")
            db.executemany("INSERT INTO tracks VALUES (?,?,?,?,?,?)", [
                ('spotify:track:a', 'Song A', 'Album', None, 180000, json.dumps([{'name': 'Artist', 'uri': 'artist:Artist'}])),
                ('spotify:track:b', 'Song B', 'Album', None, 220000, 'invalid'),
            ])
            db.execute("INSERT INTO artist_identity_aliases VALUES (?,?,?,?,?,?,?,?,?)", ('artist:Artist', 'Artist', 'artist', 'spotify:artist:canonical', 'Artist', .9, 'name_match', 1, 1))
            db.executemany("INSERT INTO plays VALUES (?,?,?,?,?)", [
                (1, dial.timestamp('2026-06-01'), 'spotify:track:a', 10000, 'import'),
                (2, dial.timestamp('2026-10-01'), 'spotify:track:a', 32000, 'live'),
                (3, dial.timestamp('2026-10-01'), 'spotify:track:b', 220000, 'recent'),
                (4, dial.timestamp('2026-10-02'), 'spotify:track:missing', 150000, 'import'),
            ])

    def tearDown(self):
        self.temp.cleanup()

    def test_open_read_only_and_missing_file_not_created(self):
        with dial.connect(self.db) as db:
            with self.assertRaises(sqlite3.OperationalError):
                db.execute("DELETE FROM plays")
        missing = self.root / 'missing.sqlite'
        with self.assertRaises(sqlite3.OperationalError):
            dial.query(missing, '/v1/status')
        self.assertFalse(missing.exists())

    def test_status_reports_unknown_months(self):
        result = dial.query(self.db, '/v1/status')
        self.assertEqual(result['coverage']['records'], 4)
        self.assertEqual(result['coverage']['months_without_records_between_first_and_last'], ['2026-07', '2026-08', '2026-09'])
        self.assertFalse(result['coverage']['complete'])

    def test_pagination_handles_equal_timestamps_and_concurrent_backfill(self):
        first = dial.query(self.db, '/v1/plays', {'limit': '2'})
        self.assertEqual([x['id'] for x in first['items']], [4, 3])
        with contextlib.closing(sqlite3.connect(self.db)) as db, db:
            db.execute("INSERT INTO plays VALUES (5,?,'spotify:track:a',50000,'import')", (dial.timestamp('2026-08-01'),))
        second = dial.query(self.db, '/v1/plays', {'limit': '2', 'cursor': first['next_cursor']})
        self.assertEqual([x['id'] for x in second['items']], [2, 1])
        self.assertIsNone(second['next_cursor'])
        with self.assertRaises(ValueError):
            dial.query(self.db, '/v1/plays', {'source': 'recent', 'cursor': first['next_cursor']})

    def test_provenance_metadata_and_aliases(self):
        result = dial.query(self.db, '/v1/plays')
        rows = {r['id']: r for r in result['items']}
        self.assertEqual(rows[1]['duration_basis'], 'spotify_export_measured')
        self.assertEqual(rows[2]['duration_basis'], 'observed_progress_at_count')
        self.assertEqual(rows[3]['duration_basis'], 'track_duration_estimate')
        self.assertEqual(rows[3]['track']['artist_metadata'], 'invalid')
        self.assertIsNone(rows[4]['track']['name'])
        self.assertEqual(rows[1]['track']['artists'][0]['uri'], 'spotify:artist:canonical')
        self.assertEqual(rows[1]['track']['artists'][0]['original_uri'], 'artist:Artist')

    def test_range_threshold_and_rank_semantics(self):
        result = dial.query(self.db, '/v1/top/tracks', {'since': '2026-06-01', 'until': '2026-10-02', 'min_ms': '30000'})
        self.assertEqual(sum(r['records'] for r in result['items']), 2)
        self.assertEqual(result['metric'], 'saved_record_count')
        artists = dial.query(self.db, '/v1/top/artists')
        self.assertEqual(sum(r['records'] for r in artists['items']), 4)
        fractional = dial.query(self.db, '/v1/plays', {'since': '2026-10-01T00:00:00.500Z'})
        self.assertEqual([r['id'] for r in fractional['items']], [4])
        fractional = dial.query(self.db, '/v1/plays', {'until': '2026-10-01T00:00:00.500Z'})
        self.assertEqual([r['id'] for r in fractional['items']], [3, 2, 1])
        fractional = dial.query(self.db, '/v1/plays', {'since': '2026-10-01T00:00:00.100Z', 'until': '2026-10-01T00:00:00.900Z'})
        self.assertEqual(fractional['items'], [])

    def test_invalid_queries(self):
        for params in [{'source': "import' OR 1=1 --"}, {'limit': '1001'}, {'min_ms': '-1'}, {'cursor': 'broken'}, {'since': '2026-10-10T10:00:00'}, {'since': '2026-10-02', 'until': '2026-10-01'}, {'sql': 'DELETE FROM plays'}]:
            with self.subTest(params=params), self.assertRaises(ValueError):
                dial.query(self.db, '/v1/plays', params)

    def test_export_uses_allowlist_including_uncheckpointed_wal(self):
        source = sqlite3.connect(self.db)
        source.execute('PRAGMA journal_mode=WAL')
        source.execute('PRAGMA wal_autocheckpoint=0')
        source.execute("INSERT INTO plays VALUES (5,?,'spotify:track:a',100000,'import')", (dial.timestamp('2026-10-03'),))
        source.commit()
        output = self.root / 'export'
        try:
            result = dial.export_snapshot(self.db, output)
            self.assertEqual(result['records'], 5)
            with dial.connect(output / 'history.sqlite') as db:
                self.assertNotIn('private_credentials', dial.tables(db))
                self.assertEqual(db.execute('SELECT COUNT(*) FROM plays').fetchone()[0], 5)
            for file in output.iterdir():
                self.assertNotIn(b'DO_NOT_EXPORT', file.read_bytes())
            read = dial.query(output / 'history.sqlite', '/v1/status')
            self.assertEqual(read['freshness']['source_kind'], 'snapshot')
            self.assertIn('snapshot_captured_at', read['freshness'])
            with self.assertRaises(ValueError):
                dial.export_snapshot(self.db, output)
        finally:
            source.close()

    def test_http_auth_read_only_and_no_filesystem_routes(self):
        token = 'a' * 48
        server = dial.make_server(self.db, token, 0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = 'http://127.0.0.1:' + str(server.server_port)
        def request(path, auth=None, method='GET'):
            headers = {'Authorization': 'Bearer ' + auth} if auth else {}
            try:
                with urllib.request.urlopen(urllib.request.Request(base + path, headers=headers, method=method), timeout=3) as response:
                    return response.status, json.load(response)
            except urllib.error.HTTPError as exc:
                with exc:
                    return exc.code, json.load(exc)
        try:
            self.assertEqual(request('/.well-known/dial-history')[0], 200)
            self.assertEqual(request('/v1/plays')[0], 401)
            self.assertEqual(request('/v1/plays', 'wrong')[0], 401)
            self.assertEqual(request('/v1/plays', token)[0], 200)
            self.assertEqual(request('/v1/status', token)[1]['coverage']['records'], 4)
            self.assertEqual(request('/v1/plays?limit=0', token)[0], 400)
            self.assertEqual(request('/v1/plays?limit=1&limit=2', token)[0], 400)
            self.assertEqual(request('/../../spotify-token.json', token)[0], 404)
            self.assertEqual(request('/v1/plays', token, 'POST')[0], 405)
            self.assertEqual(request('/openapi.json', token)[1]['openapi'], '3.0.3')
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)


if __name__ == '__main__':
    unittest.main()
