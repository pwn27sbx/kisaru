"""A stalled image request is retried once; a refusal never is.

curl_cffi raises its Timeout with a placeholder response attached (status 0),
so `_get` and `_plain_get` took every timeout for an upstream answer and
re-raised without the retry their docstrings promise. A chapter whose CDN
stalled on one page then waited 30 s and showed the page as failed, although a
second request loaded it in under a second (2026-11-17, ZonaTMO).

The retry stays narrow so the scraper never looks more like a bot than it did:
one extra request, only when the transfer stalled or the connection dropped.
A refusal (403, 429, 5xx, a browser check) is never asked twice.

Run from the repo root:
    python3 -m unittest tests.test_image_retry
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


class Answer:
    """A response object as an exception carries it."""

    def __init__(self, status_code):
        self.status_code = status_code


class Stalled(Exception):
    """curl_cffi's Timeout: a placeholder response with status 0."""

    def __init__(self):
        super().__init__("Operation timed out")
        self.response = Answer(0)


class Dropped(Exception):
    """A connection error with no response at all (requests' style)."""

    def __init__(self):
        super().__init__("Connection reset")
        self.response = None


class MidBody(Exception):
    """curl_cffi's Timeout after the status line: the real status is kept."""

    def __init__(self):
        super().__init__("Operation timed out after the headers")
        self.response = Answer(200)


class Refused(Exception):
    """An HTTP error the upstream actually sent."""

    def __init__(self, status):
        super().__init__("HTTP %d" % status)
        self.response = Answer(status)


class Ok:
    status_code = 200
    headers = {"Content-Type": "image/webp"}
    content = b"RIFF0000WEBP"

    def raise_for_status(self):
        return None


class Status:
    """A plain response with a refusal status, as the sessions return it."""

    def __init__(self, status):
        self.status_code = status
        self.headers = {"Content-Type": "text/html"}
        self.content = b"<html>no</html>"

    def raise_for_status(self):
        raise Refused(self.status_code)


class FakeSession:
    """Raises the queued errors in order, then answers Ok (or `answer`)."""

    def __init__(self, errors, log, answer=None):
        self.errors = errors
        self.log = log
        self.answer = answer

    def get(self, url, headers=None, timeout=None, allow_redirects=True, **kwargs):
        self.log.append(timeout)
        if self.errors:
            raise self.errors.pop(0)
        return Status(self.answer) if self.answer else Ok()


