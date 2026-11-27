"""Tests for scripts/chapter_versions.py.

The backend counts a favourite's new chapters with the same rule the panel uses
to draw one row per chapter (services/chapters.js). Both read the same corpus,
tests/fixtures/chapter_versions.json, so the two implementations cannot drift
apart without this test or tests/versions.test.js failing.
"""

import json
import os
import sys
import unittest
from datetime import date
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts"))

import chapter_versions  # noqa: E402

try:
    import manga_server
except ImportError:      # a CI image without curl_cffi/requests: only this class skips
    manga_server = None

CORPUS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "chapter_versions.json")


def row(number, chapter_id, day, group=""):
    return {"id": chapter_id, "chapter": str(number), "title": "Capítulo " + str(number),
            "group": group, "publishAt": day}


def generation(count):
    rows = [row(i, "old-%d" % i, "09/04/2026") for i in range(1, count + 1)]
    rows += [row("%d.1" % i, "new-%d" % i, "21/04/2026") for i in range(1, count + 1)]
    return rows


class SharedCorpusTest(unittest.TestCase):
    def test_corpus_expectations(self):
        with open(CORPUS, encoding="utf-8") as handle:
            corpus = json.load(handle)
        self.assertTrue(corpus["cases"], "the corpus cannot be empty")
        for case in corpus["cases"]:
            with self.subTest(case=case["name"]):
                self.assertEqual(chapter_versions.grouped_count(case["chapters"]), case["groups"])


class RuleTest(unittest.TestCase):
    def test_a_reupload_generation_is_one_group_per_chapter(self):
        self.assertEqual(chapter_versions.grouped_count(generation(6)), 6)
        self.assertEqual(
            chapter_versions.grouped_numbers(generation(6)),
            ["1", "2", "3", "4", "5", "6"],
        )

    def test_the_live_sample_shape_groups_into_chapters(self):
        rows = [row(i, "zonatmo_org:%d" % (114048 + i), "09/04/2026") for i in range(1, 72)]
        rows += [row("%d.1" % i, "zonatmo_org:%d" % (871341 + i), "21/04/2026") for i in range(1, 67)]
        self.assertEqual(chapter_versions.grouped_count(rows), 71)

    def test_no_chapters_is_zero(self):
        self.assertEqual(chapter_versions.grouped_count([]), 0)
        self.assertEqual(chapter_versions.grouped_count(None), 0)

    def test_non_numeric_labels_are_their_own_chapter(self):
        rows = [row("Prólogo", "p", "")] + generation(4)
        self.assertEqual(chapter_versions.grouped_numbers(rows)[0], "Prólogo")
        self.assertEqual(chapter_versions.grouped_count(rows), 5)

    def test_dates_read_day_first(self):
        self.assertEqual(chapter_versions.parse_date("21/04/2026").date(), date(2026, 4, 21))
        self.assertEqual(chapter_versions.parse_date("09/04/2026").date(), date(2026, 4, 9))
        self.assertEqual(chapter_versions.parse_date("2026-04-21T00:00:00+00:00").date(), date(2026, 4, 21))
        self.assertIsNone(chapter_versions.parse_date(""))
        self.assertIsNone(chapter_versions.parse_date("hace 2 días"))


@unittest.skipUnless(manga_server is not None, "backend dependencies missing")
class FavCheckTest(unittest.TestCase):
    """A re-upload must not announce itself as new chapters on a favourite."""

    def test_fav_check_counts_grouped_chapters(self):
        chapters = generation(6)          # 12 rows, 6 real chapters
        favs = [{
            "id": "zonatmo_org:series", "title": "T",
            "hasNewChapters": False, "lastKnownChapterCount": 6,
        }]
        saved = {}

        with mock.patch.object(manga_server, "_load_favs", return_value=favs), \
             mock.patch.object(manga_server, "_save_favs",
                               side_effect=lambda data: saved.setdefault("favs", data)), \
             mock.patch.object(manga_server, "info", return_value={"chapters": chapters}):
            result = manga_server.fav_check()

        self.assertEqual(result["updated"], [], "12 rows are still 6 chapters")
        self.assertFalse(favs[0]["hasNewChapters"])
        self.assertEqual(favs[0]["lastKnownChapterCount"], 6)

    def test_fav_check_reconciles_a_stale_raw_count(self):
        # A favourite saved while the badge counted rows keeps the raw number
        # (137 for 71 chapters), and it can already carry a pending badge. The
        # old code only reconciled the counter when the badge was off, so the
        # inflated number outlived a cleared badge and hid the next chapter.
        favs = [{
            "id": "zonatmo_org:series", "title": "T",
            "hasNewChapters": True, "lastKnownChapterCount": 12,
        }]
        payloads = [
            {"chapters": generation(6)},
            {"chapters": generation(6) + [row(7, "new-7", "22/04/2026")]},
        ]

        with mock.patch.object(manga_server, "_load_favs", return_value=favs), \
             mock.patch.object(manga_server, "_save_favs", side_effect=lambda data: None), \
             mock.patch.object(manga_server, "info", side_effect=payloads):
            first = manga_server.fav_check()
            self.assertEqual(first["updated"], [], "a stale raw count is not a new chapter")
            self.assertEqual(favs[0]["lastKnownChapterCount"], 6,
                             "the stale raw count is reconciled even with a pending badge")

            second = manga_server.fav_check()
            self.assertEqual(second["updated"],
                             [{"id": "zonatmo_org:series", "title": "T", "newCount": 7}])
            self.assertTrue(favs[0]["hasNewChapters"])

    def test_fav_check_still_reports_a_real_new_chapter(self):
        chapters = generation(6) + [row(7, "new-7", "22/04/2026")]
        favs = [{
            "id": "zonatmo_org:series", "title": "T",
            "hasNewChapters": False, "lastKnownChapterCount": 6,
        }]

        with mock.patch.object(manga_server, "_load_favs", return_value=favs), \
             mock.patch.object(manga_server, "_save_favs", side_effect=lambda data: None), \
             mock.patch.object(manga_server, "info", return_value={"chapters": chapters}):
            result = manga_server.fav_check()

        self.assertEqual(result["updated"], [{"id": "zonatmo_org:series", "title": "T", "newCount": 7}])
        self.assertTrue(favs[0]["hasNewChapters"])


if __name__ == "__main__":
    unittest.main()
