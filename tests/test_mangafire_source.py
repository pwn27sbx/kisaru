"""Tests for scripts/mangafire_source.py using recorded mangafire.to fixtures.

Run from the repo root:
    python3 -m unittest discover -s tests -p "test_*.py"

Fixtures under tests/fixtures/mangafire/ were captured from the live API
(search, title detail, chapter list and reader pages) with a valid `vrf`
signature; the tests never touch the network.

The signature is the whole reason this source works: mangafire.to answers
`{"message": "Missing token."}` to any /api call without a `vrf` parameter
derived from the query string. The algorithm is ported from the Mihon extension
(keiyoushi/extensions-source, VrfSigner.kt) and pinned here with a golden
value captured from a live 200.
"""

import io
import json
import os
import sys
import unittest
import urllib.error
import urllib.parse

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

import mangafire_source  # noqa: E402

FIX = os.path.join(os.path.dirname(__file__), "fixtures", "mangafire")


def load_json(name):
    with open(os.path.join(FIX, name), encoding="utf-8") as handle:
        return json.load(handle)


class SignatureTest(unittest.TestCase):
    """The vrf signature and the canonical string it is computed over."""

    def test_golden_signature(self):
        # Captured live: /api/titles/rl2vm?vrf=8sK3xtqdFdusLLqwpg answered 200.
        self.assertEqual(mangafire_source.sign("/titles/rl2vm"), "8sK3xtqdFdusLLqwpg")

    def test_canonical_sorts_decodes_and_indexes_array_keys(self):
        text = mangafire_source.canonical("/titles", [
            ("page", "2"),
            ("keyword", "ju jutsu"),
            ("languages[]", "es-la"),
            ("languages[]", "es"),
            ("limit", "24"),
        ])
        self.assertEqual(
            text,
            "/titles?keyword=ju jutsu&languages[0]=es-la&languages[1]=es&limit=24&page=2",
        )

    def test_canonical_without_params_is_the_bare_path(self):
        self.assertEqual(mangafire_source.canonical("/titles/rl2vm", []), "/titles/rl2vm")

    def test_signed_url_encodes_the_query_and_appends_the_signature(self):
        url = mangafire_source.signed_url("/titles", [("languages[]", "es-la"), ("limit", "3")])
        self.assertTrue(url.startswith("https://mangafire.to/api/titles?"))
        self.assertIn("languages%5B%5D=es-la", url)
        self.assertIn("vrf=", url)
        # The signature is computed over the DECODED, indexed form, not the URL.
        signature = url.rsplit("vrf=", 1)[1]
        self.assertEqual(
            signature,
            mangafire_source.sign("/titles?languages[0]=es-la&limit=3"),
        )


class ParseItemsTest(unittest.TestCase):
    """search / latest / hot list items from the recorded JSON."""

    def setUp(self):
        self.items = mangafire_source.parse_items(load_json("search.json"))

    def test_items(self):
        self.assertEqual(len(self.items), 3)

    def test_first_item(self):
        item = self.items[0]
        self.assertEqual(item["id"], "rl2vm")
        self.assertEqual(item["title"], "Jujutsu Kaisen")
        self.assertEqual(item["type"], "MANGA")
        self.assertEqual(item["year"], "2018")
        self.assertEqual(item["chapter"], "271.5")
        self.assertTrue(item["image"].startswith("http://127.0.0.1:5150/image?url="))
        self.assertIn("@280.jpg", urllib.parse.unquote(item["image"]))

    def test_status_is_the_english_display_key(self):
        # The UI translates "Completed"/"Ongoing"; a raw "finished" would show
        # through untranslated.
        by_title = {item["title"]: item for item in self.items}
        self.assertEqual(by_title["Jujutsu Kaisen 0"]["status"], "Completed")


