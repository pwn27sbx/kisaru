"""Tests for scripts/manga_chain.py (source chain + language fall-through).

The source modules are replaced with fakes so the chain logic is exercised
without the network. Run: python3 -m unittest discover -s tests -p "test_*.py"
"""

import os
import sys
import time
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

import manga_chain  # noqa: E402


class FakeSource:
    def __init__(self, found=True, chapters=True):
        self.found = found
        self.chapters = chapters

    def search(self, query, mtype=None, offset=0, sort="Best Match"):
        results = [{"id": "S-" + query, "title": query}] if self.found else []
        return {"results": results, "hasMore": False, "nextOffset": 0}

    def latest(self, page=1):
        return {"results": [{"id": "L"}] if self.found else [], "hasMore": False, "nextPage": page + 1}

    def hot(self):
        return [{"id": "H"}] if self.found else []

    def info(self, manga_id):
        chapters = [{"id": "CH", "chapter": "1"}] if self.chapters else []
        return {"id": manga_id, "title": "Foo", "chapters": chapters}

    def pages(self, chapter_id):
        return [{"page": 1, "img": "img:" + chapter_id}]


class ActiveChainTest(unittest.TestCase):
    def test_spanish_uses_the_chain(self):
        self.assertEqual(manga_chain.active_chain("", ["es-419", "es"]),
                         ["mangadex", "inmanga", "zonatmo", "zonatmo_org", "manhwaweb"])

    def test_english_uses_weebcentral(self):
        self.assertEqual(manga_chain.active_chain("", ["en"]), ["weebcentral"])

    def test_forced_source(self):
        self.assertEqual(manga_chain.active_chain("inmanga", ["en"]), ["inmanga"])
        self.assertEqual(manga_chain.active_chain("mangadex", ["es"]), ["mangadex"])
        self.assertEqual(manga_chain.active_chain("zonatmo", ["en"]), ["zonatmo"])
        self.assertEqual(manga_chain.active_chain("zonatmo_org", ["en"]), ["zonatmo_org"])

    def test_mirrors_for(self):
        self.assertEqual(manga_chain.mirrors_for("zonatmo"), ("zonatmo.net",))
        self.assertEqual(manga_chain.mirrors_for("zonatmo_org"), ("zonatmo.org",))
        self.assertEqual(manga_chain.mirrors_for("mangadex"), ())

    def test_spanish_sources_exclude_the_english_fallback(self):
        self.assertEqual(manga_chain.spanish_sources("", ["es"]),
                         ["mangadex", "inmanga", "zonatmo", "zonatmo_org", "manhwaweb"])
        self.assertEqual(manga_chain.spanish_sources("", ["en"]), [])


class RaisingSource(FakeSource):
    """A source whose domain is dead: every call raises."""

    def search(self, *args, **kwargs):
        raise RuntimeError("domain dead")

    def latest(self, *args, **kwargs):
        raise RuntimeError("domain dead")

    def hot(self, *args, **kwargs):
        raise RuntimeError("domain dead")

    def info(self, *args, **kwargs):
        raise RuntimeError("domain dead")


