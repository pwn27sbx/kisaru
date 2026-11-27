"""HentaiLA covers share the manga image proxy allowlist."""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

try:
    import manga_server
except Exception as exc:
    manga_server = None
    SKIP = f"manga_server unavailable: {exc}"
else:
    SKIP = ""


@unittest.skipIf(manga_server is None, SKIP)
class PrivateCoverHostsTest(unittest.TestCase):
    def test_provider_and_cover_cdn_are_allowed(self):
        self.assertTrue(manga_server.image_host_allowed("https://cdn.hentaila.com/x.jpg"))
        self.assertTrue(manga_server.image_host_allowed("https://hentaila.com/x.jpg"))

    def test_provider_cover_hosts_receive_the_provider_referer(self):
        self.assertEqual(manga_server.referer_for("cdn.hentaila.com"), "https://hentaila.com/")

    def test_foreign_cover_host_is_not_allowed(self):
        self.assertFalse(manga_server.image_host_allowed("https://foreign.example/x.jpg"))


if __name__ == "__main__":
    unittest.main()
