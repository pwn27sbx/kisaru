"""The image proxy only fetches public addresses.

`/image?url=` used to fetch any http(s) URL, so a page could make the backend
request loopback or LAN addresses (audit 2026-11-06, finding 18). The local
guard also fails closed now: a missing Host is refused, and an opaque
`Origin: null` (a sandboxed iframe) is refused instead of passing as "not an
http origin" (review advisories R1-local-only-origin-bypass and
R1-missing-host-open).

Run from the repo root:
    python3 -m unittest tests.test_proxy_policy
"""

import http.client
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from urllib.parse import urlparse

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "scripts"))

try:
    import manga_server
    import proxy_policy
    HAVE_SERVER = True
except Exception:  # noqa: BLE001 — curl_cffi/requests not installed
    HAVE_SERVER = False

import local_only


def public_resolver(host, port):
    return ["93.184.216.34"]


def private_resolver(host, port):
    return ["10.0.0.7"]


class ProxyTargetPolicyTest(unittest.TestCase):
    def test_a_public_http_target_is_allowed(self):
        self.assertTrue(proxy_policy.proxy_target_allowed(
            "https://cdn.example/cover.jpg", resolver=public_resolver))

    def test_loopback_and_private_literals_are_refused(self):
        for url in ("http://127.0.0.1:5150/x.jpg",
                    "http://localhost/x.jpg",
                    "http://[::1]/x.jpg",
                    "http://10.0.0.5/x.jpg",
                    "http://192.168.1.2/x.jpg",
                    "http://169.254.169.254/latest/meta-data",
                    "http://0.0.0.0/x.jpg"):
            self.assertFalse(proxy_policy.proxy_target_allowed(url, resolver=public_resolver), url)

    def test_a_name_that_resolves_to_a_private_address_is_refused(self):
        self.assertFalse(proxy_policy.proxy_target_allowed(
            "https://rebind.example/x.jpg", resolver=private_resolver))

    def test_a_name_that_does_not_resolve_is_refused(self):
        def broken(host, port):
            raise OSError("no dns")

        self.assertFalse(proxy_policy.proxy_target_allowed(
            "https://gone.example/x.jpg", resolver=broken))

    def test_non_http_schemes_are_refused(self):
        for url in ("file:///etc/passwd", "ftp://cdn.example/x.jpg",
                    "data:image/jpeg;base64,AAAA", "//cdn.example/x.jpg"):
            self.assertFalse(proxy_policy.proxy_target_allowed(url, resolver=public_resolver), url)

    def test_the_default_resolver_refuses_a_loopback_literal(self):
        self.assertFalse(proxy_policy.proxy_target_allowed("http://127.0.0.1:5150/"))


class LocalGuardTest(unittest.TestCase):
    def test_a_missing_host_is_refused(self):
        self.assertFalse(local_only.is_loopback_host(None))
        self.assertFalse(local_only.is_loopback_host(""))

    def test_a_loopback_host_is_allowed(self):
        for value in ("127.0.0.1:5150", "localhost:5151", "[::1]:5150"):
            self.assertTrue(local_only.is_loopback_host(value), value)

    def test_an_opaque_null_origin_is_refused(self):
        self.assertFalse(local_only.is_allowed_origin("null"))

    def test_a_missing_origin_is_allowed_for_qml(self):
        self.assertTrue(local_only.is_allowed_origin(None))

    def test_a_foreign_http_origin_is_refused(self):
        self.assertFalse(local_only.is_allowed_origin("https://evil.example"))

    def test_a_loopback_origin_is_allowed(self):
        self.assertTrue(local_only.is_allowed_origin("http://127.0.0.1:5150"))


class RecordingHandler:
    def __init__(self):
        self.errors = []
        self.responses = []

        class _Wfile:
            def write(self, data):
                pass

        self.wfile = _Wfile()

    def send_response(self, code, *a, **k):
        self.responses.append(code)

    def send_header(self, *a, **k):
        pass

    def end_headers(self):
        pass

    def send_error(self, code, *a, **k):
        self.errors.append(code)


class _Response:
    def __init__(self, status_code, headers=None, content=b"\xff\xd8\xff", ctype="image/jpeg"):
        self.status_code = status_code
        self.headers = headers or {}
        self.content = content
        self._ctype = ctype

    def raise_for_status(self):
        if self.status_code >= 400:
            raise RuntimeError("HTTP %d" % self.status_code)

    def header(self, name):
        return self._ctype


