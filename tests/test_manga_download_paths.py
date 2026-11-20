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
        self.original_proxy_fetch = manga_server._proxy_fetch
        self.original_img_get = manga_server._img_get
        self.original_img_put = manga_server._img_put
        self.original_jobs = dict(manga_server._dl_jobs)
        manga_server.DOWNLOADS_DIR = os.path.join(self.tmp, "downloads")
        os.makedirs(os.path.join(manga_server.DOWNLOADS_DIR, "series1"))
        manga_server._dl_jobs.clear()
        manga_server._img_get = lambda url: None
        manga_server._img_put = lambda url, body, ctype: None
        self.outside = os.path.join(self.tmp, "outside")

    def tearDown(self):
        manga_server.DOWNLOADS_DIR = self.original_dir
        manga_server._download_pages = self.original_pages
        manga_server._proxy_fetch = self.original_proxy_fetch
        manga_server._img_get = self.original_img_get
        manga_server._img_put = self.original_img_put
        manga_server._dl_jobs.clear()
        manga_server._dl_jobs.update(self.original_jobs)
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _wait_job(self, chapter_id):
        deadline = time.monotonic() + 5
        status = ""
        while time.monotonic() < deadline:
            status = manga_server.dl_progress(chapter_id)["status"]
            if status in ("done", "error"):
                break
            time.sleep(0.01)
        return status

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
        page_url = manga_server.proxy_url("https://uploads.mangadex.org/data/hash/001.jpg")
        manga_server._download_pages = lambda cid: [{"page": 1, "img": page_url}]
        manga_server._proxy_fetch = lambda url: (b"\xff\xd8\xff\xe0" + b"x" * 16, "image/jpeg")
        result = manga_server.dl_start(
            "mangadex:abc", "mangadex:abc-ch1", "1", "t", "m", "")
        self.assertTrue(result["ok"], result)
        status = self._wait_job("mangadex:abc-ch1")
        self.assertEqual(status, "done", manga_server.dl_progress("mangadex:abc-ch1"))
        chapter = os.path.join(manga_server.DOWNLOADS_DIR, "mangadex:abc",
                               "mangadex:abc-ch1")
        self.assertTrue(os.path.isdir(chapter))
        meta = json.load(open(os.path.join(chapter, "meta.json")))
        self.assertEqual(meta["chapterNum"], "1")

    def test_all_seven_source_id_shapes_download_list_read_and_delete(self):
        jpeg = b"\xff\xd8\xff\xe0" + b"p" * 32
        manga_server._proxy_fetch = lambda url: (jpeg, "image/jpeg")
        cases = [
            ("mangadex:uuid-1", "mangadex:ch-uuid-1", "https://uploads.mangadex.org/data/h/1.jpg"),
            ("inmanga:slug/uuid-2", "inmanga:uuid-2/ch-ident-2", "https://cdn1.intomanga.com/p/1.jpg"),
            ("zonatmo:tienda-del-placer", "zonatmo:tienda-del-placer/cap-106", "https://cdn.zonatmo.to/1.jpg"),
            ("zonatmo_org:library/manga/12345/slug-a", "zonatmo_org:upload-a", "https://storage.zonatmo.org/1.jpg"),
            ("zonatmo_org:library/manga/67890/slug-b", "zonatmo_org:upload-b", "https://storage.zonatmo.org/2.jpg"),
            ("manhwaweb:my-manhwa", "manhwaweb:my-manhwa-1_01", "https://img1mw.xyz/1.jpg"),
            ("mangafire:hid123", "mangafire:ch456", "https://pw6.mfcdn1.xyz/1.jpg"),
            ("weebcentral:01JABC/My-Manga", "weebcentral:01JCH1", "https://temp.compsci88.com/1.jpg"),
        ]
        for mid, cid, raw_url in cases:
            manga_server._download_pages = lambda _cid, u=raw_url: [{"page": 1, "img": manga_server.proxy_url(u)}]
            res = manga_server.dl_start(mid, cid, "1", "Ch 1", f"Title {mid}", "")
            self.assertTrue(res["ok"], f"{mid} failed: {res}")
            self.assertEqual(self._wait_job(cid), "done", f"{mid} job: {manga_server.dl_progress(cid)}")

        listed = manga_server.dl_list()
        listed_ids = {s["id"] for s in listed}
        self.assertEqual(len(listed), len(cases), f"expected {len(cases)} distinct series, got {listed_ids}")
        for series in listed:
            self.assertGreater(series["sizeBytes"], 0)
            self.assertEqual(len(series["chapters"]), 1)
            ch = series["chapters"][0]
            self.assertGreater(ch["sizeBytes"], 0)
            offline = manga_server.dl_pages(ch["chapterId"])
            self.assertEqual(len(offline), 1)
            self.assertTrue(offline[0]["img"].startswith("file://"))

        # Delete every chapter and verify clean removal of series dirs
        for _mid, cid, _raw_url in cases:
            rm = manga_server.dl_remove(cid)
            self.assertTrue(rm["ok"], f"delete {cid}: {rm}")
        self.assertEqual(manga_server.dl_list(), [])

    def test_empty_page_list_fails_without_creating_chapter_dir(self):
        manga_server._download_pages = lambda cid: []
        manga_server._dl_jobs["mangadex:empty"] = {"status": "pending", "total": 0, "done": 0, "error": None}
        manga_server._dl_worker("mangadex:s1", "mangadex:empty", "1", "t", "m", "")
        self.assertEqual(manga_server.dl_progress("mangadex:empty")["status"], "error")
        self.assertEqual(manga_server.dl_pages("mangadex:empty"), [])
        self.assertFalse(os.path.exists(os.path.join(manga_server.DOWNLOADS_DIR, "mangadex:s1", "mangadex:empty")))

    def test_failed_mid_download_cleans_partial_dir_and_dl_pages_requires_meta(self):
        page1 = manga_server.proxy_url("https://uploads.mangadex.org/data/h/1.jpg")
        page2 = manga_server.proxy_url("https://uploads.mangadex.org/data/h/2.jpg")
        manga_server._download_pages = lambda cid: [{"page": 1, "img": page1}, {"page": 2, "img": page2}]
        calls = {"n": 0}

        def flaky(url):
            calls["n"] += 1
            if calls["n"] == 1:
                return b"\xff\xd8\xff\xe0" + b"a" * 16, "image/jpeg"
            raise RuntimeError("boom")

        manga_server._proxy_fetch = flaky
        manga_server._dl_jobs["mangadex:partial"] = {"status": "pending", "total": 0, "done": 0, "error": None}
        manga_server._dl_worker("mangadex:s2", "mangadex:partial", "1", "t", "m", "")
        self.assertEqual(manga_server.dl_progress("mangadex:partial")["status"], "error")
        self.assertEqual(manga_server.dl_pages("mangadex:partial"), [])
        self.assertFalse(os.path.exists(os.path.join(manga_server.DOWNLOADS_DIR, "mangadex:s2", "mangadex:partial")))

        # Even if a stray directory with images exists without meta.json, dl_pages ignores it
        stray = os.path.join(manga_server.DOWNLOADS_DIR, "series1", "orphan-ch")
        os.makedirs(stray)
        with open(os.path.join(stray, "001.jpg"), "wb") as fh:
            fh.write(b"\xff\xd8\xff")
        self.assertEqual(manga_server.dl_pages("orphan-ch"), [])

    def test_single_active_download_limit_and_already_done_on_disk(self):
        manga_server._dl_jobs["mangadex:active"] = {"status": "downloading", "total": 5, "done": 1, "error": None}
        res = manga_server.dl_start("mangadex:s3", "mangadex:other", "2", "t", "m", "")
        self.assertFalse(res["ok"])
        self.assertEqual(res.get("error"), "busy")
        manga_server._dl_jobs.clear()

        # Already downloaded on disk (even after _dl_jobs cleared on restart)
        existing = os.path.join(manga_server.DOWNLOADS_DIR, "mangadex:s3", "mangadex:done-ch")
        os.makedirs(existing)
        with open(os.path.join(existing, "meta.json"), "w") as fh:
            json.dump({"chapterId": "mangadex:done-ch", "chapterNum": "1"}, fh)
        res2 = manga_server.dl_start("mangadex:s3", "mangadex:done-ch", "1", "t", "m", "")
        self.assertFalse(res2["ok"])
        self.assertEqual(res2.get("message"), "done")

    def test_cover_download_refuses_loopback_and_disallowed_hosts(self):
        page_url = manga_server.proxy_url("https://uploads.mangadex.org/data/h/1.jpg")
        manga_server._download_pages = lambda cid: [{"page": 1, "img": page_url}]
        fetched = []

        def checked_proxy(url):
            fetched.append(url)
            if url == "https://uploads.mangadex.org/data/h/1.jpg":
                return b"\xff\xd8\xff\xe0" + b"c" * 16, "image/jpeg"
            return self.original_proxy_fetch(url)

        manga_server._proxy_fetch = checked_proxy
        manga_server._dl_jobs["mangadex:cov"] = {"status": "pending", "total": 0, "done": 0, "error": None}
        manga_server._dl_worker("mangadex:s4", "mangadex:cov", "1", "t", "m", "http://127.0.0.1:5150/health")
        self.assertEqual(manga_server.dl_progress("mangadex:cov")["status"], "done")
        self.assertIn("http://127.0.0.1:5150/health", fetched)
        self.assertFalse(os.path.exists(os.path.join(manga_server.DOWNLOADS_DIR, "mangadex:s4", "cover.jpg")))

    def test_missing_downloads_dir_does_not_crash_pages_or_remove(self):
        shutil.rmtree(manga_server.DOWNLOADS_DIR)
        self.assertEqual(manga_server.dl_pages("mangadex:missing"), [])
        self.assertEqual(manga_server.dl_remove("mangadex:missing"), {"ok": False, "error": "not found"})


if __name__ == "__main__":
    unittest.main()