class ChainTest(unittest.TestCase):
    def setUp(self):
        self._old_env = os.environ.get("QS_CONTENT_LANG")
        os.environ["QS_CONTENT_LANG"] = "es"
        self._old_modules = manga_chain._MODULES

    def tearDown(self):
        manga_chain._MODULES = self._old_modules
        if self._old_env is None:
            os.environ.pop("QS_CONTENT_LANG", None)
        else:
            os.environ["QS_CONTENT_LANG"] = self._old_env

    def set_modules(self, mangadex, inmanga, zonatmo=None, zonatmo_org=None):
        manga_chain._MODULES = {
            "mangadex": mangadex,
            "inmanga": inmanga,
            "zonatmo": zonatmo if zonatmo is not None else FakeSource(),
            "zonatmo_org": zonatmo_org if zonatmo_org is not None else FakeSource(),
        }

    def test_latest_skips_a_dead_source(self):
        self.set_modules(RaisingSource(), FakeSource(found=True))
        result = manga_chain.latest(1)
        self.assertEqual(result["results"][0]["id"], "inmanga:L")

    def test_hot_skips_a_dead_source(self):
        self.set_modules(RaisingSource(), FakeSource(found=True))
        self.assertEqual(manga_chain.hot()[0]["id"], "inmanga:H")

    def test_info_keeps_source_when_it_has_chapters(self):
        self.set_modules(FakeSource(chapters=True), FakeSource(chapters=True))
        data = manga_chain.info("mangadex:x")
        self.assertEqual(data["id"], "mangadex:x")
        self.assertEqual(data["chapters"][0]["id"], "mangadex:CH")

    def test_info_falls_through_to_inmanga(self):
        self.set_modules(FakeSource(chapters=False), FakeSource(found=True, chapters=True))
        data = manga_chain.info("mangadex:x")
        self.assertEqual(data["id"], "inmanga:S-Foo")
        self.assertEqual(data["chapters"][0]["id"], "inmanga:CH")

    def test_info_falls_through_to_zonatmo(self):
        self.set_modules(
            FakeSource(chapters=False),
            FakeSource(found=False, chapters=False),
            FakeSource(found=True, chapters=True),
        )
        data = manga_chain.info("mangadex:x")
        self.assertEqual(data["id"], "zonatmo:S-Foo")
        self.assertEqual(data["chapters"][0]["id"], "zonatmo:CH")

    def test_info_falls_through_to_zonatmo_org(self):
        self.set_modules(
            FakeSource(chapters=False),
            FakeSource(found=False, chapters=False),
            FakeSource(found=False, chapters=False),
            FakeSource(found=True, chapters=True),
        )
        data = manga_chain.info("mangadex:x")
        self.assertEqual(data["id"], "zonatmo_org:S-Foo")
        self.assertEqual(data["chapters"][0]["id"], "zonatmo_org:CH")

    def test_info_skips_a_dead_fallthrough_source(self):
        # The primary has no chapters but provides the title; the next source
        # is dead and must be skipped so the live one is reached.
        self.set_modules(
            FakeSource(chapters=False),            # mangadex: title "Foo", no chapters
            RaisingSource(),                       # inmanga: dead
            FakeSource(found=True, chapters=True),  # zonatmo: alive
        )
        data = manga_chain.info("mangadex:x")
        self.assertEqual(data["id"], "zonatmo:S-Foo")

    def test_info_skips_source_whose_info_raises(self):
        class HalfDead(FakeSource):
            def info(self, *args, **kwargs):
                raise RuntimeError("info dead")

        self.set_modules(
            FakeSource(chapters=False),
            HalfDead(found=True, chapters=True),   # search works, info raises
            FakeSource(found=True, chapters=True),
        )
        data = manga_chain.info("mangadex:x")
        self.assertEqual(data["id"], "zonatmo:S-Foo")

    def test_info_uses_the_id_slug_when_the_starting_source_has_no_data(self):
        # zonatmo.net's detail endpoint 404s (2026-10-27), so the starting
        # source answers with nothing and there is no title yet. The chain must
        # derive the title from the id slug ("tienda-del-placer") instead of
        # stopping before the fall-through, or a dead backend hides a live one.
        import titles as titles_module

        class TitleAware(FakeSource):
            def search(self, query, mtype=None, offset=0, sort="Best Match"):
                matches = titles_module.titles_match(query, "Tienda del Placer")
                results = [{"id": "ORG", "title": "Tienda del Placer"}] if matches else []
                return {"results": results, "hasMore": False, "nextOffset": 0}

        manga_chain._MODULES = {
            "mangadex": FakeSource(found=False, chapters=False),
            "inmanga": FakeSource(found=False, chapters=False),
            "zonatmo": RaisingSource(),
            "zonatmo_org": TitleAware(found=True, chapters=True),
            "manhwaweb": FakeSource(found=False, chapters=False),
        }
        data = manga_chain.info("zonatmo:tienda-del-placer")
        self.assertEqual(data.get("id"), "zonatmo_org:ORG")
        self.assertEqual(data["chapters"][0]["id"], "zonatmo_org:CH")

    def test_none_has_spanish(self):
        self.set_modules(FakeSource(chapters=False), FakeSource(found=True, chapters=False),
                         FakeSource(found=True, chapters=False), FakeSource(found=True, chapters=False))
        data = manga_chain.info("mangadex:x")
        self.assertEqual(data.get("error"), "Sin capítulos en español")
        # The title is carried so the server can fall back to the English source.
        self.assertEqual(data.get("title"), "Foo")

    def test_fallthrough_rejects_non_matching_title(self):
        # The fall-through source answers with an unrelated series: it must NOT
        # be adopted; the chain reports "no Spanish" instead.
        class Wrong(FakeSource):
            def search(self, query, mtype=None, offset=0, sort="Best Match"):
                return {"results": [{"id": "x", "title": "Aoi - Hikaru"}], "hasMore": False, "nextOffset": 0}

        self.set_modules(FakeSource(chapters=False), Wrong(found=True, chapters=True),
                         FakeSource(found=False, chapters=False), FakeSource(found=False, chapters=False))
        data = manga_chain.info("mangadex:x")
        self.assertEqual(data.get("error"), "Sin capítulos en español")

    def test_fallthrough_rejects_a_sequel(self):
        # Regression: "Foo" must not resolve to its sequel "Foo: Ragnarok"
        # (a subtitle is a different work). See scripts/titles.py.
        class SequelOnly(FakeSource):
            def search(self, query, mtype=None, offset=0, sort="Best Match"):
                return {"results": [{"id": "x", "title": "Foo: Ragnarok"}], "hasMore": False, "nextOffset": 0}

        self.set_modules(FakeSource(chapters=False), SequelOnly(found=True, chapters=True),
                         FakeSource(found=False, chapters=False), FakeSource(found=False, chapters=False))
        data = manga_chain.info("mangadex:x")
        self.assertEqual(data.get("error"), "Sin capítulos en español")

    def test_info_carries_the_id_the_caller_asked_for(self):
        # The reader stores progress against the entry the user opened, so a
        # fallback must not replace its identity with the answering source's.
        class OnlyOrg(FakeSource):
            def search(self, query, mtype=None, offset=0, sort="Best Match"):
                return {"results": [{"id": "ORG", "title": "Tienda del Placer"}],
                        "hasMore": False, "nextOffset": 0}

        manga_chain._MODULES = {
            "mangadex": FakeSource(found=False, chapters=False),
            "inmanga": FakeSource(found=False, chapters=False),
            "zonatmo": RaisingSource(),
            "zonatmo_org": OnlyOrg(found=True, chapters=True),
            "manhwaweb": FakeSource(found=False, chapters=False),
        }
        data = manga_chain.info("zonatmo:tienda-del-placer")
        self.assertEqual(data["id"], "zonatmo_org:ORG")
        self.assertEqual(data["originId"], "zonatmo:tienda-del-placer")

    def test_info_origin_matches_when_the_same_source_answers(self):
        self.set_modules(FakeSource(chapters=True), FakeSource())
        data = manga_chain.info("mangadex:x")
        self.assertEqual(data["originId"], "mangadex:x")
        self.assertEqual(data["id"], data["originId"])

    def test_pages_routes_by_prefix(self):
        self.set_modules(FakeSource(), FakeSource())
        pages = manga_chain.pages("inmanga:manga/CH")
        self.assertEqual(pages[0]["img"], "img:manga/CH")

    def test_pages_routes_to_zonatmo(self):
        self.set_modules(FakeSource(), FakeSource(), FakeSource())
        pages = manga_chain.pages("zonatmo:solo-leveling/solo-leveling-capitulo-1")
        self.assertEqual(pages[0]["img"], "img:solo-leveling/solo-leveling-capitulo-1")

    def test_pages_routes_to_zonatmo_org(self):
        self.set_modules(FakeSource(), FakeSource(), FakeSource(), FakeSource())
        pages = manga_chain.pages("zonatmo_org:969671")
        self.assertEqual(pages[0]["img"], "img:969671")


