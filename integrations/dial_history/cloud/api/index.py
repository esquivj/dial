"""Authenticated cloud read API. Deployed package contains code only."""
import os
from pathlib import Path
import sys
from urllib.parse import parse_qs, urlencode, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
import dial_history as dial
from cloud_store import SnapshotReader


def client():
    from vercel.blob import BlobClient
    return BlobClient()


reader = SnapshotReader(client)
HistoryHandler = dial.make_handler(None, os.environ.get("DIAL_HISTORY_READ_TOKEN", ""), loader=reader.query)


# Vercel detects a top-level handler class during static Python analysis.
class handler(HistoryHandler):
    def do_GET(self):
        # Vercel forwards the rewritten URL to BaseHTTPRequestHandler. Carry
        # the original route explicitly; shared auth still applies to every route.
        if len(self.path) > 4096:
            return self.respond(414, {"error": "URL too long"})
        try:
            parts = urlsplit(self.path)
            params = parse_qs(parts.query, keep_blank_values=True, max_num_fields=9)
            original = params.pop("__dial_path", None)
            if original is not None:
                if len(original) != 1:
                    raise ValueError()
                # Vercel also forwards the catch-all capture as a query field.
                # Remove it only when it agrees with the explicit original route.
                if params.get("path") == original:
                    params.pop("path")
                self.path = "/" + original[0].lstrip("/")
                if params:
                    self.path += "?" + urlencode(params, doseq=True)
        except ValueError:
            return self.respond(400, {"error": "Invalid request route"})
        return super().do_GET()
