"""Every image failure in /image leaves one bounded, private log line.

The owner saw page 8 of a chapter fail with a Bad Gateway, and the backend had
logged nothing (its stdout is not captured), so the upstream answer was lost.
`proxy_image` now appends one line per failure to
`$XDG_STATE_HOME/kisaru/image-failures.log`, keeping the last 200.

A line holds only the time, the image host, the failure path, the exception
class with its curl code or the HTTP status, the attempts and the elapsed time:
never a URL, a title, a chapter or a page. Writing the log never raises and
never changes the response.

Run from the repo root:
    python3 -m unittest tests.test_image_failure_log
"""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

try:
    import manga_server
    HAVE_SERVER = True
except Exception:  # noqa: BLE001 — curl_cffi/requests not installed
    HAVE_SERVER = False

SECRET_URL = "https://cdn.zonatmo.to/manga/secret-title/capitulo-106/page-08.webp?token=abc123"


class Answer:
    def __init__(self, status_code):
        self.status_code = status_code


class CurlTimeout(Exception):
    """Shaped like curl_cffi's Timeout, with the URL in its message."""

    def __init__(self):
        super().__init__("Failed to perform, curl: (28) Operation timed out " + SECRET_URL)
        self.code = 28
        self.response = Answer(0)


class Refused(Exception):
    def __init__(self, status):
        super().__init__("HTTP Error %d: %s" % (status, SECRET_URL))
        self.response = Answer(status)


class Handler:
    def __init__(self):
        self.errors = []

    def send_error(self, code, message=None):
        self.errors.append(code)


@unittest.skipUnless(HAVE_SERVER, "manga_server needs curl_cffi/requests")
class FailureLogTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.saved_env = os.environ.get("XDG_STATE_HOME")
        os.environ["XDG_STATE_HOME"] = self.tmp.name
        self.saved = (manga_server._proxy_fetch, manga_server._send_image,
                      manga_server._img_get, manga_server._img_put)
        manga_server._img_get = lambda url: None
        manga_server._img_put = lambda url, body, ctype: None
        manga_server._send_image = lambda handler, body, ctype: handler.errors.append(200)
        with manga_server._img_failed_lock:
            manga_server._img_failed.clear()
        with manga_server._img_host_lock:
            manga_server._img_host_down.clear()

    def tearDown(self):
        (manga_server._proxy_fetch, manga_server._send_image,
         manga_server._img_get, manga_server._img_put) = self.saved
        with manga_server._img_failed_lock:
            manga_server._img_failed.clear()
        with manga_server._img_host_lock:
            manga_server._img_host_down.clear()
        if self.saved_env is None:
            os.environ.pop("XDG_STATE_HOME", None)
        else:
            os.environ["XDG_STATE_HOME"] = self.saved_env
        self.tmp.cleanup()

    def lines(self):
        path = manga_server.image_failure_log_path()
        if not os.path.exists(path):
            return []
        with open(path, encoding="utf-8") as fh:
            return fh.read().splitlines()

    def fetch_raises(self, error):
        def fake(url):
            raise error
        manga_server._proxy_fetch = fake

    def serve(self, url=SECRET_URL, chapter=None, page=None):
        handler = Handler()
        manga_server.proxy_image(handler, url, chapter, page)
        return handler

    def assert_private(self, line):
        for secret in ("secret-title", "capitulo", "page-08", "token", "abc123", "http", "/"):
            self.assertNotIn(secret, line)

    def test_the_log_lives_in_the_xdg_state_home(self):
        self.assertEqual(manga_server.image_failure_log_path(),
                         os.path.join(self.tmp.name, "kisaru", "image-failures.log"))

    def test_a_stall_logs_its_class_curl_code_attempts_and_time(self):
        self.fetch_raises(CurlTimeout())
        handler = self.serve()
        self.assertEqual(handler.errors, [502])
        lines = self.lines()
        self.assertEqual(len(lines), 1)
        fields = lines[0].split(" ")
        self.assertRegex(fields[0], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d")
        self.assertEqual(fields[1:5], ["host=cdn.zonatmo.to", "path=exception",
                                       "error=CurlTimeout", "curl=28"])
        self.assertRegex(fields[5], r"^attempts=\d+$")
        self.assertRegex(fields[6], r"^elapsed=\d+\.\d\ds$")
        self.assertEqual(len(fields), 7)
        self.assert_private(lines[0])

    def test_an_upstream_status_is_logged_without_its_message(self):
        self.fetch_raises(Refused(503))
        handler = self.serve()
        self.assertEqual(handler.errors, [502])
        line = self.lines()[0]
        self.assertIn(" path=exception error=Refused status=503 ", line)
        self.assert_private(line)

    def test_a_blocked_address_is_logged(self):
        self.fetch_raises(manga_server.ProxyBlocked(SECRET_URL))
        handler = self.serve()
        self.assertEqual(handler.errors, [403])
        line = self.lines()[0]
        self.assertIn(" path=blocked-403 ", line)
        self.assert_private(line)

    def test_a_page_that_is_not_an_image_is_logged(self):
        manga_server._proxy_fetch = lambda url: (b"<html>check</html>", "text/html")
        handler = self.serve()
        self.assertEqual(handler.errors, [502])
        line = self.lines()[0]
        self.assertIn(" path=not-an-image ", line)
        self.assertIn(" attempts=", line)
        self.assert_private(line)

    def test_the_failure_windows_are_logged_with_no_attempt(self):
        # A retry inside the windows costs nothing upstream (A12), and says so.
        manga_server.img_mark_failed(SECRET_URL)
        self.assertEqual(self.serve().errors, [502])
        with manga_server._img_failed_lock:
            manga_server._img_failed.clear()
        manga_server.img_mark_host_down("cdn.zonatmo.to")
        self.assertEqual(self.serve().errors, [502])
        lines = self.lines()
        self.assertEqual(len(lines), 2)
        self.assertIn(" path=img_blocked-502 attempts=0 ", lines[0])
        self.assertIn(" path=host_down-502 attempts=0 ", lines[1])
        for line in lines:
            self.assert_private(line)

    def test_a_served_image_logs_nothing(self):
        manga_server._proxy_fetch = lambda url: (b"RIFF\x00\x00\x00\x00WEBPVP8 ", "image/webp")
        self.assertEqual(self.serve().errors, [200])
        self.assertEqual(self.lines(), [])

    def test_the_log_keeps_only_the_last_200_lines(self):
        for i in range(205):
            manga_server.log_image_failure("cdn%d.example" % i, "exception", attempts=1)
        lines = self.lines()
        self.assertEqual(len(lines), 200)
        self.assertIn(" host=cdn5.example ", lines[0])
        self.assertIn(" host=cdn204.example ", lines[-1])

    def test_a_host_is_reduced_to_host_characters(self):
        manga_server.log_image_failure("evil.example\nforged line /x?y", "exception")
        lines = self.lines()
        self.assertEqual(len(lines), 1)
        self.assertIn(" host=evil.exampleforgedlinexy ", lines[0])

    def test_an_unwritable_log_never_breaks_the_response(self):
        # The state home is a file: the directory cannot be created.
        blocker = os.path.join(self.tmp.name, "file")
        with open(blocker, "w") as fh:
            fh.write("x")
        os.environ["XDG_STATE_HOME"] = blocker
        self.fetch_raises(CurlTimeout())
        self.assertEqual(self.serve().errors, [502])
        manga_server.log_image_failure("cdn.example", "exception")


if __name__ == "__main__":
    unittest.main()
