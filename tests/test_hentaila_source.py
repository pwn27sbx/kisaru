"""Contract tests for the private anime source adapter.

All HTTP is mocked. Fixtures are neutral and contain no live titles, URLs,
tokens, cookies or images.
"""

import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

import hentaila_source  # noqa: E402

FIX = os.path.join(os.path.dirname(__file__), "fixtures", "hentaila")
TOKEN = "a" * 32


def load(name):
    with open(os.path.join(FIX, name), encoding="utf-8") as handle:
        return handle.read()


class OfflineTestCase(unittest.TestCase):
    def setUp(self):
        patcher = mock.patch.object(hentaila_source, "proxy_target_allowed", return_value=True)
        patcher.start()
        self.addCleanup(patcher.stop)


class ParseSearchTest(OfflineTestCase):
    def test_cards_and_pagination(self):
        items = hentaila_source.parse_search(load("catalogue.html"))
        self.assertEqual([item["id"] for item in items], ["item-one", "item-two"])
        self.assertEqual(items[0]["name"], "Sample item one")
        self.assertEqual(items[0]["thumbnail"], "/covers/item-one.jpg")
        self.assertEqual(items[0]["available_episodes"]["sub"], 1)
        self.assertTrue(hentaila_source.has_next_page(load("catalogue.html"), 1))
        self.assertFalse(hentaila_source.has_next_page(load("catalogue.html"), 2))


class ParseSeriesTest(OfflineTestCase):
    def test_series_and_episode_numbers(self):
        series = hentaila_source.parse_series(load("series.html"))
        self.assertEqual(series["name"], "Sample series")
        self.assertEqual(series["thumbnail"], "/covers/item-one.jpg")
        self.assertEqual(series["episodes"], ["1", "2", "10"])


class ParseEpisodeTest(OfflineTestCase):
    def test_only_one_same_origin_play_token_is_accepted(self):
        html = load("episode.html").replace("{token}", TOKEN)
        self.assertEqual(hentaila_source.parse_play_token(html), TOKEN)

    def test_missing_play_token_is_rejected(self):
        html = load("episode.html").replace("/play/{token}", "/get/{token}")
        with self.assertRaises(hentaila_source.SourceError):
            hentaila_source.parse_play_token(html.replace("{token}", TOKEN))

    def test_duplicate_play_tokens_are_rejected(self):
        html = load("episode.html").replace("{token}", TOKEN)
        html = html.replace("</body>", '<iframe src="/play/%s"></iframe></body>' % TOKEN)
        with self.assertRaises(hentaila_source.SourceError):
            hentaila_source.parse_play_token(html)

    def test_foreign_play_token_is_rejected(self):
        html = load("episode.html").replace('/play/{token}', 'https://foreign.example/play/{token}')
        with self.assertRaises(hentaila_source.SourceError):
            hentaila_source.parse_play_token(html.replace("{token}", TOKEN))

    def test_approved_cross_origin_player_is_accepted(self):
        html = load("episode.html").replace('/play/{token}', 'https://cdn.dotanborito.net/play/{token}')
        self.assertEqual(hentaila_source.parse_play_token(html.replace("{token}", TOKEN)), TOKEN)


class ParsePlayerTest(OfflineTestCase):
    def test_module_and_hls_base(self):
        html = load("player.html")
        self.assertEqual(hentaila_source.parse_player_module(html), "/assets/player-fixture.js")
        base = hentaila_source.parse_hls_base(load("player.js"), "https://hentaila.com")
        self.assertEqual(base, "https://hentaila.com/m3u8/")


class SearchTest(OfflineTestCase):
    def test_search_uses_catalogue_route_and_normalizes_cover(self):
        with mock.patch.object(hentaila_source, "_fetch", return_value=(load("catalogue.html"), "https://hentaila.com/catalogo?search=a&page=1")) as fetch:
            result = hentaila_source.search("a", 1)
        self.assertEqual(result["nextPage"], 2)
        self.assertEqual(result["results"][0]["thumbnail"], "https://hentaila.com/covers/item-one.jpg")
        fetch.assert_called_once()
        self.assertIn("search=a", fetch.call_args.args[0])
        self.assertIn("page=1", fetch.call_args.args[0])


class SeriesTest(OfflineTestCase):
    def test_series_route(self):
        with mock.patch.object(hentaila_source, "_fetch", return_value=(load("series.html"), "https://hentaila.com/media/item-one")) as fetch:
            result = hentaila_source.series("item-one")
        self.assertEqual(result["episodes"], ["1", "2", "10"])
        self.assertEqual(result["thumbnail"], "https://hentaila.com/covers/item-one.jpg")
        fetch.assert_called_once_with("https://hentaila.com/media/item-one")


class LinksTest(OfflineTestCase):
    def test_links_follow_play_only_and_build_hls(self):
        episode = load("episode.html").replace("{token}", TOKEN)
        responses = [
            (episode, "https://hentaila.com/media/item-one/1"),
            (load("player.html"), "https://hentaila.com/play/%s" % TOKEN),
            (load("player.js"), "https://hentaila.com/assets/player-fixture.js"),
        ]
        with mock.patch.object(hentaila_source, "_fetch", side_effect=responses) as fetch:
            links = hentaila_source.links("item-one", "1")
        self.assertEqual(len(links), 1)
        self.assertEqual(links[0]["url"], "https://hentaila.com/m3u8/%s" % TOKEN)
        self.assertEqual(links[0]["type"], "m3u8")
        self.assertEqual(links[0]["provider"], "HentaiLA")
        self.assertEqual(fetch.call_count, 3)
        self.assertNotIn("/get/", "\n".join(call.args[0] for call in fetch.call_args_list))


class CoverTest(OfflineTestCase):
    def test_cover_uses_existing_manga_image_proxy(self):
        proxied = hentaila_source.proxy_cover("/covers/item-one.jpg", "http://127.0.0.1:5151")
        self.assertTrue(proxied.startswith("http://127.0.0.1:5151/image?url="))
        self.assertIn("hentaila.com", proxied)


class NetworkPolicyTest(OfflineTestCase):
    def test_rejects_unapproved_or_unsafe_urls(self):
        for url in (
            "http://hentaila.com/hub",
            "https://user:pass@hentaila.com/hub",
            "https://127.0.0.1/hub",
            "https://foreign.example/hub",
            "file:///tmp/source",
        ):
            with self.subTest(url=url), self.assertRaises(hentaila_source.SourceError):
                hentaila_source.validate_url(url, allowed_hosts={"hentaila.com"})

    def test_accepts_approved_https_host(self):
        hentaila_source.validate_url("https://hentaila.com/hub", allowed_hosts={"hentaila.com"})


if __name__ == "__main__":
    unittest.main()