@unittest.skipUnless(HAVE_SERVER, "manga_server needs curl_cffi/requests")
class MangaProxyGuardTest(unittest.TestCase):
    def setUp(self):
        self.original_policy = manga_server.proxy_target_allowed
        self.original_get = manga_server._get
        self.original_plain = manga_server._plain_get

    def tearDown(self):
        manga_server.proxy_target_allowed = self.original_policy
        manga_server._get = self.original_get
        manga_server._plain_get = self.original_plain

    def test_the_route_answers_403_for_a_private_target(self):
        manga_server.proxy_target_allowed = lambda url: False
        handler = RecordingHandler()
        manga_server.proxy_image(handler, "http://127.0.0.1:5150/secret")
        self.assertEqual(handler.errors, [403])

    def test_a_redirect_to_a_private_target_is_refused(self):
        seen = []

        def parser(url):
            return False

        manga_server.proxy_target_allowed = lambda url: urlparse(url).hostname != "127.0.0.1"

        def fake_get(url, headers, timeout, follow=True):
            seen.append(url)
            return _Response(302, {"Location": "http://127.0.0.1:5150/secret"})

        manga_server._get = fake_get
        manga_server._plain_get = fake_get

        with self.assertRaises(manga_server.ProxyBlocked):
            manga_server._proxy_fetch("https://cdn.example/x.jpg")
        self.assertEqual(len(seen), 1)

    def test_a_public_redirect_is_followed(self):
        calls = []

        def fake_get(url, headers, timeout, follow=True):
            calls.append((url, follow))
            if len(calls) == 1:
                return _Response(301, {"Location": "https://cdn2.example/x.jpg"})
            return _Response(200)

        manga_server.proxy_target_allowed = lambda url: True
        manga_server._get = fake_get
        manga_server._plain_get = fake_get

        body, ctype = manga_server._proxy_fetch("https://cdn.example/x.jpg")
        self.assertEqual(body, b"\xff\xd8\xff")
        self.assertEqual(ctype, "image/jpeg")
        self.assertEqual([url for url, _ in calls],
                         ["https://cdn.example/x.jpg", "https://cdn2.example/x.jpg"])
        self.assertTrue(all(follow is False for _, follow in calls))


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def request(port, method, path, body=None, headers=None):
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    try:
        conn.request(method, path, body=body, headers=headers or {})
        response = conn.getresponse()
        return response.status, response.read()
    finally:
        conn.close()


class NovelProxyGuardTest(unittest.TestCase):
    """Runs the real entry point; the check must be reachable from /image."""

    @classmethod
    def setUpClass(cls):
        cls.port = free_port()
        cls.log = tempfile.TemporaryFile()
        cls.process = subprocess.Popen(
            [sys.executable, os.path.join("scripts", "novel_server", "main.py"),
             "--port", str(cls.port)],
            cwd=ROOT, stdout=cls.log, stderr=subprocess.STDOUT,
        )
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            if cls.process.poll() is not None:
                cls.log.seek(0)
                raise AssertionError(cls.log.read().decode("utf-8", "replace")[-1500:])
            try:
                status, _ = request(cls.port, "GET", "/health")
            except OSError:
                time.sleep(0.2)
                continue
            if status == 200:
                return
        raise AssertionError("the novel backend did not answer /health")

    @classmethod
    def tearDownClass(cls):
        cls.process.terminate()
        try:
            cls.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            cls.process.kill()
            cls.process.wait(timeout=10)
        cls.log.close()

    def test_the_route_answers_403_for_a_private_target(self):
        status, _ = request(self.port, "GET", "/image?url=http%3A%2F%2F127.0.0.1%3A1%2Fsecret")
        self.assertEqual(status, 403)

    def test_a_non_json_post_is_refused(self):
        status, _ = request(self.port, "POST", "/favorites/remove",
                            body="id=1", headers={"Content-Type": "text/plain"})
        self.assertEqual(status, 403)

    def test_a_json_post_reaches_the_route(self):
        status, _ = request(self.port, "POST", "/favorites/remove",
                            body=json.dumps({}),
                            headers={"Content-Type": "application/json"})
        self.assertEqual(status, 400, "the request must reach the route")


if __name__ == "__main__":
    unittest.main()
