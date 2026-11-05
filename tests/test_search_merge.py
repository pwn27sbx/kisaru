"""Tests for scripts/search_merge.py (dedupe + ranking of source answers).

A search asks every active source; the answers are merged into one page. These
tests pin the two rules the merge must not get wrong: the same work appears
once, and the versions that differ on purpose ("sin censura") stay apart.

Run: python3 -m unittest discover -s tests -p "test_*.py"
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

import search_merge  # noqa: E402


def page(titles, has_more=False):
    return {
        "results": [{"id": "id-" + t, "title": t} for t in titles],
        "hasMore": has_more,
    }


class FoldTest(unittest.TestCase):
    def test_case_accents_and_punctuation_fold(self):
        self.assertEqual(search_merge.fold("Las Amigas de mi Madrastra"),
                         "las amigas de mi madrastra")
        self.assertEqual(search_merge.fold("Pokémon: ¡Aventura!"),
                         "pokemon aventura")
        self.assertEqual(search_merge.fold("  NARUTO  "), "naruto")
        self.assertEqual(search_merge.fold(""), "")


class ScoreTest(unittest.TestCase):
    def test_exact_ranking_is_case_and_accent_folded(self):
        self.assertEqual(search_merge.score("pokemon", "Pokémon"),
                         search_merge.score("Pokémon", "Pokémon"))
        self.assertGreater(search_merge.score("pokemon", "Pokémon"),
                           search_merge.score("pokemon", "Pokémon Adventures"))

    def test_full_title_beats_a_partial_one(self):
        exact = search_merge.score("las amigas de mi madrastra",
                                   "Las Amigas de mi Madrastra")
        variant = search_merge.score("las amigas de mi madrastra",
                                     "Las Amigas de mi Madrastra sin Censura")
        near = search_merge.score("las amigas de mi madrastra",
                                  "La Amiga de mi Hermana")
        self.assertGreater(exact, variant)
        self.assertGreater(variant, near)

    def test_a_prefix_match_beats_an_unrelated_title(self):
        self.assertGreater(search_merge.score("solo leveling", "Solo Leveling: Ragnarok"),
                           search_merge.score("solo leveling", "Otro titulo"))


class MergeTest(unittest.TestCase):
    def test_dedupe_keeps_the_entry_from_the_earlier_source(self):
        answers = [
            ("mangadex", page(["Las Amigas de mi Madrastra"])),
            ("manhwaweb", page(["las amigas de mi madrastra"])),
        ]
        merged = search_merge.merge(answers, "las amigas de mi madrastra")
        self.assertEqual(len(merged["items"]), 1)
        source, item = merged["items"][0]
        self.assertEqual(source, "mangadex")
        self.assertEqual(item["id"], "id-Las Amigas de mi Madrastra")

    def test_a_different_version_stays_its_own_entry(self):
        answers = [
            ("manhwaweb", page(["Las Amigas de mi Madrastra",
                                "Las Amigas de mi Madrastra sin Censura"])),
        ]
        merged = search_merge.merge(answers, "las amigas de mi madrastra")
        self.assertEqual([item["title"] for _, item in merged["items"]],
                         ["Las Amigas de mi Madrastra",
                          "Las Amigas de mi Madrastra sin Censura"])

    def test_the_exact_title_comes_first_even_from_the_last_source(self):
        answers = [
            ("mangadex", page(["La Amiga de mi Hermana",
                               "Empece a salir con la amiga de mi hermana"])),
            ("manhwaweb", page(["Las Amigas de mi Madrastra",
                                "Las Amigas de mi Madrastra sin Censura"])),
        ]
        merged = search_merge.merge(answers, "las amigas de mi madrastra")
        titles = [item["title"] for _, item in merged["items"]]
        self.assertEqual(titles[0], "Las Amigas de mi Madrastra")
        self.assertEqual(titles[1], "Las Amigas de mi Madrastra sin Censura")
        self.assertIn("La Amiga de mi Hermana", titles)
        # Nothing is dropped: the near matches stay, only below the matches.
        self.assertEqual(len(titles), 4)

    def test_equally_ranked_titles_keep_the_source_order(self):
        answers = [
            ("mangadex", page(["Bleach"])),
            ("inmanga", page(["Bleach"])),
            ("manhwaweb", page(["Zorro", "Bleach"])),
        ]
        merged = search_merge.merge(answers, "bleach")
        bleaches = [(source, item) for source, item in merged["items"]
                    if item["title"] == "Bleach"]
        self.assertEqual(len(bleaches), 1)
        self.assertEqual(bleaches[0][0], "mangadex")

    def test_paging_window_is_the_largest_source_window(self):
        answers = [
            ("mangadex", page(["A", "B", "C"], has_more=True)),
            ("manhwaweb", page(["D", "E"], has_more=False)),
        ]
        merged = search_merge.merge(answers, "x")
        self.assertEqual(merged["window"], 3)
        self.assertTrue(merged["hasMore"])

    def test_an_empty_answer_pages_nothing(self):
        merged = search_merge.merge([("mangadex", page([]))], "x")
        self.assertEqual(merged["items"], [])
        self.assertEqual(merged["window"], 0)
        self.assertFalse(merged["hasMore"])

    def test_a_source_that_answered_nothing_is_ignored(self):
        answers = [("mangadex", None), ("manhwaweb", page(["D"]))]
        merged = search_merge.merge(answers, "d")
        self.assertEqual([source for source, _ in merged["items"]], ["manhwaweb"])

    def test_has_more_comes_from_any_source_that_says_so(self):
        answers = [
            ("mangadex", page(["A"], has_more=False)),
            ("manhwaweb", page(["B"], has_more=True)),
        ]
        self.assertTrue(search_merge.merge(answers, "x")["hasMore"])


if __name__ == "__main__":
    unittest.main()
