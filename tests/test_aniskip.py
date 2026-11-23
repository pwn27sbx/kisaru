"""Tests for scripts/aniskip.py — AniSkip v2 client, MAL ID resolver, and disk cache.

All HTTP calls are mocked and cache writes go into an isolated mktemp directory
(XDG_CACHE_HOME). Zero live network requests.

Run: python3 -m unittest tests/test_aniskip.py
"""

import json
import os
import sys
import tempfile
import time
import unittest
import urllib.error
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

import aniskip  # noqa: E402


def _aniskip_ok(results):
    return 200, json.dumps({
        "found": True,
        "results": results,
        "message": "Successfully found skip times",
        "statusCode": 200,
    })


def _aniskip_404():
    return 404, json.dumps({
        "found": False,
        "results": [],
        "message": "Skip times not found",
        "statusCode": 404,
    })


class AniSkipTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self._env_patch = mock.patch.dict(
            os.environ,
            {"XDG_CACHE_HOME": self._tmp.name, "HOME": self._tmp.name},
            clear=False,
        )
        self._env_patch.start()
        self.addCleanup(self._env_patch.stop)
        aniskip.reset_rate_limit_state()

    def test_native_mal_id_skips_title_lookup_and_fetches_aniskip(self):
        calls = []

        def fake_http(url, method="GET", body=None, headers=None, timeout=4.0):
            calls.append((method, url))
            return _aniskip_ok([
                {
                    "interval": {"startTime": 28.783, "endTime": 118.783},
                    "skipType": "op",
                    "skipId": "op-1",
                    "episodeLength": 1500.04,
                },
                {
                    "interval": {"startTime": 1387.996, "endTime": 1500.0},
                    "skipType": "ed",
                    "skipId": "ed-1",
                    "episodeLength": 1500.146,
                },
            ])

        res = aniskip.get_skip_times(
            show_id="allanime-1",
            episode="1",
            meta={"name": "One Piece", "englishName": "One Piece", "malId": "21"},
            duration=1500.0,
            http_get=fake_http,
        )
        self.assertTrue(res["found"])
        self.assertEqual(res["mal_id"], 21)
        self.assertEqual(res["source"], "allanime")
        self.assertEqual(len(res["intervals"]), 2)
        self.assertEqual(res["intervals"][0]["skip_type"], "op")
        self.assertAlmostEqual(res["intervals"][0]["start_time"], 28.783)
        self.assertEqual(res["intervals"][1]["skip_type"], "ed")
        self.assertEqual(len(calls), 1)
        self.assertIn("api.aniskip.com/v2/skip-times/21/1", calls[0][1])
        self.assertIn("episodeLength=1500", calls[0][1])

    def test_non_integer_episode_rejected_without_network(self):
        called = False

        def fake_http(*args, **kwargs):
            nonlocal called
            called = True
            return 200, "{}"

        for ep in ("12.5", "0", "OVA", "SP1", ""):
            res = aniskip.get_skip_times(
                show_id="show-1",
                episode=ep,
                meta={"name": "Naruto", "malId": "20"},
                http_get=fake_http,
            )
            self.assertFalse(res["found"], ep)
            self.assertEqual(res["reason"], "non_integer_episode")
            self.assertFalse(called, ep)

    def test_bilingual_spanish_season_title_resolves_via_anilist(self):
        anilist_payload = {
            "data": {
                "Page": {
                    "media": [
                        {
                            "id": 16498,
                            "idMal": 16498,
                            "title": {
                                "romaji": "Shingeki no Kyojin",
                                "english": "Attack on Titan",
                                "native": "進撃の巨人",
                            },
                            "synonyms": [],
                            "seasonYear": 2013,
                            "episodes": 25,
                            "format": "TV",
                        },
                        {
                            "id": 20958,
                            "idMal": 25777,
                            "title": {
                                "romaji": "Shingeki no Kyojin Season 2",
                                "english": "Attack on Titan Season 2",
                                "native": "進撃の巨人 Season 2",
                            },
                            "synonyms": [],
                            "seasonYear": 2017,
                            "episodes": 12,
                            "format": "TV",
                        },
                    ]
                }
            }
        }

        def fake_http(url, method="GET", body=None, headers=None, timeout=4.0):
            if "graphql.anilist.co" in url:
                return 200, json.dumps(anilist_payload)
            if "api.aniskip.com/v2/skip-times/25777/3" in url:
                return _aniskip_ok([{
                    "interval": {"startTime": 90.0, "endTime": 180.0},
                    "skipType": "op",
                    "skipId": "s2-op",
                    "episodeLength": 1440.0,
                }])
            raise AssertionError(f"Unexpected URL: {url}")

        res = aniskip.get_skip_times(
            show_id="jkanime:shingeki-no-kyojin-2",
            episode="3",
            meta={"name": "Shingeki no Kyojin Temporada 2 (Sub)"},
            duration=1440.0,
            http_get=fake_http,
        )
        self.assertTrue(res["found"])
        self.assertEqual(res["mal_id"], 25777)
        self.assertEqual(res["source"], "anilist")

    def test_low_confidence_mismatch_fails_safe_to_no_skip(self):
        # AniList only returns Naruto Shippuden when user asked for Naruto.
        anilist_payload = {
            "data": {
                "Page": {
                    "media": [
                        {
                            "id": 1735,
                            "idMal": 1735,
                            "title": {
                                "romaji": "Naruto: Shippuuden",
                                "english": "Naruto Shippuden",
                                "native": "ナルト- 疾風伝",
                            },
                            "synonyms": [],
                            "seasonYear": 2007,
                            "episodes": 500,
                            "format": "TV",
                        }
                    ]
                }
            }
        }
        jikan_payload = {"data": []}

        def fake_http(url, method="GET", body=None, headers=None, timeout=4.0):
            if "graphql.anilist.co" in url:
                return 200, json.dumps(anilist_payload)
            if "api.jikan.moe" in url:
                return 200, json.dumps(jikan_payload)
            raise AssertionError(f"AniSkip must not be called on mismatch: {url}")

        res = aniskip.get_skip_times(
            show_id="jkanime:naruto",
            episode="1",
            meta={"name": "Naruto"},
            http_get=fake_http,
        )
        self.assertFalse(res["found"])
        self.assertIsNone(res["mal_id"])
        self.assertEqual(res["reason"], "mal_id_not_found")

    def test_episode_exceeding_candidate_count_is_rejected(self):
        # Prevents matching episode 105 against a 12-episode season.
        anilist_payload = {
            "data": {
                "Page": {
                    "media": [
                        {
                            "id": 100,
                            "idMal": 999,
                            "title": {"romaji": "My Show", "english": "My Show", "native": ""},
                            "synonyms": [],
                            "seasonYear": 2020,
                            "episodes": 12,
                            "format": "TV",
                        }
                    ]
                }
            }
        }

        def fake_http(url, method="GET", body=None, headers=None, timeout=4.0):
            if "graphql.anilist.co" in url:
                return 200, json.dumps(anilist_payload)
            if "api.jikan.moe" in url:
                return 200, json.dumps({"data": []})
            raise AssertionError(f"Should not query AniSkip: {url}")

        res = aniskip.get_skip_times(
            show_id="jkanime:my-show",
            episode="105",
            meta={"name": "My Show"},
            http_get=fake_http,
        )
        self.assertFalse(res["found"])
        self.assertIsNone(res["mal_id"])

    def test_jikan_fallback_used_when_anilist_fails(self):
        jikan_payload = {
            "data": [
                {
                    "mal_id": 9253,
                    "title": "Steins;Gate",
                    "title_english": "Steins;Gate",
                    "title_japanese": "STEINS;GATE",
                    "title_synonyms": [],
                    "year": 2011,
                    "episodes": 24,
                    "type": "TV",
                }
            ]
        }

        def fake_http(url, method="GET", body=None, headers=None, timeout=4.0):
            if "graphql.anilist.co" in url:
                raise urllib.error.URLError("anilist down")
            if "api.jikan.moe" in url:
                return 200, json.dumps(jikan_payload)
            if "api.aniskip.com/v2/skip-times/9253/1" in url:
                return _aniskip_ok([{
                    "interval": {"startTime": 60.0, "endTime": 150.0},
                    "skipType": "op",
                    "skipId": "sg-op",
                    "episodeLength": 1421.0,
                }])
            raise AssertionError(f"Unexpected URL: {url}")

        res = aniskip.get_skip_times(
            show_id="jkanime:steins-gate",
            episode="1",
            meta={"name": "Steins;Gate"},
            duration=1421.0,
            http_get=fake_http,
        )
        self.assertTrue(res["found"])
        self.assertEqual(res["mal_id"], 9253)
        self.assertEqual(res["source"], "jikan")

    def test_interval_sanitization_drops_invalid_and_clamps_within_tolerance(self):
        raw = [
            # Invalid: negative start
            {"interval": {"startTime": -5.0, "endTime": 80.0}, "skipType": "op", "skipId": "neg"},
            # Invalid: start >= end
            {"interval": {"startTime": 100.0, "endTime": 90.0}, "skipType": "op", "skipId": "inv"},
            # Invalid: too short (< 5s noise)
            {"interval": {"startTime": 10.0, "endTime": 13.0}, "skipType": "op", "skipId": "short"},
            # Invalid: vandalized > 300s OP
            {"interval": {"startTime": 10.0, "endTime": 500.0}, "skipType": "op", "skipId": "huge"},
            # Invalid: starts past duration
            {"interval": {"startTime": 1500.0, "endTime": 1590.0}, "skipType": "ed", "skipId": "past"},
            # Valid: ED ends 3s past duration -> clamped to duration (1420.0)
            {"interval": {"startTime": 1330.0, "endTime": 1423.0}, "skipType": "ed", "skipId": "clamp"},
            # Valid: normal OP
            {"interval": {"startTime": 50.0, "endTime": 140.0}, "skipType": "op", "skipId": "good"},
            # Valid: mixed-op
            {"interval": {"startTime": 200.0, "endTime": 260.0}, "skipType": "mixed-op", "skipId": "mix"},
        ]
        cleaned = aniskip.sanitize_intervals(raw, duration=1420.0)
        ids = [i["skip_id"] for i in cleaned]
        self.assertEqual(ids, ["good", "mix", "clamp"])
        self.assertEqual(cleaned[2]["end_time"], 1420.0)

    def test_404_with_duration_retries_once_with_episode_length_zero(self):
        urls = []

        def fake_http(url, method="GET", body=None, headers=None, timeout=4.0):
            urls.append(url)
            if "episodeLength=1425" in url:
                return _aniskip_404()
            if "episodeLength=0" in url:
                return _aniskip_ok([{
                    "interval": {"startTime": 85.0, "endTime": 175.0},
                    "skipType": "op",
                    "skipId": "wild-op",
                    "episodeLength": 1421.0,
                }])
            raise AssertionError(f"Unexpected URL: {url}")

        res = aniskip.get_skip_times(
            show_id="show-wild",
            episode="2",
            meta={"name": "Test", "malId": "9253"},
            duration=1425.0,
            http_get=fake_http,
        )
        self.assertTrue(res["found"])
        self.assertEqual(len(urls), 2)
        self.assertEqual(res["intervals"][0]["skip_id"], "wild-op")

    def test_upstream_errors_429_500_timeout_fail_gracefully(self):
        for effect in (
            lambda *a, **kw: (429, "rate limited"),
            lambda *a, **kw: (503, "down"),
            lambda *a, **kw: (_ for _ in ()).throw(TimeoutError("timed out")),
        ):
            res = aniskip.get_skip_times(
                show_id="show-err",
                episode="1",
                meta={"name": "Test", "malId": "9253"},
                duration=0.0,
                http_get=effect,
            )
            self.assertFalse(res["found"])
            self.assertEqual(res["intervals"], [])
            self.assertEqual(res["reason"], "upstream_unavailable")

    def test_disk_cache_hit_and_offline_stale_fallback(self):
        calls = 0

        def ok_http(url, method="GET", body=None, headers=None, timeout=4.0):
            nonlocal calls
            calls += 1
            return _aniskip_ok([{
                "interval": {"startTime": 30.0, "endTime": 120.0},
                "skipType": "op",
                "skipId": "cached-op",
                "episodeLength": 1440.0,
            }])

        # First call populates disk cache.
        r1 = aniskip.get_skip_times(
            show_id="show-cache",
            episode="4",
            meta={"name": "Cached Show", "malId": "21"},
            duration=1440.0,
            http_get=ok_http,
        )
        self.assertTrue(r1["found"])
        self.assertEqual(calls, 1)

        # Second call hits disk cache without HTTP.
        r2 = aniskip.get_skip_times(
            show_id="show-cache",
            episode="4",
            meta={"name": "Cached Show", "malId": "21"},
            duration=1440.0,
            http_get=ok_http,
        )
        self.assertTrue(r2["found"])
        self.assertTrue(r2["cached"])
        self.assertEqual(calls, 1)

        # Expire cache timestamp manually and simulate offline network failure -> stale fallback!
        cache_file = aniskip._episode_cache_path(21, 4)
        with open(cache_file, encoding="utf-8") as fh:
            entry = json.load(fh)
        entry["fetched_at"] = time.time() - (aniskip.TTL_EPISODE_OK + 100)
        with open(cache_file, "w", encoding="utf-8") as fh:
            json.dump(entry, fh)

        def offline_http(*args, **kwargs):
            raise urllib.error.URLError("offline")

        r3 = aniskip.get_skip_times(
            show_id="show-cache",
            episode="4",
            meta={"name": "Cached Show", "malId": "21"},
            duration=1440.0,
            http_get=offline_http,
        )
        self.assertTrue(r3["found"])
        self.assertTrue(r3["stale"])
        self.assertEqual(r3["intervals"][0]["skip_id"], "cached-op")


if __name__ == "__main__":
    unittest.main()