@unittest.skipUnless(HAVE_SERVER, "manga_server needs curl_cffi/requests")
class RetryTest(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self.original = (manga_server._session, manga_server._plain_session,
                         manga_server._image_session)

    def tearDown(self):
        (manga_server._session, manga_server._plain_session,
         manga_server._image_session) = self.original

    def use(self, errors, answer=None):
        session = FakeSession(list(errors), self.calls, answer)
        manga_server._session = lambda: session
        manga_server._plain_session = lambda: session
        manga_server._image_session = lambda: session

    def test_a_stalled_request_is_retried_once(self):
        self.use([Stalled()])
        r = manga_server._get("https://cdn.example/p.webp", {}, 15)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(len(self.calls), 2)

    def test_a_stalled_plain_request_is_retried_once(self):
        self.use([Stalled()])
        r = manga_server._plain_get("https://uploads.mangadex.org/p.png", {}, 15)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(len(self.calls), 2)

    def test_a_dropped_connection_is_still_retried_once(self):
        self.use([Dropped()])
        r = manga_server._get("https://cdn.example/p.webp", {}, 15)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(len(self.calls), 2)

    def test_two_stalls_give_up_after_two_requests(self):
        self.use([Stalled(), Stalled()])
        with self.assertRaises(Stalled):
            manga_server._get("https://cdn.example/p.webp", {}, 15)
        self.assertEqual(len(self.calls), 2)

    def test_an_upstream_refusal_is_never_retried(self):
        for status in (403, 404, 429, 503):
            for get in (manga_server._get, manga_server._plain_get):
                with self.subTest(status=status, get=get.__name__):
                    self.calls.clear()
                    self.use([Refused(status)])
                    with self.assertRaises(Refused):
                        get("https://cdn.example/p.webp", {}, 15)
                    self.assertEqual(len(self.calls), 1)

    def test_a_body_that_stalls_mid_transfer_is_retried_once(self):
        # curl_cffi's whole-transfer timeout keeps the status it already read.
        self.use([MidBody()])
        r = manga_server._get("https://cdn.example/p.webp", {}, 30)
        self.assertEqual(r.status_code, 200)
        self.assertEqual(len(self.calls), 2)

    def test_a_refusal_response_is_returned_after_one_request(self):
        # The sessions do not raise for 4xx/5xx: the refusal comes back as a
        # response and the proxy raises it after a single request.
        for status in (403, 429, 503):
            with self.subTest(status=status):
                self.calls.clear()
                self.use([], answer=status)
                original_allowed = manga_server.image_host_allowed
                manga_server.image_host_allowed = lambda url: True
                try:
                    with self.assertRaises(Exception):
                        manga_server._proxy_fetch("https://cdn.zonatmo.to/manga/x/p.webp")
                finally:
                    manga_server.image_host_allowed = original_allowed
                self.assertEqual(len(self.calls), 1)

    def proxy(self, url):
        original_allowed = manga_server.image_host_allowed
        manga_server.image_host_allowed = lambda url: True
        try:
            return manga_server._proxy_fetch(url)
        finally:
            manga_server.image_host_allowed = original_allowed

    @unittest.skipUnless(HAVE_SERVER and manga_server._USE_CFFI, "needs curl_cffi")
    def test_page_images_are_cut_by_silence_not_by_a_whole_transfer_cap(self):
        # A whole-transfer timeout cut a page that was still arriving (27 s for
        # one page of chapter 106). The image session cuts only silence:
        # LOW_SPEED_TIME on the session, a 10 s connect limit and a 120 s total
        # backstop on the call.
        self.use([])
        body, ctype = self.proxy("https://cdn.zonatmo.to/manga/x/p.webp")
        self.assertEqual(body, Ok.content)
        self.assertEqual(self.calls, [(10, 110)])
        manga_server._image_session = self.original[2]
        manga_server._tls_image.session = None
        options = manga_server._image_session().curl_options
        from curl_cffi.const import CurlOpt
        self.assertEqual(options[CurlOpt.LOW_SPEED_LIMIT], 1)
        self.assertEqual(options[CurlOpt.LOW_SPEED_TIME], 15)
        manga_server._tls_image.session = None

    def test_mangadex_pages_wait_for_silence_per_read(self):
        # requests' read timeout is already per read, so (10, 15) is the same
        # rule: 10 s to connect, cut after 15 s without a byte.
        self.use([])
        self.proxy("https://uploads.mangadex.org/data/h/p.png")
        self.assertEqual(self.calls, [(10, 15)])

    def test_the_requests_fallback_uses_a_per_read_timeout(self):
        saved = manga_server._USE_CFFI
        manga_server._USE_CFFI = False
        try:
            self.assertEqual(manga_server._image_timeout(), (10, 15))
        finally:
            manga_server._USE_CFFI = saved

    def test_an_image_stall_is_retried_once_and_a_refusal_never(self):
        self.use([Stalled()])
        self.assertEqual(manga_server._image_get("https://cdn.example/p.webp", {}).status_code, 200)
        self.assertEqual(len(self.calls), 2)
        self.calls.clear()
        self.use([Stalled(), MidBody()])
        with self.assertRaises(MidBody):
            manga_server._image_get("https://cdn.example/p.webp", {})
        self.assertEqual(len(self.calls), 2)
        for status in (403, 429, 503):
            with self.subTest(status=status):
                self.calls.clear()
                self.use([Refused(status)])
                with self.assertRaises(Refused):
                    manga_server._image_get("https://cdn.example/p.webp", {})
                self.assertEqual(len(self.calls), 1)

    def test_chapter_downloads_use_the_image_session_and_covers_keep_15_s(self):
        # A downloaded page is the same transfer as a read page. A cover keeps
        # its whole 15 s cap on the scraper session (amendment A8): it is small,
        # and the panel would rather show a placeholder than wait.
        scraper, image = [], []
        manga_server._session = lambda: FakeSession([], scraper)
        manga_server._image_session = lambda: FakeSession([], image)
        manga_server._raw_get("https://cdn.zonatmo.to/manga/x/p.webp")
        manga_server._raw_get("https://cdn.zonatmo.to/cover.jpg", timeout=15)
        self.assertEqual(image, [manga_server._image_timeout()])
        self.assertEqual(scraper, [15])


if __name__ == "__main__":
    unittest.main()