class TitledSource:
    """A search source with controllable titles, paging, delay and failure."""

    def __init__(self, titles=(), has_more=False, delay=0.0, error=None):
        self.titles = list(titles)
        self.has_more = has_more
        self.delay = delay
        self.error = error
        self.calls = []

    def search(self, query, mtype=None, offset=0, sort="Best Match"):
        self.calls.append({"query": query, "mtype": mtype, "offset": offset, "sort": sort})
        if self.error is not None:
            raise self.error
        if self.delay:
            time.sleep(self.delay)
        return {
            "results": [{"id": "id-" + t, "title": t} for t in self.titles],
            "hasMore": self.has_more,
            "nextOffset": offset + len(self.titles),
        }


class SearchAllSourcesTest(unittest.TestCase):
    """A search asks every active source, merges, dedupes and ranks.

    The reported bug: MangaDex answers a Spanish query with near matches, the
    chain stopped there, and ManhwaWeb (which has the title) was never asked.
    """

    NEAR = ["La Amiga de mi Hermana",
            "Empece a salir con la amiga de mi hermana"]

    def setUp(self):
        self._old_env = os.environ.get("QS_CONTENT_LANG")
        os.environ["QS_CONTENT_LANG"] = "es"
        self._old_modules = manga_chain._MODULES
        self._old_timeout = manga_chain.SEARCH_SOURCE_TIMEOUT
        self._old_report = manga_chain._report
        self.reported = []
        manga_chain._report = lambda error, source="", op="": self.reported.append(
            (type(error).__name__, source, op))

    def tearDown(self):
        manga_chain._MODULES = self._old_modules
        manga_chain.SEARCH_SOURCE_TIMEOUT = self._old_timeout
        manga_chain._report = self._old_report
        if self._old_env is None:
            os.environ.pop("QS_CONTENT_LANG", None)
        else:
            os.environ["QS_CONTENT_LANG"] = self._old_env

    def set_sources(self, **by_name):
        base = {name: TitledSource() for name in
                ("mangadex", "inmanga", "zonatmo", "zonatmo_org", "manhwaweb")}
        base.update(by_name)
        manga_chain._MODULES = base
        return base

    def test_every_active_source_is_asked(self):
        sources = self.set_sources(mangadex=TitledSource(titles=["A"]))
        manga_chain.search("x", merge=True)
        for name, source in sources.items():
            self.assertEqual(len(source.calls), 1, f"{name} was not asked")

    def test_the_near_match_does_not_hide_the_exact_title(self):
        self.set_sources(
            mangadex=TitledSource(titles=self.NEAR),
            manhwaweb=TitledSource(titles=["Las Amigas de mi Madrastra",
                                           "Las Amigas de mi Madrastra sin Censura"]),
        )
        result = manga_chain.search("las amigas de mi madrastra", merge=True)
        titles = [item["title"] for item in result["results"]]
        self.assertEqual(titles[0], "Las Amigas de mi Madrastra")
        self.assertEqual(titles[1], "Las Amigas de mi Madrastra sin Censura")
        self.assertIn("La Amiga de mi Hermana", titles)

    def test_ids_keep_the_source_prefix_of_the_answering_source(self):
        self.set_sources(mangadex=TitledSource(titles=["Las Amigas de mi Madrastra"]),
                         manhwaweb=TitledSource(titles=["Las Amigas de mi Madrastra"]))
        result = manga_chain.search("las amigas de mi madrastra", merge=True)
        self.assertEqual(len(result["results"]), 1)
        self.assertTrue(result["results"][0]["id"].startswith("mangadex:"))

    def test_a_slow_source_cannot_hold_the_search(self):
        manga_chain.SEARCH_SOURCE_TIMEOUT = 0.15
        self.set_sources(
            mangadex=TitledSource(titles=["Slow"], delay=0.6),
            manhwaweb=TitledSource(titles=["Las Amigas de mi Madrastra"]),
        )
        started = time.monotonic()
        result = manga_chain.search("las amigas de mi madrastra", merge=True)
        elapsed = time.monotonic() - started
        self.assertLess(elapsed, 0.45, f"the search waited for the slow source: {elapsed}s")
        self.assertEqual(result["results"][0]["title"], "Las Amigas de mi Madrastra")
        self.assertIn(("TimeoutError", "mangadex", "search"), self.reported)

    def test_a_failing_source_is_skipped_and_reported(self):
        self.set_sources(
            mangadex=TitledSource(error=RuntimeError("domain dead")),
            manhwaweb=TitledSource(titles=["Las Amigas de mi Madrastra"]),
        )
        result = manga_chain.search("las amigas de mi madrastra", merge=True)
        self.assertEqual(result["results"][0]["title"], "Las Amigas de mi Madrastra")
        self.assertIn(("RuntimeError", "mangadex", "search"), self.reported)

    def test_the_same_title_from_two_sources_appears_once(self):
        self.set_sources(
            mangadex=TitledSource(titles=["Solo Leveling"]),
            manhwaweb=TitledSource(titles=["solo leveling"]),
        )
        result = manga_chain.search("solo leveling", merge=True)
        self.assertEqual([r["title"] for r in result["results"]], ["Solo Leveling"])
        self.assertTrue(result["results"][0]["id"].startswith("mangadex:"))

    def test_a_deliberate_variant_stays_its_own_entry(self):
        self.set_sources(manhwaweb=TitledSource(titles=["Solo Leveling",
                                                        "Solo Leveling sin Censura"]))
        result = manga_chain.search("solo leveling", merge=True)
        self.assertEqual([r["title"] for r in result["results"]],
                         ["Solo Leveling", "Solo Leveling sin Censura"])

    def test_paging_sends_the_same_offset_to_every_source(self):
        sources = self.set_sources(
            mangadex=TitledSource(titles=["A"] * 20, has_more=True),
            manhwaweb=TitledSource(titles=["B"] * 30, has_more=True),
        )
        result = manga_chain.search("x", offset=60, merge=True)
        for name, source in sources.items():
            self.assertEqual(source.calls[0]["offset"], 60, f"{name} got another window")
        # The page advances by the largest window a source actually returned,
        # so no source is asked for the same items twice.
        self.assertEqual(result["nextOffset"], 90)
        self.assertTrue(result["hasMore"])

    def test_paging_stops_when_no_source_says_there_is_more(self):
        self.set_sources(mangadex=TitledSource(titles=["A"]),
                         manhwaweb=TitledSource(titles=["B"]))
        result = manga_chain.search("x", offset=30, merge=True)
        self.assertEqual(result["nextOffset"], 31)
        self.assertFalse(result["hasMore"])

    def test_an_all_empty_answer_does_not_advance_the_offset(self):
        self.set_sources()
        result = manga_chain.search("x", offset=30, merge=True)
        self.assertEqual(result["results"], [])
        self.assertEqual(result["nextOffset"], 30)
        self.assertFalse(result["hasMore"])

    def test_the_catalog_path_keeps_the_first_source_answer(self):
        # Browse lists through /search with q=a and popularity; that path must
        # not become a merged, ranked search.
        sources = self.set_sources(
            mangadex=TitledSource(titles=["A1", "A2"]),
            manhwaweb=TitledSource(titles=["B1"]),
        )
        result = manga_chain.search("a", sort="Popularity")
        self.assertEqual([r["title"] for r in result["results"]], ["A1", "A2"])
        self.assertEqual(len(sources["manhwaweb"].calls), 0,
                         "the catalog asked every source")

    def test_mtype_and_sort_reach_every_source(self):
        sources = self.set_sources()
        manga_chain.search("x", mtype="Manhwa", offset=0, sort="Popularity", merge=True)
        for name, source in sources.items():
            self.assertEqual(source.calls[0]["mtype"], "Manhwa", name)
            self.assertEqual(source.calls[0]["sort"], "Popularity", name)


if __name__ == "__main__":
    unittest.main()
