"""Page images are cut by silence, never by a timer on the whole transfer.

curl_cffi's `timeout` bounded the whole transfer, so a page that was still
trickling in was cut at 30 s and the retry started from zero (page 12 of a
ZonaTMO chapter took 27 s in one attempt on 2026-11-17). The image session
now sets LOW_SPEED_LIMIT 1 byte/s for LOW_SPEED_TIME seconds: a body that keeps
sending is never cut, a body that goes silent is cut and retried once, and a
refusal is answered once.

These tests talk to a local socket server, never the network. The stall time
is scaled down to STALL seconds through `IMAGE_STALL_SECONDS`, so the trickle
lasts more than two stall windows (a whole-transfer cap of that size would cut it)
and the suite stays fast.

Run from the repo root:
    python3 -m unittest tests.test_image_stall
"""

import os
import socket
import sys
import tempfile
import threading
import time
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

try:
    import manga_server
    HAVE_CFFI = manga_server._USE_CFFI
except Exception:  # noqa: BLE001 — curl_cffi/requests not installed
    HAVE_CFFI = False

STALL = 2
WEBP = b"RIFF\x00\x00\x00\x00WEBPVP8 "


class Upstream:
    """A local HTTP server; each connection is answered by the next behaviour.

    A behaviour is a function taking the accepted socket. The last one repeats.
    """

    def __init__(self, *behaviours):
        self.behaviours = list(behaviours)
        self.hits = 0
        self.sock = socket.socket()
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("127.0.0.1", 0))
        self.sock.listen(8)
        self.port = self.sock.getsockname()[1]
        self.open = []
        threading.Thread(target=self._loop, daemon=True).start()

    def url(self, path="/p.webp"):
        return "http://127.0.0.1:%d%s" % (self.port, path)

    def _loop(self):
        while True:
            try:
                conn, _ = self.sock.accept()
            except OSError:
                return
            self.open.append(conn)
            behaviour = self.behaviours[min(self.hits, len(self.behaviours) - 1)]
            self.hits += 1
            threading.Thread(target=self._serve, args=(conn, behaviour), daemon=True).start()

    @staticmethod
    def _serve(conn, behaviour):
        try:
            conn.recv(65536)
            behaviour(conn)
        except OSError:
            pass

    def close(self):
        self.sock.close()
        for conn in self.open:
            try:
                conn.close()
            except OSError:
                pass


def headers(length, status="200 OK", ctype="image/webp"):
    return ("HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\n"
            "Connection: close\r\n\r\n" % (status, ctype, length)).encode()


def answer(conn):
    conn.sendall(headers(len(WEBP)) + WEBP)
    conn.close()


def trickle(seconds, every=0.25, chunk=4096):
    """Send a WEBP body a little at a time for about `seconds`.

    Default rate is 16 KB/s (above IMAGE_LOW_SPEED_LIMIT = 8 KB/s) so a
    genuinely slow transfer is never cut.
    """
    count = int(seconds / every)
    body = WEBP + b"x" * (count * chunk)

    def behaviour(conn):
        conn.sendall(headers(len(body)) + body[:len(WEBP)])
        rest = body[len(WEBP):]
        for i in range(count):
            time.sleep(every)
            conn.sendall(rest[i * chunk:(i + 1) * chunk])
        conn.close()
    behaviour.length = len(body)
    return behaviour


def silent_after_headers(conn):
    conn.sendall(headers(len(WEBP) * 4) + WEBP)
    time.sleep(STALL * 5)


def silent_before_headers(conn):
    time.sleep(STALL * 5)


def refuse(conn):
    conn.sendall(headers(0, status="403 Forbidden", ctype="text/html"))
    conn.close()


