"""Tests for the GET /skip-times route in scripts/anime_server.py (WU-2).

Uses Flask's test client when flask/requests are installed (CI / app venv),
plus a lightweight fallback stub when running under bare system python so the
route wiring is always exercised without live network calls.

Run: python3 -m unittest tests/test_anime_skip_route.py
"""

import os
import sys
import types
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))


def _import_anime_server():
    try:
        import anime_server  # noqa: PLC0415
        return anime_server, True
    except ModuleNotFoundError:
        # Provide minimal stubs for flask & requests so route helpers can be
        # tested under bare system python without touching the real venv.
        fake_requests = types.ModuleType("requests")
        fake_requests.RequestException = Exception
        fake_requests.HTTPError = Exception

        class _FakeArgs(dict):
            def get(self, key, default=""):
                return super().get(key, default)

        class _FakeRequest:
            args = _FakeArgs()

        class _FakeApp:
            def __init__(self, _name):
                self.routes = {}

            def route(self, path, **_kw):
                def deco(fn):
                    self.routes[path] = fn
                    return fn
                return deco

        fake_flask = types.ModuleType("flask")
        fake_flask.Flask = _FakeApp
        fake_flask.jsonify = lambda obj: obj
        fake_flask.request = _FakeRequest()

        with mock.patch.dict(sys.modules, {"flask": fake_flask, "requests": fake_requests}):
            import anime_server  # noqa: PLC0415
        return anime_server, False


anime_server, HAS_FLASK = _import_anime_server()


class SkipTimesRouteTest(unittest.TestCase):
    def _call_route(self, params):
        if HAS_FLASK:
            client = anime_server.app.test_client()
            resp = client.get("/skip-times", query_string=params)
            return resp.status_code, resp.get_json()
        anime_server.request.args = type(anime_server.request.args)(params)
        result = anime_server.skip_times_route()
        if isinstance(result, tuple):
            return result[1], result[0]
        return 200, result

    def test_missing_id_or_ep_returns_400(self):
        code, body = self._call_route({"ep": "1"})
        self.assertEqual(code, 400)
        self.assertIn("error", body)

        code2, body2 = self._call_route({"id": "show-1"})
        self.assertEqual(code2, 400)
        self.assertIn("error", body2)

    def test_allanime_show_uses_show_meta_and_returns_intervals(self):
        expected = {
            "found": True,
            "mal_id": 21,
            "source": "allanime",
            "intervals": [{"skip_type": "op", "skip_id": "op-1", "start_time": 28.0, "end_time": 118.0}],
            "cached": False,
            "stale": False,
            "reason": "ok",
        }
        with mock.patch.object(
            anime_server, "_show_meta",
            return_value={"name": "One Piece", "englishName": "One Piece", "malId": "21"},
        ) as meta_mock, mock.patch.object(
            anime_server.aniskip, "get_skip_times", return_value=expected,
        ) as skip_mock:
            code, body = self._call_route({"id": "abc123", "ep": "1", "duration": "1500"})

        self.assertEqual(code, 200)
        self.assertTrue(body["found"])
        self.assertEqual(body["mal_id"], 21)
        meta_mock.assert_called_once_with("abc123")
        _, kwargs = skip_mock.call_args
        self.assertEqual(kwargs["duration"], 1500.0)
        self.assertEqual(kwargs["meta"]["malId"], "21")

    def test_jkanime_show_uses_title_without_calling_allanime_meta(self):
        expected = {
            "found": True,
            "mal_id": 9253,
            "source": "anilist",
            "intervals": [],
            "cached": False,
            "stale": False,
            "reason": "ok",
        }
        with mock.patch.object(anime_server, "_show_meta") as meta_mock, \
             mock.patch.object(anime_server.aniskip, "get_skip_times", return_value=expected) as skip_mock:
            code, body = self._call_route({
                "id": "jkanime:steins-gate",
                "ep": "1",
                "title": "Steins;Gate",
                "duration": "1420",
            })

        self.assertEqual(code, 200)
        meta_mock.assert_not_called()
        _, kwargs = skip_mock.call_args
        self.assertEqual(kwargs["meta"]["name"], "Steins;Gate")

    def test_invalid_duration_defaults_to_zero_without_500(self):
        with mock.patch.object(anime_server, "_show_meta", return_value={"name": "X", "englishName": "", "malId": "1"}), \
             mock.patch.object(anime_server.aniskip, "get_skip_times", return_value={"found": False, "intervals": []}) as skip_mock:
            code, _ = self._call_route({"id": "x", "ep": "1", "duration": "not-a-number"})
        self.assertEqual(code, 200)
        self.assertEqual(skip_mock.call_args[1]["duration"], 0.0)

    def test_unexpected_exception_returns_safe_empty_200(self):
        with mock.patch.object(anime_server, "_show_meta", side_effect=RuntimeError("boom")):
            code, body = self._call_route({"id": "x", "ep": "1"})
        self.assertEqual(code, 200)
        self.assertFalse(body["found"])
        self.assertEqual(body["intervals"], [])


if __name__ == "__main__":
    unittest.main()
