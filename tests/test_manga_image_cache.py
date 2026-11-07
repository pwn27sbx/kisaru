"""The in-memory image cache is bounded, reads included.

`_img_get` added every disk hit to `_img_cache` and only `_img_put` evicted,
by entry count, so a long session grew the dict without limit and one large
page could still push it past its entry cap (audit 2026-11-06, finding 4).

Run from the repo root:
    python3 -m unittest tests.test_manga_image_cache
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

try:
    import manga_server
    HAVE_SERVER = True
except Exception:  # noqa: BLE001 — curl_cffi/requests not installed
    HAVE_SERVER = False


JPEG = b"\xff\xd8\xff"


def image(size):
    return JPEG + b"x" * max(0, size - len(JPEG))


@unittest.skipUnless(HAVE_SERVER, "manga_server needs curl_cffi/requests")
class ImageMemoryCacheTest(unittest.TestCase):
    def setUp(self):
        self.original_cache = manga_server._img_cache
        self.original_bytes = manga_server._img_cache_bytes
        self.original_max = manga_server._img_cache_max
        self.original_budget = manga_server.IMG_CACHE_MAX_BYTES
        self.original_disk_get = manga_server.img_disk_get
        self.original_disk_put = manga_server.img_disk_put
        manga_server._img_cache = {}
        manga_server._img_cache_bytes = 0
        manga_server.img_disk_put = lambda url, body, directory=None: None

    def tearDown(self):
        manga_server._img_cache = self.original_cache
        manga_server._img_cache_bytes = self.original_bytes
        manga_server._img_cache_max = self.original_max
        manga_server.IMG_CACHE_MAX_BYTES = self.original_budget
        manga_server.img_disk_get = self.original_disk_get
        manga_server.img_disk_put = self.original_disk_put

    def test_a_disk_hit_is_evicted_when_the_entry_cap_is_reached(self):
        manga_server._img_cache_max = 2
        manga_server.img_disk_get = lambda url, directory=None: (JPEG, "image/jpeg")

        for url in ("a", "b", "c"):
            self.assertEqual(manga_server._img_get(url), (JPEG, "image/jpeg"))

        self.assertEqual(len(manga_server._img_cache), 2)
        self.assertNotIn("a", manga_server._img_cache)

    def test_the_cache_is_bounded_by_bytes(self):
        manga_server._img_cache_max = 100
        manga_server.IMG_CACHE_MAX_BYTES = 10
        manga_server.img_disk_get = lambda url, directory=None: (image(6), "image/jpeg")

        for url in ("a", "b", "c", "d"):
            manga_server._img_get(url)

        self.assertLessEqual(manga_server._img_cache_bytes, 10)
        self.assertEqual(len(manga_server._img_cache), 1)

    def test_an_image_bigger_than_the_budget_is_served_but_not_cached(self):
        manga_server.IMG_CACHE_MAX_BYTES = 10
        manga_server.img_disk_get = lambda url, directory=None: (image(64), "image/jpeg")

        self.assertEqual(manga_server._img_get("a")[0], image(64))
        self.assertEqual(manga_server._img_cache, {})
        self.assertEqual(manga_server._img_cache_bytes, 0)

    def test_a_hit_makes_its_entry_the_newest(self):
        manga_server._img_cache_max = 2
        manga_server.img_disk_get = lambda url, directory=None: (JPEG, "image/jpeg")

        for url in ("a", "b", "a", "c"):
            manga_server._img_get(url)

        self.assertIn("a", manga_server._img_cache)
        self.assertNotIn("b", manga_server._img_cache)

    def test_a_put_is_served_from_memory(self):
        manga_server.img_disk_get = lambda url, directory=None: None
        manga_server._img_put("a", JPEG, "image/jpeg")

        self.assertEqual(manga_server._img_get("a"), (JPEG, "image/jpeg"))

    def test_a_miss_returns_none_and_caches_nothing(self):
        manga_server.img_disk_get = lambda url, directory=None: None

        self.assertIsNone(manga_server._img_get("a"))
        self.assertEqual(manga_server._img_cache, {})


if __name__ == "__main__":
    unittest.main()
