"""Tests for the manga image proxy (manga_server.proxy_image / retry).

manga_server imports curl_cffi/requests, so these run only where one of them is
installed (the app venv); otherwise they are skipped.
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

try:
    import manga_server
    import manga_sources
    HAVE_SERVER = True
except Exception:  # noqa: BLE001 — curl_cffi/requests not installed
    HAVE_SERVER = False


class RecordingHandler:
    def __init__(self):
        self.responses = []
        self.errors = []
        self.body = b""

        class _Wfile:
            def write(_self, data):
                self.body += data

        self.wfile = _Wfile()

    def send_response(self, code, *a, **k):
        self.responses.append(code)

    def send_header(self, *a, **k):
        pass

    def end_headers(self):
        pass

    def send_error(self, code, *a, **k):
        self.errors.append(code)


@unittest.skipUnless(HAVE_SERVER, "manga_server needs curl_cffi/requests")
class ImageRefererTest(unittest.TestCase):
    """ManhwaWeb's CDN answers 403 without its own site as the referer."""

    def test_manhwaweb_hosts_get_the_referer(self):
        for url in ("https://img1mw.xyz/manhwas/x/chapter_1/001.jpg",
                    "https://img2mw.xyz/x.jpg",
                    "https://uploads.manhwaweb.com/x.jpg"):
            self.assertEqual(manga_server.image_headers(url).get("Referer"),
                             "https://manhwaweb.com/", url)

    def test_other_hosts_are_left_alone(self):
        headers = manga_server.image_headers("https://uploads.mangadex.org/x.jpg")
        self.assertNotIn("Referer", headers)


@unittest.skipUnless(HAVE_SERVER, "manga_server requires curl_cffi or requests")
class ProxyImageTest(unittest.TestCase):
    def test_upstream_404_maps_to_404(self):
        class Upstream404(Exception):
            class response:
                status_code = 404

        handler = RecordingHandler()
        original = manga_server._raw_get
        manga_server._raw_get = lambda *a, **k: (_ for _ in ()).throw(Upstream404())
        try:
            manga_server.proxy_image(handler, "https://x/nope.jpg")
        finally:
            manga_server._raw_get = original
        self.assertEqual(handler.errors, [404])

    def test_generic_error_maps_to_502(self):
        handler = RecordingHandler()
        original = manga_server._raw_get
        manga_server._raw_get = lambda *a, **k: (_ for _ in ()).throw(RuntimeError("boom"))
        try:
            manga_server.proxy_image(handler, "https://x/nope.jpg")
        finally:
            manga_server._raw_get = original
        self.assertEqual(handler.errors, [502])

    def test_retry_on_404_recovers(self):
        class Upstream404(Exception):
            class response:
                status_code = 404

        handler = RecordingHandler()
        state = {"n": 0}

        def raw(url):
            state["n"] += 1
            if state["n"] == 1:
                raise Upstream404()
            return b"img", "image/jpeg"

        orig_raw, orig_retry = manga_server._raw_get, manga_server._retry_mangadex_page
        manga_server._raw_get = raw
        manga_server._retry_mangadex_page = lambda chapter, page, old: "https://uploads.mangadex.org/data-saver/h/f.jpg"
        try:
            manga_server.proxy_image(handler, "https://node.example/data-saver/h/f.jpg", "chapter", "1")
        finally:
            manga_server._raw_get, manga_server._retry_mangadex_page = orig_raw, orig_retry
        self.assertEqual(handler.responses, [200])
        self.assertEqual(handler.errors, [])
        self.assertEqual(state["n"], 2)

    def test_retry_uses_canonical_host_when_node_unchanged(self):
        original = manga_sources.at_home_fresh
        manga_sources.at_home_fresh = lambda chapter, **k: {
            "baseUrl": "https://node.example", "chapter": {"hash": "h", "dataSaver": ["f.jpg"]}}
        try:
            url = manga_server._retry_mangadex_page("chapter", 1, "https://node.example/data-saver/h/f.jpg")
        finally:
            manga_sources.at_home_fresh = original
        self.assertEqual(url, "https://uploads.mangadex.org/data-saver/h/f.jpg")

    def test_english_fallback_flags_language(self):
        orig_search, orig_info = manga_server.search, manga_server.info
        manga_server.search = lambda q, mtype=None, offset=0, sort="": {
            "results": [{"id": "S1", "title": "Foo"}]}
        manga_server.info = lambda i: {"id": "S1", "title": "Foo", "chapters": [{"id": "C1", "chapter": "1"}]}
        try:
            data = manga_server._english_fallback("Foo")
        finally:
            manga_server.search, manga_server.info = orig_search, orig_info
        self.assertEqual(data["language"], "en")
        self.assertEqual(data["notice"], "no_spanish")
        self.assertTrue(data["id"].startswith("weebcentral:"))
        self.assertTrue(data["chapters"][0]["id"].startswith("weebcentral:"))


@unittest.skipUnless(HAVE_SERVER, "manga_server needs curl_cffi/requests")
class HealthPayloadTest(unittest.TestCase):
    """GET /health names the source that answers first, so the panel's source
    chip shows real data instead of a hardcoded label."""

    def test_payload_names_the_first_source_of_the_chain(self):
        self.assertEqual(
            manga_server.health_payload(["mangadex", "inmanga", "zonatmo"]),
            {"ok": True, "source": "mangadex",
             "chain": ["mangadex", "inmanga", "zonatmo"]})

    def test_payload_keeps_the_single_source_chain_whole(self):
        payload = manga_server.health_payload(["weebcentral"])
        self.assertEqual(payload["source"], "weebcentral")
        self.assertEqual(payload["chain"], ["weebcentral"])

    def test_an_empty_chain_reports_no_source(self):
        self.assertEqual(manga_server.health_payload([]),
                         {"ok": True, "source": "", "chain": []})

    def test_it_does_not_mutate_the_chain_it_is_given(self):
        chain = ["mangadex", "inmanga"]
        manga_server.health_payload(chain)
        self.assertEqual(chain, ["mangadex", "inmanga"])

    def test_without_an_argument_it_reads_the_active_chain(self):
        original = manga_server.manga_chain.active_chain
        manga_server.manga_chain.active_chain = lambda: ["zonatmo_org"]
        try:
            payload = manga_server.health_payload()
        finally:
            manga_server.manga_chain.active_chain = original
        self.assertEqual(payload["source"], "zonatmo_org")
        # The field /health already promised stays: the extension is additive,
        # so a reader that only checks `ok` keeps working.
        self.assertIs(payload["ok"], True)

    def test_the_health_route_serves_the_same_payload(self):
        """The route must not re-implement the body: one helper, one shape.

        Calls do_GET on a handler built without a socket, so the real route
        wiring is exercised without binding a port.
        """
        handler = manga_server.Handler.__new__(manga_server.Handler)
        handler.path = "/health"
        handler.answered = []
        handler._json = lambda data, status=200: handler.answered.append(data)
        handler.do_GET()
        self.assertEqual(len(handler.answered), 1, handler.answered)
        payload = handler.answered[0]
        self.assertIs(payload["ok"], True)
        self.assertEqual(payload["chain"], manga_server.manga_chain.active_chain())
        self.assertEqual(payload["source"], payload["chain"][0])



if __name__ == "__main__":
    unittest.main()