class ParseTitleTest(unittest.TestCase):
    def setUp(self):
        self.info = mangafire_source.parse_title(load_json("title.json"))

    def test_top_level(self):
        self.assertEqual(self.info["id"], "rl2vm")
        self.assertEqual(self.info["title"], "Jujutsu Kaisen")
        self.assertEqual(self.info["type"], "MANGA")
        self.assertEqual(self.info["year"], "2018")
        self.assertEqual(self.info["status"], "")  # the site leaves it empty
        self.assertIn("Yuji Itadori", self.info["description"])
        self.assertNotIn("<br>", self.info["description"])
        self.assertIn("Akutami Gege", self.info["authors"])
        self.assertIn("Action", self.info["tags"])
        self.assertIn("@280.jpg", urllib.parse.unquote(self.info["image"]))

    def test_status_map(self):
        self.assertEqual(mangafire_source._status("releasing"), "Ongoing")
        self.assertEqual(mangafire_source._status("finished"), "Completed")
        self.assertEqual(mangafire_source._status("hiatus"), "Hiatus")
        self.assertEqual(mangafire_source._status("discontinued"), "Cancelled")


class ParseChaptersTest(unittest.TestCase):
    def setUp(self):
        self.chapters = mangafire_source.parse_chapters(load_json("chapters.json"))

    def test_sorted_ascending(self):
        numbers = [float(chapter["chapter"]) for chapter in self.chapters]
        self.assertEqual(numbers, sorted(numbers))
        self.assertEqual(numbers, [267, 268, 269, 270, 271])

    def test_chapter_fields(self):
        last = self.chapters[-1]
        self.assertEqual(last["id"], "3744182")
        self.assertEqual(last["chapter"], "271")
        self.assertEqual(last["title"], "La continuación del sueño")
        self.assertRegex(last["publishAt"], r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")

    def test_untitled_chapter_gets_a_placeholder(self):
        # The API sends name "" for many chapters (267 in the fixture).
        self.assertEqual(self.chapters[0]["chapter"], "267")
        self.assertEqual(self.chapters[0]["title"], "Capítulo 267")


class ParsePagesTest(unittest.TestCase):
    def test_pages_in_order_through_the_proxy(self):
        pages = mangafire_source.parse_pages(load_json("chapter.json"))
        self.assertEqual([page["page"] for page in pages], list(range(1, 23)))
        first = urllib.parse.unquote(pages[0]["img"])
        self.assertIn("pw6.mfcdn2.xyz", first)
        self.assertTrue(first.endswith("/h/p.jpg"))
        self.assertTrue(pages[0]["img"].startswith("http://127.0.0.1:5150/image?url="))


class ApiTest(unittest.TestCase):
    """The public API with a faked transport (deterministic, no network)."""

    def setUp(self):
        mangafire_source._cache.clear()
        self.urls = []
        self.original = mangafire_source._request

        def fake(url):
            self.urls.append(url)
            if "/chapters/" in url:
                return json.dumps(load_json("chapter.json"))
            if "/titles/" in url and "/chapters" in url:
                return json.dumps(load_json("chapters.json"))
            if "/titles/" in url:
                return json.dumps(load_json("title.json"))
            return json.dumps(load_json("search.json"))

        mangafire_source._request = fake

    def tearDown(self):
        mangafire_source._request = self.original
        mangafire_source._cache.clear()

    def test_search(self):
        result = mangafire_source.search("jujutsu")
        self.assertEqual(result["results"][0]["id"], "rl2vm")
        self.assertTrue(result["hasMore"])
        self.assertIn("keyword=jujutsu", self.urls[0])
        self.assertIn("languages%5B%5D=es-la", self.urls[0])
        self.assertIn("vrf=", self.urls[0])

    def test_search_paging_uses_the_offset(self):
        mangafire_source.search("x", offset=24)
        self.assertIn("page=2", self.urls[0])

    def test_search_popularity_order(self):
        mangafire_source.search("x", sort="Popularity")
        self.assertIn("order%5Bviews_30d%5D=desc", self.urls[0])

    def test_latest(self):
        result = mangafire_source.latest(2)
        self.assertTrue(result["results"])
        self.assertIn("page=2", self.urls[0])
        self.assertIn("order%5Bchapter_updated_at%5D=desc", self.urls[0])

    def test_hot(self):
        items = mangafire_source.hot()
        self.assertTrue(items)
        self.assertIn("order%5Bviews_7d%5D=desc", self.urls[0])

    def test_info(self):
        data = mangafire_source.info("rl2vm")
        self.assertEqual(data["title"], "Jujutsu Kaisen")
        self.assertEqual(len(data["chapters"]), 5)
        self.assertIn("/titles/rl2vm/chapters", self.urls[1])

    def test_pages(self):
        pages = mangafire_source.pages("3727642")
        self.assertEqual(len(pages), 22)

    def test_info_sorts_chapters_across_pages(self):
        # Page 1 carries the newest chapters and page 2 the oldest, so the
        # union must be sorted again or the reader shows 72…271,1…71.
        original = mangafire_source._request

        def two_pages(url):
            self.urls.append(url)
            if "/chapters" in url:
                if "page=1" in url:
                    return json.dumps({"items": [
                        {"id": 3, "number": 3, "name": "", "createdAt": 1700000000},
                        {"id": 4, "number": 4, "name": "", "createdAt": 1700000000},
                    ], "meta": {"hasNext": True}})
                return json.dumps({"items": [
                    {"id": 1, "number": 1, "name": "", "createdAt": 1700000000},
                    {"id": 2, "number": 2, "name": "", "createdAt": 1700000000},
                ], "meta": {"hasNext": False}})
            return json.dumps(load_json("title.json"))

        mangafire_source._request = two_pages
        try:
            data = mangafire_source.info("rl2vm")
        finally:
            mangafire_source._request = original
        self.assertEqual([chapter["chapter"] for chapter in data["chapters"]],
                         ["1", "2", "3", "4"])

    def test_info_prefers_es_la_and_falls_back_to_es(self):
        original = mangafire_source._request

        def empty_es_la(url):
            self.urls.append(url)
            if "/chapters" in url:
                if "language=es-la" in url:
                    return json.dumps({"items": [], "meta": {"total": 0}})
                return json.dumps(load_json("chapters.json"))
            return json.dumps(load_json("title.json"))

        mangafire_source._request = empty_es_la
        try:
            data = mangafire_source.info("rl2vm")
        finally:
            mangafire_source._request = original
        self.assertEqual(len(data["chapters"]), 5)
        self.assertTrue(any("language=es-la" in url for url in self.urls))
        self.assertTrue(any("language=es&" in url for url in self.urls))


class TransportTest(unittest.TestCase):
    """Retries live in _request, so a 403 burst or a 5xx does not kill a page."""

    class _Resp:
        def __init__(self, text):
            self._text = text

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

        def read(self):
            return self._text.encode("utf-8")

    def setUp(self):
        self.calls = 0
        self._orig = (mangafire_source.urllib.request.urlopen,
                      mangafire_source.time.sleep,
                      mangafire_source._rate_limit)
        mangafire_source.time.sleep = lambda *args: None
        mangafire_source._rate_limit = lambda: None
        mangafire_source._cache.clear()

    def tearDown(self):
        (mangafire_source.urllib.request.urlopen,
         mangafire_source.time.sleep,
         mangafire_source._rate_limit) = self._orig
        mangafire_source._cache.clear()

    def _patch(self, fake):
        mangafire_source.urllib.request.urlopen = fake

    def test_retries_a_burst_403_then_succeeds(self):
        def fake(request, timeout=None):
            self.calls += 1
            if self.calls == 1:
                body = b'{"message": "Missing token."}'
                raise urllib.error.HTTPError("u", 403, "forbidden", {}, io.BytesIO(body))
            return self._Resp('{"ok": true}')

        self._patch(fake)
        self.assertEqual(mangafire_source._request("https://x/"), '{"ok": true}')
        self.assertEqual(self.calls, 2)

    def test_a_persistent_invalid_token_gives_up(self):
        def fake(request, timeout=None):
            self.calls += 1
            body = b'{"message": "Invalid token."}'
            raise urllib.error.HTTPError("u", 403, "forbidden", {}, io.BytesIO(body))

        self._patch(fake)
        with self.assertRaises(urllib.error.HTTPError):
            mangafire_source._request("https://x/")
        self.assertEqual(self.calls, mangafire_source.ATTEMPTS)

    def test_5xx_is_retried(self):
        def fake(request, timeout=None):
            self.calls += 1
            if self.calls < 2:
                raise urllib.error.HTTPError("u", 503, "boom", {}, io.BytesIO(b""))
            return self._Resp("ok")

        self._patch(fake)
        self.assertEqual(mangafire_source._request("https://x/"), "ok")
        self.assertEqual(self.calls, 2)


if __name__ == "__main__":
    unittest.main()
