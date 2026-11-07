"""Caches drop what expired and one bad number cannot break the list.

The manga, InManga and novel TTL caches kept every key the session ever
asked for, and `dl_list` sorted with a bare `float(chapterNum)`, so one
non-numeric entry turned the whole response into a 500 (audit 2026-11-06,
findings 25 and 35). The disk-cache prune also fired only every 32 writes,
which could overshoot the budget by up to 248 MiB (review advisory R3-001).

Run from the repo root:
    python3 -m unittest tests.test_cache_and_sort
"""

import json
import os
import shutil
import sys
import tempfile
import time
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
sys.path.insert(0, os.path.join(ROOT, "scripts", "novel_server"))

try:
    import manga_server
    import inmanga_source
    HAVE_MANGA = True
except Exception:  # noqa: BLE001 — curl_cffi/requests not installed
    HAVE_MANGA = False

try:
    from providers import utils as novel_utils
    HAVE_NOVEL = True
except Exception:  # noqa: BLE001 — provider helpers unavailable
    HAVE_NOVEL = False


class _CacheFixture:
    def __init__(self, module, attr, lock_attr):
        self.module = module
        self.attr = attr
        self.lock_attr = lock_attr
        self.saved = getattr(module, attr)

    def install(self):
        setattr(self.module, self.attr, {})

    def restore(self):
        setattr(self.module, self.attr, self.saved)


@unittest.skipUnless(HAVE_MANGA, "manga_server needs curl_cffi/requests")
class MangaCachePurgeTest(unittest.TestCase):
    def setUp(self):
        self.fixture = _CacheFixture(manga_server, "_cache", "_cache_lock")
        self.fixture.install()
        now = time.monotonic()
        manga_server._cache["expired"] = ("old", now - 10)
        manga_server._cache["fresh"] = ("kept", now + 60)

    def tearDown(self):
        self.fixture.restore()

    def test_a_miss_drops_expired_entries(self):
        self.assertEqual(manga_server._cached("new", 60, lambda: "value"), "value")
        self.assertNotIn("expired", manga_server._cache)
        self.assertIn("fresh", manga_server._cache)


@unittest.skipUnless(HAVE_MANGA, "manga_server needs curl_cffi/requests")
class InmangaCachePurgeTest(unittest.TestCase):
    def setUp(self):
        self.fixture = _CacheFixture(inmanga_source, "_cache", "_cache_lock")
        self.fixture.install()
        now = time.monotonic()
        inmanga_source._cache["expired"] = ("old", now - 10)
        inmanga_source._cache["fresh"] = ("kept", now + 60)

    def tearDown(self):
        self.fixture.restore()

    def test_a_miss_drops_expired_entries(self):
        self.assertEqual(inmanga_source._cached("new", 60, lambda: "value"), "value")
        self.assertNotIn("expired", inmanga_source._cache)
        self.assertIn("fresh", inmanga_source._cache)


@unittest.skipUnless(HAVE_NOVEL, "the novel providers are unavailable")
class NovelCachePurgeTest(unittest.TestCase):
    def setUp(self):
        self.saved = novel_utils._cache
        novel_utils._cache = {}
        now = time.monotonic()
        novel_utils._cache["expired"] = ("old", now - 10)
        novel_utils._cache["fresh"] = ("kept", now + 60)

    def tearDown(self):
        novel_utils._cache = self.saved

    def test_a_miss_drops_expired_entries(self):
        self.assertEqual(novel_utils.cached("new", 60, lambda: "value"), "value")
        self.assertNotIn("expired", novel_utils._cache)
        self.assertIn("fresh", novel_utils._cache)


@unittest.skipUnless(HAVE_MANGA, "manga_server needs curl_cffi/requests")
class DlListSortTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.original = manga_server.DOWNLOADS_DIR
        manga_server.DOWNLOADS_DIR = os.path.join(self.tmp, "downloads")
        series = os.path.join(manga_server.DOWNLOADS_DIR, "series1")
        os.makedirs(series)
        with open(os.path.join(series, "series_meta.json"), "w") as fh:
            json.dump({"id": "s1", "title": "One", "localId": "series1",
                       "rawCoverUrl": ""}, fh)
        for chapter, number in (("ch1", "2"), ("ch2", "extra"), ("ch3", "10")):
            directory = os.path.join(series, chapter)
            os.makedirs(directory)
            with open(os.path.join(directory, "meta.json"), "w") as fh:
                json.dump({"chapterId": chapter, "chapterNum": number,
                           "title": chapter, "pages": 1}, fh)

    def tearDown(self):
        manga_server.DOWNLOADS_DIR = self.original
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_a_non_numeric_chapter_number_does_not_break_the_list(self):
        result = manga_server.dl_list()
        self.assertEqual(len(result), 1)
        numbers = [chapter["chapterNum"] for chapter in result[0]["chapters"]]
        self.assertEqual(numbers, ["10", "2", "extra"])


@unittest.skipUnless(HAVE_MANGA, "manga_server needs curl_cffi/requests")
class DiskPruneTriggerTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.saved_writes = manga_server._img_disk_writes
        self.saved_pending = manga_server._img_disk_pending
        self.saved_every = manga_server._IMG_DISK_PRUNE_EVERY
        self.saved_bytes = manga_server._IMG_DISK_PRUNE_BYTES
        self.saved_budget = manga_server.IMG_DISK_MAX_TOTAL_BYTES

    def tearDown(self):
        manga_server._img_disk_writes = self.saved_writes
        manga_server._img_disk_pending = self.saved_pending
        manga_server._IMG_DISK_PRUNE_EVERY = self.saved_every
        manga_server._IMG_DISK_PRUNE_BYTES = self.saved_bytes
        manga_server.IMG_DISK_MAX_TOTAL_BYTES = self.saved_budget
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_the_budget_is_checked_after_enough_bytes_not_only_after_32_writes(self):
        manga_server._img_disk_writes = 0
        manga_server._img_disk_pending = 0
        manga_server._IMG_DISK_PRUNE_EVERY = 1000
        manga_server._IMG_DISK_PRUNE_BYTES = 12
        manga_server.IMG_DISK_MAX_TOTAL_BYTES = 12

        manga_server.img_disk_put("https://cdn/a.jpg", b"\xff\xd8\xff" + b"a" * 5, self.dir)
        manga_server.img_disk_put("https://cdn/b.jpg", b"\xff\xd8\xff" + b"b" * 5, self.dir)

        self.assertEqual(len(os.listdir(self.dir)), 1)
        newest = manga_server.img_disk_path("https://cdn/b.jpg", self.dir)
        self.assertTrue(os.path.exists(newest))


if __name__ == "__main__":
    unittest.main()
