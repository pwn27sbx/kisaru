"""Download ids never point outside the downloads folder.

`_dl_worker` created and wrote `DOWNLOADS_DIR/<mangaId>/<chapterId>` straight
from the request, and `dl_pages` listed the same path, so an id with `../` or
an absolute one wrote and listed outside Downloads (audit 2026-11-06, C2).

Run from the repo root:
    python3 -m unittest tests.test_manga_download_paths
"""

import json
import os
import shutil
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

try:
    import manga_server
    HAVE_SERVER = True
except Exception:  # noqa: BLE001 — curl_cffi/requests not installed
    HAVE_SERVER = False


@unittest.skipUnless(HAVE_SERVER, "manga_server needs curl_cffi/requests")
class DownloadPathTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.original_dir = manga_server.DOWNLOADS_DIR
        self.original_pages = manga_server._download_pages
        manga_server.DOWNLOADS_DIR = os.path.join(self.tmp, "downloads")
        os.makedirs(os.path.join(manga_server.DOWNLOADS_DIR, "series1"))
        self.outside = os.path.join(self.tmp, "outside")

    def tearDown(self):
        manga_server.DOWNLOADS_DIR = self.original_dir
        manga_server._download_pages = self.original_pages
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_the_worker_cannot_write_outside_downloads(self):
        manga_server._download_pages = lambda cid: []
        manga_server._dl_worker("series1", "../../outside", "1", "t", "m", "")
        self.assertFalse(os.path.exists(self.outside))
        self.assertEqual(manga_server._dl_jobs["../../outside"]["status"], "error")

    def test_the_worker_cannot_escape_through_the_manga_id(self):
        manga_server._download_pages = lambda cid: []
        manga_server._dl_worker("..", "ch1", "1", "t", "m", "")
        self.assertFalse(os.path.exists(os.path.join(self.tmp, "ch1")))

    def test_pages_cannot_list_outside_downloads(self):
        os.makedirs(self.outside)
        with open(os.path.join(self.outside, "001.jpg"), "wb") as fh:
            fh.write(b"\xff\xd8\xff")
        self.assertEqual(manga_server.dl_pages("../../outside"), [])

    def test_start_refuses_an_id_that_leaves_downloads(self):
        result = manga_server.dl_start("series1", "../../outside", "1", "t", "m", "")
        self.assertFalse(result["ok"])

    def test_a_normal_chapter_still_downloads(self):
        pages = [{"page": 1, "img": "file://" + os.path.join(self.tmp, "001.jpg")}]
        with open(os.path.join(self.tmp, "001.jpg"), "wb") as fh:
            fh.write(b"\xff\xd8\xff")
        manga_server._download_pages = lambda cid: pages
        result = manga_server.dl_start(
            "mangadex:abc", "mangadex:abc-ch1", "1", "t", "m", "")
        self.assertTrue(result["ok"], result)
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            status = manga_server.dl_progress("mangadex:abc-ch1")["status"]
            if status in ("done", "error"):
                break
            time.sleep(0.01)
        self.assertEqual(status, "done", manga_server.dl_progress("mangadex:abc-ch1"))
        chapter = os.path.join(manga_server.DOWNLOADS_DIR, "mangadex:abc",
                               "mangadex:abc-ch1")
        self.assertTrue(os.path.isdir(chapter))
        meta = json.load(open(os.path.join(chapter, "meta.json")))
        self.assertEqual(meta["chapterNum"], "1")


if __name__ == "__main__":
    unittest.main()
