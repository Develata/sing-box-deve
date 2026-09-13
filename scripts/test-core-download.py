#!/usr/bin/env python3
"""Real curl transfers: interrupted ranges, bounded retries and verified cache."""
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest

SCRIPT = Path(__file__).resolve().with_name("download-current-cores.sh")
PAYLOAD = b"verified stable core fixture\n" * 64
DIGEST = hashlib.sha256(PAYLOAD).hexdigest()


class DownloadTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="core download 中文 ")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.mode = "success"
        self.ranges = []
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def do_GET(self):
                requested_range = self.headers.get("Range")
                fixture.ranges.append(requested_range)
                if fixture.mode == "forbidden":
                    self.send_error(403)
                    return
                start = int(requested_range[6:-1]) if requested_range else 0
                body = PAYLOAD[start:]
                self.send_response(206 if requested_range else 200)
                self.send_header("Content-Length", str(len(body)))
                if requested_range:
                    self.send_header("Content-Range", f"bytes {start}-{len(PAYLOAD)-1}/{len(PAYLOAD)}")
                self.end_headers()
                if fixture.mode == "always-interrupted" or (fixture.mode == "interrupted" and not requested_range):
                    body = body[:len(body) // 2]
                self.wfile.write(body)
                self.close_connection = True

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(thread.join, 2)
        self.addCleanup(self.server.shutdown)
        self.target = self.root / "download.tar.gz"
        self.cache = self.root / "cache" / "current.tar.gz"

    def download(self, digest=DIGEST):
        return subprocess.run([
            "bash", "-c", 'source "$1"; download_current_core_asset "$2" "$3" "$4" "$5"',
            "core-download-test", str(SCRIPT), f"http://127.0.0.1:{self.server.server_port}/core",
            str(self.target), digest, str(self.cache),
        ], capture_output=True, text=True, timeout=15, check=False)

    def test_interrupted_transfer_resumes_and_publishes_verified_cache(self):
        self.mode = "interrupted"
        result = self.download()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.ranges, [None, f"bytes={len(PAYLOAD) // 2}-"])
        self.assertEqual(self.target.read_bytes(), PAYLOAD)
        self.assertEqual(self.cache.read_bytes(), PAYLOAD)

    def test_retries_stop_after_three_incomplete_transfers(self):
        self.mode = "always-interrupted"
        self.assertNotEqual(self.download().returncode, 0)
        self.assertEqual(len(self.ranges), 3)
        self.assertFalse(self.cache.exists())

    def test_forbidden_response_is_not_retried(self):
        self.mode = "forbidden"
        self.assertEqual(self.download().returncode, 22)
        self.assertEqual(self.ranges, [None])

    def test_existing_target_does_not_resume_a_previous_asset(self):
        self.target.write_bytes(b"old incomplete archive")
        result = self.download()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.ranges, [None])
        self.assertEqual(self.target.read_bytes(), PAYLOAD)

    def test_matching_cache_needs_no_asset_request(self):
        self.cache.parent.mkdir()
        self.cache.write_bytes(PAYLOAD)
        self.assertEqual(self.download().returncode, 0)
        self.assertEqual(self.ranges, [])
        self.assertEqual(self.target.read_bytes(), PAYLOAD)

    def test_stale_or_corrupt_cache_is_replaced_after_verification(self):
        self.cache.parent.mkdir()
        self.cache.write_bytes(b"old or corrupt core")
        self.assertEqual(self.download().returncode, 0)
        self.assertEqual(self.ranges, [None])
        self.assertEqual(self.cache.read_bytes(), PAYLOAD)

    def test_wrong_digest_does_not_publish_cache(self):
        self.assertNotEqual(self.download("0" * 64).returncode, 0)
        self.assertEqual(self.ranges, [None])
        self.assertFalse(self.cache.exists())


if __name__ == "__main__":
    unittest.main()
