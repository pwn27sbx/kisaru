"""Tests for in-flight image coalescing and background chapter page prefetch."""

import os
import sys
import tempfile
import threading
import time
import unittest
from urllib.parse import quote

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

try:
    import manga_server
    HAVE_SERVER = True
except Exception:  # noqa: BLE001 — curl_cffi/requests not installed
    HAVE_SERVER = False


WEBP = b"RIFF\x00\x00\x00\x00WEBPVP8 " + b"\x00" * 32
CHALLENGE = b"<!doctype html><html><title>Just a moment</title></html>"


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


def _proxied(raw_url):
    return "http://127.0.0.1:5150/image?url=" + quote(raw_url, safe="")


def _wait_until(predicate, timeout=3.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(0.01)
    return predicate()


@unittest.skipUnless(HAVE_SERVER, "manga_server needs curl_cffi/requests")
class InflightCoalescingTest(unittest.TestCase):
    def setUp(self):
        self.saved = (
            manga_server.proxy_target_allowed,
            manga_server.image_host_allowed,
            manga_server._proxy_fetch,
            manga_server._img_get,
            manga_server._img_put,
        )
        self.cache = {}
        manga_server.proxy_target_allowed = lambda url: True
        manga_server.image_host_allowed = lambda url: True
        manga_server._img_get = lambda url: self.cache.get(url)
        manga_server._img_put = lambda url, body, ctype: self.cache.__setitem__(url, (body, ctype))
        with manga_server._img_failed_lock:
            manga_server._img_failed.clear()
        with manga_server._img_host_lock:
            manga_server._img_host_down.clear()

    def tearDown(self):
        (
            manga_server.proxy_target_allowed,
            manga_server.image_host_allowed,
            manga_server._proxy_fetch,
            manga_server._img_get,
            manga_server._img_put,
        ) = self.saved
        with manga_server._img_failed_lock:
            manga_server._img_failed.clear()
        with manga_server._img_host_lock:
            manga_server._img_host_down.clear()

    def test_concurrent_requests_for_same_url_trigger_one_upstream_fetch(self):
        started = threading.Event()
        release = threading.Event()
        calls = []

        def fake_fetch(url):
            calls.append(url)
            started.set()
            release.wait(2.0)
            return WEBP, "image/webp"

        manga_server._proxy_fetch = fake_fetch
        url = "https://cdn.zonatmo.to/manga/x/p6.webp"
        h1, h2 = RecordingHandler(), RecordingHandler()
        t1 = threading.Thread(target=manga_server.proxy_image, args=(h1, url))
        t2 = threading.Thread(target=manga_server.proxy_image, args=(h2, url))
        t1.start()
        self.assertTrue(started.wait(1.0))
        t2.start()
        time.sleep(0.05)
        release.set()
        t1.join(2.0)
        t2.join(2.0)

        self.assertEqual(len(calls), 1)
        self.assertEqual(h1.responses, [200])
        self.assertEqual(h2.responses, [200])
        self.assertEqual(h1.body, WEBP)
        self.assertEqual(h2.body, WEBP)
        self.assertEqual(manga_server._img_inflight, {})

    def test_failed_leader_wakes_follower_with_attempts_and_cleans_inflight(self):
        started = threading.Event()
        release = threading.Event()
        calls = [0]

        def failing_fetch(url):
            calls[0] += 1
            manga_server._tls_image.attempts = 2
            started.set()
            release.wait(2.0)
            raise RuntimeError("boom")

        manga_server._proxy_fetch = failing_fetch
        url = "https://cdn.zonatmo.to/manga/x/fail.webp"
        h1, h2 = RecordingHandler(), RecordingHandler()
        with tempfile.TemporaryDirectory() as state:
            saved_state = os.environ.get("XDG_STATE_HOME")
            os.environ["XDG_STATE_HOME"] = state
            try:
                t1 = threading.Thread(target=manga_server.proxy_image, args=(h1, url))
                t2 = threading.Thread(target=manga_server.proxy_image, args=(h2, url))
                t1.start()
                self.assertTrue(started.wait(1.0))
                t2.start()
                time.sleep(0.05)
                release.set()
                t1.join(2.0)
                t2.join(2.0)
                with open(manga_server.image_failure_log_path(), encoding="utf-8") as fh:
                    lines = fh.read().splitlines()
            finally:
                if saved_state is None:
                    os.environ.pop("XDG_STATE_HOME", None)
                else:
                    os.environ["XDG_STATE_HOME"] = saved_state

        self.assertEqual(calls[0], 1)
        self.assertEqual(h1.errors, [502])
        self.assertEqual(h2.errors, [502])
        self.assertEqual(manga_server._img_inflight, {})
        self.assertEqual(len(lines), 2)
        for line in lines:
            self.assertIn("attempts=2", line)

    def test_non_image_response_logs_not_an_image_for_leader_and_follower(self):
        started = threading.Event()
        release = threading.Event()
        calls = [0]

        def html_fetch(url):
            calls[0] += 1
            started.set()
            release.wait(2.0)
            return CHALLENGE, "text/html"

        manga_server._proxy_fetch = html_fetch
        url = "https://cdn.zonatmo.to/manga/x/challenge.webp"
        h1, h2 = RecordingHandler(), RecordingHandler()
        with tempfile.TemporaryDirectory() as state:
            saved_state = os.environ.get("XDG_STATE_HOME")
            os.environ["XDG_STATE_HOME"] = state
            try:
                t1 = threading.Thread(target=manga_server.proxy_image, args=(h1, url))
                t2 = threading.Thread(target=manga_server.proxy_image, args=(h2, url))
                t1.start()
                self.assertTrue(started.wait(1.0))
                t2.start()
                time.sleep(0.05)
                release.set()
                t1.join(2.0)
                t2.join(2.0)
                with open(manga_server.image_failure_log_path(), encoding="utf-8") as fh:
                    lines = fh.read().splitlines()
            finally:
                if saved_state is None:
                    os.environ.pop("XDG_STATE_HOME", None)
                else:
                    os.environ["XDG_STATE_HOME"] = saved_state

        self.assertEqual(calls[0], 1)
        self.assertEqual(h1.errors, [502])
        self.assertEqual(h2.errors, [502])
        self.assertNotIn(url, self.cache)
        self.assertTrue(manga_server.img_host_down("cdn.zonatmo.to"))
        self.assertEqual(len(lines), 2)
        for line in lines:
            self.assertIn("path=not-an-image", line)

    def test_concurrent_requests_to_same_host_respect_per_host_limit(self):
        lock = threading.Lock()
        active = [0]
        peak = [0]

        def slow_fetch(url):
            with lock:
                active[0] += 1
                if active[0] > peak[0]:
                    peak[0] = active[0]
            time.sleep(0.05)
            with lock:
                active[0] -= 1
            return WEBP, "image/webp"

        manga_server._proxy_fetch = slow_fetch
        handlers = [RecordingHandler() for _ in range(5)]
        threads = [
            threading.Thread(
                target=manga_server.proxy_image,
                args=(handlers[i], f"https://cdn.zonatmo.to/manga/ch113/{i}.webp"),
            )
            for i in range(5)
        ]
        for t in threads:
            t.start()
        for t in threads:
            t.join(3.0)

        for h in handlers:
            self.assertEqual(h.responses, [200])
        self.assertLessEqual(peak[0], manga_server.IMAGE_HOST_CONCURRENCY)
        self.assertEqual(peak[0], manga_server.IMAGE_HOST_CONCURRENCY)


@unittest.skipUnless(HAVE_SERVER, "manga_server needs curl_cffi/requests")
class ChapterPrefetchTest(unittest.TestCase):
    def setUp(self):
        self.saved = (
            manga_server.proxy_target_allowed,
            manga_server.image_host_allowed,
            manga_server._proxy_fetch,
            manga_server._img_get,
            manga_server._img_put,
        )
        self.cache = {}
        self.cache_lock = threading.Lock()
        manga_server.proxy_target_allowed = lambda url: True
        manga_server.image_host_allowed = lambda url: True
        manga_server._img_get = lambda url: self.cache.get(url)
        manga_server._img_put = self._put
        with manga_server._img_failed_lock:
            manga_server._img_failed.clear()
        with manga_server._img_host_lock:
            manga_server._img_host_down.clear()

    def _put(self, url, body, ctype):
        with self.cache_lock:
            self.cache[url] = (body, ctype)

    def tearDown(self):
        try:
            manga_server._schedule_chapter_prefetch([])
        finally:
            (
                manga_server.proxy_target_allowed,
                manga_server.image_host_allowed,
                manga_server._proxy_fetch,
                manga_server._img_get,
                manga_server._img_put,
            ) = self.saved
            with manga_server._img_failed_lock:
                manga_server._img_failed.clear()
            with manga_server._img_host_lock:
                manga_server._img_host_down.clear()

    def test_extract_prefetch_urls_filters_offline_dedupes_and_caps(self):
        encoded = "https://cdn.zonatmo.to/manga/a%20b/1.webp"
        items = [
            {"page": 1, "img": "file:///tmp/offline/001.webp"},
            {"page": 2, "img": _proxied(encoded)},
            {"page": 3, "img": _proxied(encoded)},
            {"page": 4, "img": ""},
        ] + [
            {"page": i, "img": _proxied(f"https://cdn.zonatmo.to/manga/x/{i}.webp")}
            for i in range(5, 35)
        ]
        urls = manga_server._extract_prefetch_urls(items)
        self.assertEqual(urls[0], "https://cdn.zonatmo.to/manga/a b/1.webp")
        self.assertEqual(len(urls), len(set(urls)))
        self.assertLessEqual(len(urls), manga_server.PREFETCH_MAX_PAGES)

    def test_schedule_prefetches_uncached_pages_into_cache(self):
        u1 = "https://cdn.zonatmo.to/manga/x/1.webp"
        u2 = "https://cdn.zonatmo.to/manga/x/2.webp"
        u3 = "https://cdn.zonatmo.to/manga/x/3.webp"
        self.cache[u1] = (WEBP, "image/webp")
        fetched = []
        lock = threading.Lock()

        def fake_fetch(url):
            with lock:
                fetched.append(url)
            return WEBP, "image/webp"

        manga_server._proxy_fetch = fake_fetch
        manga_server._schedule_chapter_prefetch([
            {"page": 1, "img": _proxied(u1)},
            {"page": 2, "img": _proxied(u2)},
            {"page": 3, "img": _proxied(u3)},
        ])
        self.assertTrue(_wait_until(lambda: u2 in self.cache and u3 in self.cache))
        self.assertEqual(sorted(fetched), [u2, u3])

    def test_new_chapter_cancels_previous_chapter_queue(self):
        gate = threading.Event()
        first_started = threading.Event()
        fetched = []
        lock = threading.Lock()

        def fake_fetch(url):
            with lock:
                fetched.append(url)
            if "/chA/" in url:
                first_started.set()
                gate.wait(2.0)
            return WEBP, "image/webp"

        manga_server._proxy_fetch = fake_fetch
        ch_a = [{"page": i, "img": _proxied(f"https://cdn.zonatmo.to/chA/{i}.webp")} for i in range(1, 10)]
        ch_b = [{"page": i, "img": _proxied(f"https://cdn.zonatmo.to/chB/{i}.webp")} for i in range(1, 3)]

        manga_server._schedule_chapter_prefetch(ch_a)
        self.assertTrue(first_started.wait(1.0))
        manga_server._schedule_chapter_prefetch(ch_b)
        gate.set()

        self.assertTrue(_wait_until(lambda: "https://cdn.zonatmo.to/chB/2.webp" in self.cache))
        ch_a_hits = [u for u in fetched if "/chA/" in u]
        self.assertLessEqual(len(ch_a_hits), manga_server.PREFETCH_WORKERS)

    def test_rate_limit_status_aborts_remaining_prefetch_for_generation(self):
        class RateLimited(Exception):
            class response:
                status_code = 429

        fetched = []
        lock = threading.Lock()

        def fake_fetch(url):
            with lock:
                fetched.append(url)
            raise RateLimited()

        manga_server._proxy_fetch = fake_fetch
        pages = [{"page": i, "img": _proxied(f"https://cdn.zonatmo.to/rl/{i}.webp")} for i in range(1, 12)]
        manga_server._schedule_chapter_prefetch(pages)
        time.sleep(0.2)
        self.assertLessEqual(len(fetched), manga_server.PREFETCH_WORKERS)


if __name__ == "__main__":
    unittest.main()
