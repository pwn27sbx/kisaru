"""The image cache on disk has a total size budget.

Every page the proxy served was written under `~/.cache/kisaru/covers` (the
name is historical) with only a per-image cap of 8 MB and no total limit, so
the folder grew with browsing (audit 2026-11-06, finding 5).

Run from the repo root:
    python3 -m unittest tests.test_manga_image_disk_cache
"""

import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

try:
    import manga_server
    HAVE_SERVER = True
except Exception:  # noqa: BLE001 — curl_cffi/requests not installed
    HAVE_SERVER = False


JPEG = b"\xff\xd8\xff"


def body(size):
    return JPEG + b"x" * max(0, size - len(JPEG))


class _Cache:
    """A throwaway cache folder and the budget knobs, restored on teardown."""

    def __init__(self):
        self.dir = tempfile.mkdtemp()
        self.budget = manga_server.IMG_DISK_MAX_TOTAL_BYTES
        self.every = manga_server._IMG_DISK_PRUNE_EVERY
        self.writes = manga_server._img_disk_writes

    def write(self, name, size, mtime):
        path = os.path.join(self.dir, name)
        with open(path, "wb") as fh:
            fh.write(body(size))
        os.utime(path, (mtime, mtime))
        return path

    def restore(self):
        manga_server.IMG_DISK_MAX_TOTAL_BYTES = self.budget
        manga_server._IMG_DISK_PRUNE_EVERY = self.every
        manga_server._img_disk_writes = self.writes
        shutil.rmtree(self.dir, ignore_errors=True)


@unittest.skipUnless(HAVE_SERVER, "manga_server needs curl_cffi/requests")
class ImageDiskCacheTest(unittest.TestCase):
    def setUp(self):
        self.cache = _Cache()

    def tearDown(self):
        self.cache.restore()

    def test_prune_removes_the_oldest_files_until_the_budget_holds(self):
        self.cache.write("oldest.img", 10, 1000)
        self.cache.write("middle.img", 10, 2000)
        self.cache.write("newer.img", 10, 3000)
        self.cache.write("newest.img", 10, 4000)

        removed = manga_server.prune_img_disk_cache(self.cache.dir, max_bytes=25)

        self.assertEqual(removed, 2)
        self.assertEqual(sorted(os.listdir(self.cache.dir)),
                         ["newer.img", "newest.img"])

    def test_nothing_is_removed_under_the_budget(self):
        self.cache.write("a.img", 10, 1000)
        self.cache.write("b.img", 10, 2000)

        self.assertEqual(manga_server.prune_img_disk_cache(self.cache.dir, max_bytes=25), 0)
        self.assertEqual(len(os.listdir(self.cache.dir)), 2)

    def test_the_fresh_file_survives_even_when_it_is_the_oldest(self):
        kept = self.cache.write("kept.img", 100, 1000)
        self.cache.write("other.img", 10, 2000)

        manga_server.prune_img_disk_cache(self.cache.dir, max_bytes=10, keep=kept)

        self.assertTrue(os.path.exists(kept))

    def test_a_put_prunes_when_its_turn_comes(self):
        manga_server._IMG_DISK_PRUNE_EVERY = 1
        manga_server.IMG_DISK_MAX_TOTAL_BYTES = 12

        manga_server.img_disk_put("https://cdn/one.jpg", body(8), self.cache.dir)
        manga_server.img_disk_put("https://cdn/two.jpg", body(8), self.cache.dir)

        self.assertEqual(len(os.listdir(self.cache.dir)), 1)
        newest = manga_server.img_disk_path("https://cdn/two.jpg", self.cache.dir)
        self.assertTrue(os.path.exists(newest))

    def test_a_body_over_the_per_image_cap_is_not_stored(self):
        manga_server.img_disk_put(
            "https://cdn/huge.jpg", body(manga_server.IMG_DISK_MAX_BYTES + 1),
            self.cache.dir)

        self.assertEqual(os.listdir(self.cache.dir), [])


if __name__ == "__main__":
    unittest.main()