@unittest.skipUnless(HAVE_CFFI, "the stall rule needs curl_cffi")
class StallTest(unittest.TestCase):
    def setUp(self):
        self.saved = (manga_server.IMAGE_STALL_SECONDS, manga_server.proxy_target_allowed,
                      manga_server.image_host_allowed)
        manga_server.IMAGE_STALL_SECONDS = STALL
        manga_server._tls_image.session = None
        # The local server is loopback, which the proxy refuses on purpose.
        manga_server.proxy_target_allowed = lambda url: True
        manga_server.image_host_allowed = lambda url: True
        self.servers = []

    def tearDown(self):
        (manga_server.IMAGE_STALL_SECONDS, manga_server.proxy_target_allowed,
         manga_server.image_host_allowed) = self.saved
        manga_server._tls_image.session = None
        for server in self.servers:
            server.close()

    def upstream(self, *behaviours):
        server = Upstream(*behaviours)
        self.servers.append(server)
        return server

    def test_a_body_that_keeps_trickling_is_never_cut(self):
        slow = trickle(STALL * 2.5)
        server = self.upstream(slow)
        start = time.monotonic()
        body, ctype = manga_server._proxy_fetch(server.url())
        elapsed = time.monotonic() - start
        self.assertEqual(len(body), slow.length)
        self.assertEqual(server.hits, 1)
        # It lasted longer than the stall window: only silence is cut.
        self.assertGreater(elapsed, STALL * 2)

    def test_a_zombie_trickle_below_low_speed_limit_is_cut_and_retried_once(self):
        zombie = trickle(STALL * 5, every=0.25, chunk=256)  # 1 KB/s < 8 KB/s
        server = self.upstream(zombie, answer)
        start = time.monotonic()
        body, _ = manga_server._proxy_fetch(server.url())
        elapsed = time.monotonic() - start
        self.assertEqual(body, WEBP)
        self.assertEqual(server.hits, 2)
        self.assertGreaterEqual(elapsed, STALL - 0.5)
        self.assertLess(elapsed, STALL * 4)

    def test_a_body_that_goes_silent_is_cut_and_retried_once(self):
        server = self.upstream(silent_after_headers, answer)
        start = time.monotonic()
        body, _ = manga_server._proxy_fetch(server.url())
        elapsed = time.monotonic() - start
        self.assertEqual(body, WEBP)
        self.assertEqual(server.hits, 2)
        self.assertGreaterEqual(elapsed, STALL - 0.5)
        # curl averages the current speed over its last ~5 s of samples, so the
        # bytes that came before the silence keep it above 1 byte/s for up to
        # ~6 s: a body that goes silent is cut within STALL + 6 s.
        self.assertLess(elapsed, STALL + 9)

    def test_a_request_with_no_answer_at_all_is_cut_and_retried_once(self):
        server = self.upstream(silent_before_headers, answer)
        start = time.monotonic()
        body, _ = manga_server._proxy_fetch(server.url())
        elapsed = time.monotonic() - start
        self.assertEqual(body, WEBP)
        self.assertEqual(server.hits, 2)
        self.assertLess(elapsed, STALL * 4)

    def test_two_silences_give_up_after_two_requests(self):
        server = self.upstream(silent_before_headers)
        with self.assertRaises(Exception) as caught:
            manga_server._proxy_fetch(server.url())
        self.assertEqual(server.hits, 2)
        self.assertEqual(getattr(caught.exception, "code", None), 28)

    def test_a_refusal_is_answered_once(self):
        server = self.upstream(refuse)
        with self.assertRaises(Exception) as caught:
            manga_server._proxy_fetch(server.url())
        self.assertEqual(caught.exception.response.status_code, 403)
        self.assertEqual(server.hits, 1)

    def test_a_chapter_download_page_trickling_is_never_cut(self):
        slow = trickle(STALL * 2.5)
        server = self.upstream(slow)
        body, _ = manga_server._raw_get(server.url())
        self.assertEqual(len(body), slow.length)
        self.assertEqual(server.hits, 1)

    def test_a_stalled_page_is_logged_with_its_curl_code_and_attempts(self):
        server = self.upstream(silent_before_headers)
        with tempfile.TemporaryDirectory() as state:
            saved = os.environ.get("XDG_STATE_HOME")
            os.environ["XDG_STATE_HOME"] = state
            try:
                handler = Handler()
                manga_server.proxy_image(handler, server.url("/stalled.webp"))
                with open(manga_server.image_failure_log_path(), encoding="utf-8") as fh:
                    lines = fh.read().splitlines()
            finally:
                if saved is None:
                    os.environ.pop("XDG_STATE_HOME", None)
                else:
                    os.environ["XDG_STATE_HOME"] = saved
        self.assertEqual(handler.errors, [502])
        self.assertEqual(len(lines), 1)
        line = lines[0]
        self.assertIn(" host=127.0.0.1 ", line)
        self.assertIn(" path=exception ", line)
        self.assertIn(" curl=28 ", line)
        self.assertIn(" attempts=2 ", line)
        self.assertNotIn("stalled", line)
        self.assertNotIn("http", line)


class Handler:
    def __init__(self):
        self.errors = []

    def send_error(self, code, message=None):
        self.errors.append(code)


if __name__ == "__main__":
    unittest.main()
