"""The manga backend answers only this machine's panel.

The downloads folder is the user's data: a page open in any browser could POST
`/dl/delete` with `../` and remove a directory outside Downloads (audit
2026-11-06, C1). These tests pin the local-only guard and the path validation
around it.

Run from the repo root:
    python3 -m unittest tests.test_manga_local_only
"""

import http.client
import json
import os
import shutil
import sys
import tempfile
import threading
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

try:
    import manga_server
    HAVE_SERVER = True
except Exception:  # noqa: BLE001 — curl_cffi/requests not installed
    HAVE_SERVER = False


class _LiveServer:
    """The real Handler on a loopback port, so the request guard is under test."""

    def __init__(self):
        self.server = manga_server.ThreadingHTTPServer(
            ("127.0.0.1", 0), manga_server.Handler)
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def request(self, method, path, body=None, headers=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        try:
            conn.request(method, path, body=body, headers=headers or {})
            response = conn.getresponse()
            return response.status, response.read()
        finally:
            conn.close()

    def close(self):
        self.server.shutdown()
        self.server.server_close()


@unittest.skipUnless(HAVE_SERVER, "manga_server needs curl_cffi/requests")
class RequestGuardTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.http = _LiveServer()

    @classmethod
    def tearDownClass(cls):
        cls.http.close()

    def test_a_page_cannot_delete_a_chapter(self):
        status, _ = self.http.request(
            "POST", "/dl/delete",
            body=json.dumps({"chapterId": "anything"}),
            headers={"Content-Type": "application/json",
                     "Origin": "https://evil.example"},
        )
        self.assertEqual(status, 403)

    def test_a_simple_post_without_a_json_body_is_refused(self):
        status, _ = self.http.request(
            "POST", "/dl/delete",
            body="chapterId=anything",
            headers={"Content-Type": "text/plain"},
        )
        self.assertEqual(status, 403)

    def test_a_page_cannot_read_the_backend(self):
        status, _ = self.http.request(
            "GET", "/health", headers={"Origin": "https://evil.example"})
        self.assertEqual(status, 403)

    def test_the_panel_posts_json_without_an_origin(self):
        status, _ = self.http.request(
            "POST", "/dl/delete",
            body=json.dumps({}),
            headers={"Content-Type": "application/json"},
        )
        self.assertEqual(status, 400, "the request must reach the route")

    def test_the_panel_reads_health_without_an_origin(self):
        status, _ = self.http.request("GET", "/health")
        self.assertEqual(status, 200)


@unittest.skipUnless(HAVE_SERVER, "manga_server needs curl_cffi/requests")
class DlRemoveTraversalTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.original = manga_server.DOWNLOADS_DIR
        manga_server.DOWNLOADS_DIR = os.path.join(self.tmp, "downloads")
        os.makedirs(os.path.join(manga_server.DOWNLOADS_DIR, "series1", "ch1"))
        self.outside = os.path.join(self.tmp, "outside")
        os.makedirs(self.outside)
        with open(os.path.join(self.outside, "keep.txt"), "w") as fh:
            fh.write("keep")

    def tearDown(self):
        manga_server.DOWNLOADS_DIR = self.original
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_an_absolute_id_cannot_delete_outside_downloads(self):
        result = manga_server.dl_remove(self.outside)
        self.assertFalse(result["ok"])
        self.assertTrue(os.path.exists(os.path.join(self.outside, "keep.txt")))

    def test_a_parent_escape_cannot_delete_outside_downloads(self):
        result = manga_server.dl_remove("../../outside")
        self.assertFalse(result["ok"])
        self.assertTrue(os.path.exists(os.path.join(self.outside, "keep.txt")))

    def test_a_normal_id_still_deletes_its_chapter(self):
        result = manga_server.dl_remove("ch1")
        self.assertTrue(result["ok"])
        self.assertFalse(os.path.exists(
            os.path.join(manga_server.DOWNLOADS_DIR, "series1", "ch1")))


if __name__ == "__main__":
    unittest.main()
