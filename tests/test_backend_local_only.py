"""The backends advertise no CORS and refuse a non-loopback Host.

`Access-Control-Allow-Origin: *` let any page read `/favorites` and
`/dl/list`, private-mode titles included, and an unvalidated `Host` let a
rebound domain reach the same routes (audit 2026-11-06, finding 3).

Run from the repo root:
    python3 -m unittest tests.test_backend_local_only
"""

import http.client
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "scripts"))

try:
    import manga_server
    HAVE_MANGA = True
except Exception:  # noqa: BLE001 — curl_cffi/requests not installed
    HAVE_MANGA = False


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def request(port, method, path, headers=None):
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    try:
        conn.request(method, path, headers=headers or {})
        response = conn.getresponse()
        return response.status, response.getheader("Access-Control-Allow-Origin")
    finally:
        conn.close()


@unittest.skipUnless(HAVE_MANGA, "manga_server needs curl_cffi/requests")
class MangaLocalOnlyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = manga_server.ThreadingHTTPServer(
            ("127.0.0.1", 0), manga_server.Handler)
        cls.port = cls.server.server_address[1]
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def test_health_does_not_advertise_cors(self):
        status, allow_origin = request(self.port, "GET", "/health")
        self.assertEqual(status, 200)
        self.assertIsNone(allow_origin)

    def test_an_error_does_not_advertise_cors(self):
        status, allow_origin = request(self.port, "GET", "/nope")
        self.assertEqual(status, 404)
        self.assertIsNone(allow_origin)

    def test_a_rebound_host_is_refused(self):
        status, _ = request(self.port, "GET", "/health",
                            {"Host": "evil.example"})
        self.assertEqual(status, 403)

    def test_the_loopback_host_still_works(self):
        status, _ = request(self.port, "GET", "/health",
                            {"Host": "localhost:%d" % self.port})
        self.assertEqual(status, 200)


class NovelLocalOnlyTest(unittest.TestCase):
    """Runs the real entry point, as Quickshell does."""

    @classmethod
    def setUpClass(cls):
        cls.port = free_port()
        cls.log = tempfile.TemporaryFile()
        cls.process = subprocess.Popen(
            [sys.executable, os.path.join("scripts", "novel_server", "main.py"),
             "--port", str(cls.port)],
            cwd=ROOT, stdout=cls.log, stderr=subprocess.STDOUT,
        )
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            if cls.process.poll() is not None:
                cls.log.seek(0)
                raise AssertionError(cls.log.read().decode("utf-8", "replace")[-1500:])
            try:
                status, _ = request(cls.port, "GET", "/health")
            except OSError:
                time.sleep(0.2)
                continue
            if status == 200:
                return
        raise AssertionError("the novel backend did not answer /health")

    @classmethod
    def tearDownClass(cls):
        cls.process.terminate()
        try:
            cls.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            cls.process.kill()
            cls.process.wait(timeout=10)
        cls.log.close()

    def test_health_does_not_advertise_cors(self):
        status, allow_origin = request(self.port, "GET", "/health")
        self.assertEqual(status, 200)
        self.assertIsNone(allow_origin)

    def test_a_rebound_host_is_refused(self):
        status, _ = request(self.port, "GET", "/health",
                            {"Host": "evil.example"})
        self.assertEqual(status, 403)

    def test_a_page_origin_is_refused(self):
        status, _ = request(self.port, "GET", "/favorites",
                            {"Origin": "https://evil.example"})
        self.assertEqual(status, 403)


if __name__ == "__main__":
    unittest.main()
