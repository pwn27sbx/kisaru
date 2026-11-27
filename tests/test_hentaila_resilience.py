"""Resilience and hermetic-network regressions for the private source adapter."""

import http.client
import io
import os
import sys
import unittest
import urllib.error
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

import hentaila_source as source

TOKEN = "a" * 32
TOKEN2 = "b" * 32
BASE = "https://hentaila.com"


def response(body, url):
    result = mock.MagicMock()
    result.__enter__.return_value = result
    result.read.return_value = body.encode() if isinstance(body, str) else body
    result.geturl.return_value = url
    return result


class ResilienceTest(unittest.TestCase):
    def setUp(self):
        source.clear_cache()
        source._last[0] = 0.0
        patcher = mock.patch.object(source, "proxy_target_allowed", return_value=True)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_rate_timeout_and_size_bound(self):
        now = [100.0]
        sleeps = []
        source._last[0] = 99.0

        def sleep(seconds):
            sleeps.append(seconds)
            now[0] += seconds

        with mock.patch.object(source.time, "monotonic", side_effect=lambda: now[0]), \
             mock.patch.object(source.time, "sleep", side_effect=sleep):
            source._rate_limit()
            source._rate_limit()
        self.assertEqual(sleeps, [1.0])

        with mock.patch.object(source, "_rate_limit"), \
             mock.patch.object(source._opener, "open", return_value=response("ok", BASE)) as opened:
            source._fetch(BASE)
        self.assertEqual(opened.call_args.kwargs["timeout"], source.TIMEOUT)

        body = b"x" * (source.MAX_HTML_BYTES + 1)
        with mock.patch.object(source, "_rate_limit"), \
             mock.patch.object(source._opener, "open", return_value=response(body, BASE)):
            with self.assertRaises(source.SourceError) as caught:
                source._fetch(BASE)
        self.assertEqual(caught.exception.code, "response_too_large")

    def test_failures_use_fixed_codes(self):
        with self.assertRaises(source.SourceError) as caught:
            source.search("sample", "not-a-page")
        self.assertEqual(caught.exception.code, "invalid_page")

        error = http.client.IncompleteRead(b"partial", 20)
        with mock.patch.object(source, "_rate_limit"), \
             mock.patch.object(source._opener, "open", side_effect=error):
            with self.assertRaises(source.SourceError) as caught:
                source._fetch(BASE)
        self.assertEqual(caught.exception.code, "network_error")

    def test_player_redirect_never_fetches_get(self):
        episode_url = BASE + "/media/item-one/1"
        player_url = BASE + "/play/" + TOKEN
        get_url = BASE + "/get/" + TOKEN
        episode = '<iframe src="/play/%s"></iframe>' % TOKEN
        requested = []

        def open_request(request, timeout):
            requested.append(request.full_url)
            if request.full_url == episode_url:
                return response(episode, episode_url)
            if request.full_url == player_url:
                error = urllib.error.HTTPError(
                    player_url, 302, "Found",
                    {"Location": "/get/" + TOKEN}, io.BytesIO(b"")
                )
                self.addCleanup(error.close)
                raise error
            return response("advertisement", request.full_url)

        with mock.patch.object(source, "_rate_limit"), \
             mock.patch.object(source._opener, "open", side_effect=open_request):
            with self.assertRaises(source.SourceError):
                source.links("item-one", "1")
        self.assertNotIn(get_url, requested)

    def test_approved_embed_host_fallback(self):
        episode_url = BASE + "/media/item-one/1"
        fallback = "https://cdn.dotanborito.net/play/" + TOKEN2
        episode = '<iframe src="/play/%s"></iframe><iframe src="%s"></iframe>' % (TOKEN, fallback)
        responses = [
            (episode, episode_url),
            source.SourceError("network_error"),
            ('<script type="module" src="/assets/player.js"></script>', fallback),
            ('const hlsBase = "/m3u8/";', fallback + "/assets/player.js"),
        ]
        with mock.patch.object(source, "_fetch", side_effect=responses):
            result = source.links("item-one", "1")
        self.assertEqual(
            result[0]["url"],
            "https://cdn.dotanborito.net/m3u8/" + TOKEN2,
        )

    def test_player_markup_variants(self):
        self.assertEqual(
            source.parse_play_token("<iframe src='/play/%s'></iframe>" % TOKEN),
            TOKEN,
        )
        malformed = '<iframe src="https://[::1/play/%s"></iframe>' % TOKEN
        with self.assertRaises(source.SourceError) as caught:
            source.parse_play_token(malformed)
        self.assertEqual(caught.exception.code, "invalid_player")


if __name__ == "__main__":
    unittest.main()
