"""Tests for the manga image proxy (manga_server.proxy_image / retry).

manga_server imports curl_cffi/requests, so these run only where one of them is
installed (the app venv); otherwise they are skipped.
"""

import os
import shutil
import sys
import tempfile
import unittest
from urllib.parse import quote

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

    def test_mangafire_reader_hosts_get_the_referer(self):
        # The mfcdnN number rotates per chapter, so the rule matches the family.
        for url in ("https://pw6.mfcdn1.xyz/mf/x/h/p.jpg",
                    "https://pw6.mfcdn2.xyz/mf/x/h/p.jpg",
                    "https://l1n.mfcdn12.xyz/mf/y/h/p.jpg"):
            self.assertEqual(manga_server.image_headers(url).get("Referer"),
                             "https://mangafire.to/", url)

    def test_mangafire_lookalikes_get_no_referer(self):
        for url in ("https://evil-mfcdn1.xyz/x.jpg",
                    "https://mfcdn1.xyz.evil.example/x.jpg",
                    "https://static.mfcdn.nl/x.jpg"):
            self.assertNotIn("Referer", manga_server.image_headers(url), url)


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


    def test_an_html_challenge_is_not_an_image(self):
        """A bot check must read as a failure, not as a broken cover.

        MangaDex answers 200 with an HTML "Browser verification" page when it
        gates the IP. The proxy used to hand those bytes to Qt as an image: the
        grid filled with placeholders and the log said "Unsupported image
        format". This is the rule that keeps that from being silent.
        """
        challenge = b"<!doctype html><html><head><title>MangaDex - Browser verification</title>"
        self.assertFalse(manga_server.is_image_response("text/html", challenge))
        self.assertFalse(manga_server.is_image_response("text/html; charset=utf-8", challenge))
        self.assertFalse(manga_server.is_image_response("", challenge))
        self.assertFalse(manga_server.is_image_response("application/octet-stream", challenge))

    def test_real_image_bytes_pass_the_check(self):
        jpeg = b"\xff\xd8\xff\xe0" + b"\x00" * 32
        png = b"\x89PNG\r\n\x1a\n" + b"\x00" * 32
        webp = b"RIFF\x00\x00\x00\x00WEBP" + b"\x00" * 32
        gif = b"GIF89a" + b"\x00" * 32
        # A declared image type is enough, even with junk bytes.
        self.assertTrue(manga_server.is_image_response("image/jpeg", jpeg))
        self.assertTrue(manga_server.is_image_response("image/webp; charset=binary", webp))
        # A host that mislabels a cover must not lose it: the bytes decide
        # whenever the type is not an image.
        for body in (jpeg, png, webp, gif):
            self.assertTrue(manga_server.is_image_response("", body), body[:6])
            self.assertTrue(manga_server.is_image_response("application/octet-stream", body), body[:6])
        self.assertFalse(manga_server.is_image_response("", b"{\"error\": \"nope\"}"))

    def test_a_failed_cover_is_not_asked_again_for_a_minute(self):
        """32 covers x 2 retries per panel open is what got the IP challenged.

        The window is per URL and expires on its own, so a cover that comes
        back is fetched again without a restart.
        """
        url = "https://example.invalid/cover.jpg"
        self.assertFalse(manga_server.img_blocked(url, now=1000.0))
        manga_server.img_mark_failed(url, now=1000.0)
        self.assertTrue(manga_server.img_blocked(url, now=1000.0))
        self.assertTrue(manga_server.img_blocked(url, now=1000.0 + manga_server.IMG_FAIL_TTL - 1))
        self.assertFalse(manga_server.img_blocked(url, now=1000.0 + manga_server.IMG_FAIL_TTL))
        # Expired entries are dropped as they are read, not accumulated.
        self.assertFalse(manga_server.img_blocked(url, now=1000.0 + manga_server.IMG_FAIL_TTL))

    def test_a_cover_survives_on_disk(self):
        """Art already fetched must not vanish because the CDN stopped answering."""
        import tempfile
        jpeg = b"\xff\xd8\xff\xe0" + b"\x00" * 64
        with tempfile.TemporaryDirectory() as tmp:
            url = "https://example.invalid/cover.jpg"
            self.assertIsNone(manga_server.img_disk_get(url, directory=tmp))
            manga_server.img_disk_put(url, jpeg, directory=tmp)
            got = manga_server.img_disk_get(url, directory=tmp)
            self.assertEqual(got[0], jpeg)
            self.assertEqual(got[1], "image/jpeg")

    def test_only_images_are_stored_on_disk(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            url = "https://example.invalid/broken.jpg"
            manga_server.img_disk_put(url, b"<!doctype html><html>challenge</html>", directory=tmp)
            self.assertIsNone(manga_server.img_disk_get(url, directory=tmp))

    def test_a_challenged_host_is_left_alone(self):
        """One browser check must cost one request, not one per cover."""
        host = "uploads.example.invalid"
        self.assertFalse(manga_server.img_host_down(host, now=500.0))
        manga_server.img_mark_host_down(host, now=500.0)
        self.assertTrue(manga_server.img_host_down(host, now=500.0))
        self.assertTrue(manga_server.img_host_down(host, now=500.0 + manga_server.IMG_HOST_TTL - 1))
        self.assertFalse(manga_server.img_host_down(host, now=500.0 + manga_server.IMG_HOST_TTL))


class FakeResponse:
    def __init__(self, body=b"\xff\xd8\xff\xe0cover", ctype="image/jpeg"):
        self.content = body
        self.headers = {"Content-Type": ctype}

    def raise_for_status(self):
        pass


class FakeSession:
    """Records the headers of every request it is given."""

    def __init__(self, body=b"\xff\xd8\xff\xe0cover", ctype="image/jpeg"):
        self.calls = []
        self.body = body
        self.ctype = ctype

    def get(self, url, headers=None, timeout=None):
        self.calls.append(headers or {})
        return FakeResponse(self.body, self.ctype)


CHALLENGE = b"<!doctype html><html><head><title>MangaDex - Browser verification</title>"


@unittest.skipUnless(HAVE_SERVER, "manga_server needs curl_cffi/requests")
class MangaDexFetchPolicyTest(unittest.TestCase):
    """MangaDex challenges impersonation: covers go out as kisaru itself.

    The CDN answers 302 to /edge/challenge for the Firefox impersonation and
    200 for an honest client, so the image proxy must stop pretending — for
    MangaDex hosts only, because every other source still needs the browser.
    """

    def setUp(self):
        self.orig_plain, self.orig_session = manga_server._plain_session, manga_server._session

    def tearDown(self):
        manga_server._plain_session, manga_server._session = self.orig_plain, self.orig_session

    def _forbid_plain(self):
        def never():
            raise AssertionError("the honest session must not be used here")
        manga_server._plain_session = never

    def _forbid_impersonation(self):
        def never():
            raise AssertionError("the impersonating session must not be used here")
        manga_server._session = never

    def test_a_mangadex_cover_is_fetched_with_the_honest_user_agent(self):
        plain = FakeSession()
        manga_server._plain_session = lambda: plain
        self._forbid_impersonation()
        body, ctype = manga_server._raw_get("https://uploads.mangadex.org/covers/abc/512.jpg")
        sent = plain.calls[0]
        self.assertEqual(sent["User-Agent"], manga_server.app_meta.user_agent())
        self.assertEqual(sent["Accept"], "image/*")
        self.assertNotIn("Referer", sent)
        self.assertEqual([k for k in sent if k.lower().startswith(("sec-", "upgrade-", "dnt"))], [])
        self.assertEqual(ctype, "image/jpeg")
        self.assertTrue(body.startswith(b"\xff\xd8"))

    def test_an_at_home_node_keeps_the_site_referer(self):
        plain = FakeSession()
        manga_server._plain_session = lambda: plain
        self._forbid_impersonation()
        manga_server._raw_get("https://cmdxd98sb0x3yprd.mangadex.network/data-saver/h/1.webp")
        sent = plain.calls[0]
        self.assertEqual(sent["Referer"], "https://mangadex.org/")
        self.assertEqual(sent["User-Agent"], manga_server.app_meta.user_agent())

    def test_every_other_host_keeps_the_impersonating_session(self):
        imp = FakeSession()
        manga_server._session = lambda: imp
        self._forbid_plain()
        manga_server._raw_get("https://img1mw.xyz/manhwas/x/001.jpg")
        sent = imp.calls[0]
        self.assertTrue(sent["User-Agent"].startswith("Mozilla/5.0"), sent["User-Agent"])
        self.assertEqual(sent["Referer"], "https://manhwaweb.com/")

    def test_the_policy_matches_by_host_not_by_substring(self):
        for url in ("https://evil-mangadex.network.example.com/x.jpg",
                    "https://notmangadex.network/x.jpg",
                    "https://uploads.mangadex.org.example.com/x.jpg",
                    "https://mangadex.network/x.jpg",
                    "https://uploads.mangadex.org.evil.example/x.jpg"):
            self.assertFalse(manga_server.uses_mangadex_image_policy(url), url)
        for url in ("https://uploads.mangadex.org/x.jpg",
                    "https://UPLOADS.MANGADEX.ORG/x.jpg",
                    "https://cmdxd98sb0x3yprd.mangadex.network/data-saver/h/1.webp"):
            self.assertTrue(manga_server.uses_mangadex_image_policy(url), url)

    def test_a_challenge_page_is_never_served_or_cached(self):
        """The honest UA is for fetch policy, not for skipping the image check."""
        handler = RecordingHandler()
        url = "https://uploads.mangadex.org/covers/abc/512.jpg"
        plain = FakeSession(CHALLENGE, "text/html")
        manga_server._plain_session = lambda: plain
        self._forbid_impersonation()
        original_get = manga_server._img_get
        manga_server._img_get = lambda target: None
        try:
            manga_server.proxy_image(handler, url)
        finally:
            manga_server._img_get = original_get
        self.assertEqual(handler.errors, [502])
        self.assertNotIn(url, manga_server._img_cache)


@unittest.skipUnless(HAVE_SERVER, "manga_server needs curl_cffi/requests")
class DownloadImageGuardTest(unittest.TestCase):
    """A challenge page must never be written to disk as a page or a cover."""

    CHAPTER_URL = "https://cmdxd98sb0x3yprd.mangadex.network/data-saver/h/1.jpg"
    COVER_URL   = "https://uploads.mangadex.org/covers/abc/512.jpg"

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.orig = (manga_server.DOWNLOADS_DIR, manga_server._download_pages,
                     manga_server._raw_get, manga_server._img_get,
                     manga_server._img_put)
        manga_server.DOWNLOADS_DIR = self.tmp
        manga_server._download_pages = lambda cid: [{
            "page": 1,
            "img": "http://127.0.0.1:5150/image?url=" + quote(self.CHAPTER_URL, safe=""),
        }]
        manga_server._img_get = lambda url: None
        manga_server._img_put = lambda *a, **k: None
        manga_server._dl_jobs["ch1"] = {"status": "queued", "total": 0, "done": 0}

    def tearDown(self):
        (manga_server.DOWNLOADS_DIR, manga_server._download_pages,
         manga_server._raw_get, manga_server._img_get,
         manga_server._img_put) = self.orig
        manga_server._dl_jobs.pop("ch1", None)
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _chapter_dir(self):
        return os.path.join(self.tmp, "s1", "ch1")

    def test_a_challenge_page_is_never_saved_as_a_page(self):
        manga_server._raw_get = lambda url, timeout=30: (CHALLENGE, "text/html")
        manga_server._dl_worker("s1/Title", "ch1", "1", "Chapter 1", "Title", "")
        self.assertEqual(manga_server._dl_jobs["ch1"]["status"], "error")
        self.assertEqual(os.listdir(self._chapter_dir()), [])

    def test_a_challenge_page_is_never_saved_as_the_series_cover(self):
        jpeg = b"\xff\xd8\xff\xe0page"
        manga_server._raw_get = lambda url, timeout=30: (
            (jpeg, "image/jpeg") if url == self.CHAPTER_URL else (CHALLENGE, "text/html"))
        manga_server._dl_worker("s1/Title", "ch1", "1", "Chapter 1", "Title", self.COVER_URL)
        self.assertEqual(manga_server._dl_jobs["ch1"]["status"], "done")
        self.assertEqual(sorted(os.listdir(self._chapter_dir())), ["001.jpg", "meta.json"])
        self.assertFalse(os.path.exists(os.path.join(self.tmp, "s1", "cover.jpg")))


if __name__ == "__main__":
    unittest.main()
