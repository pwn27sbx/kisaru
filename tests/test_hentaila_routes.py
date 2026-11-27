"""HTTP and playback contracts for the private anime source routes."""

import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

try:
    import anime_server
except Exception as exc:  # Flask/requests unavailable in a bare environment.
    anime_server = None
    SKIP = f"anime_server unavailable: {exc}"
else:
    SKIP = ""

import hentaila_source

ITEM = {
    "id": "item-one",
    "name": "Sample item",
    "english_name": "Sample item",
    "native_name": "",
    "thumbnail": "https://cdn.example/cover.jpg",
    "score": None,
    "episode_count": "",
    "available_episodes": {"sub": 1, "dub": 0, "raw": 0},
}
SERIES = {
    "id": "item-one",
    "name": "Sample series",
    "thumbnail": "https://cdn.example/cover.jpg",
    "episodes": ["1", "2"],
}
LINK = {
    "quality": "best",
    "url": "https://cdn.example/m3u8/token",
    "type": "m3u8",
    "provider": "HentaiLA",
    "referer": "https://cdn.example/play/token",
    "subtitle": "",
    "subtitle_label": "Español",
}


@unittest.skipIf(anime_server is None, SKIP)
class PrivateRoutesTest(unittest.TestCase):
    def setUp(self):
        self.client = anime_server.app.test_client()
        patcher = mock.patch.dict(os.environ, {"QS_HENTAILA_SOURCE": "on"})
        patcher.start()
        self.addCleanup(patcher.stop)
        hentaila_source.clear_cache()

    def test_search_prefixes_ids_and_returns_pagination(self):
        with mock.patch.object(hentaila_source, "search", return_value={
            "results": [dict(ITEM)], "hasMore": True, "nextPage": 2,
        }) as search:
            response = self.client.get("/hentaila/search", query_string={"q": "sample", "page": 1})
        self.assertEqual(response.status_code, 200)
        body = response.get_json()
        self.assertEqual(body["results"][0]["id"], "hentaila:item-one")
        self.assertTrue(body["hasMore"])
        search.assert_called_once_with("sample", 1)

    def test_kill_switch_off_returns_fixed_404_without_upstream(self):
        with mock.patch.dict(os.environ, {"QS_HENTAILA_SOURCE": "off"}), \
             mock.patch.object(hentaila_source, "search") as search:
            response = self.client.get("/hentaila/search", query_string={"q": "sample"})
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.get_json(), {"error": "source_disabled"})
        search.assert_not_called()

    def test_series_route_returns_episodes(self):
        with mock.patch.object(hentaila_source, "series", return_value=dict(SERIES)) as series:
            response = self.client.get("/hentaila/series", query_string={"id": "item-one"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["id"], "hentaila:item-one")
        self.assertEqual(response.get_json()["episodes"], ["1", "2"])
        series.assert_called_once_with("item-one")

    def test_links_route_returns_selected_private_link(self):
        with mock.patch.object(hentaila_source, "links", return_value=[dict(LINK)]) as links:
            response = self.client.get("/hentaila/links", query_string={"id": "item-one", "ep": "1"})
        self.assertEqual(response.status_code, 200)
        body = response.get_json()
        self.assertEqual(body["selected"]["provider"], "HentaiLA")
        self.assertEqual(body["show_id"], "hentaila:item-one")
        links.assert_called_once_with("item-one", "1")

    def test_source_errors_never_expose_provider_data(self):
        with mock.patch.object(hentaila_source, "search", side_effect=hentaila_source.SourceError("network_error")):
            response = self.client.get("/hentaila/search", query_string={"q": "sample"})
        self.assertEqual(response.status_code, 502)
        self.assertEqual(response.get_json(), {"error": "source_unavailable"})

    def test_generic_routes_reject_private_ids_before_upstream(self):
        with mock.patch.object(anime_server, "episodes_list") as episodes, \
             mock.patch.object(anime_server, "get_episode_links") as links:
            response = self.client.get("/episodes", query_string={"id": "hentaila:item-one"})
            response2 = self.client.get("/links", query_string={"id": "hentaila:item-one", "ep": "1"})
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response2.status_code, 404)
        episodes.assert_not_called()
        links.assert_not_called()

    def test_skip_times_are_disabled_before_metadata_or_enrichment(self):
        with mock.patch.object(anime_server, "_show_meta") as meta, \
             mock.patch.object(anime_server.aniskip, "get_skip_times") as skip:
            response = self.client.get("/skip-times", query_string={
                "id": "hentaila:item-one", "ep": "1", "title": "Sample title",
            })
        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.get_json()["found"])
        self.assertEqual(response.get_json()["reason"], "disabled_for_source")
        meta.assert_not_called()
        skip.assert_not_called()

    def test_missing_parameters_are_fixed_400_errors(self):
        for path in ("/hentaila/search", "/hentaila/series", "/hentaila/links"):
            with self.subTest(path=path):
                self.assertEqual(self.client.get(path).status_code, 400)

    def test_private_access_log_redacts_query_and_title(self):
        import ast
        from pathlib import Path
        from werkzeug.serving import WSGIRequestHandler

        tree = ast.parse(Path(anime_server.__file__).read_text(encoding="utf-8"))
        node = next(
            item for item in ast.walk(tree)
            if isinstance(item, ast.ClassDef) and item.name == "PrivateSafeRequestHandler"
        )
        namespace = {"WSGIRequestHandler": WSGIRequestHandler}
        exec(
            compile(ast.Module(body=[node], type_ignores=[]), anime_server.__file__, "exec"),
            namespace,
        )
        handler = object.__new__(namespace["PrivateSafeRequestHandler"])
        handler.command = "GET"
        handler.request_version = "HTTP/1.1"
        handler.path = "/hentaila/search?q=secret-query&title=secret-title"
        handler.requestline = "GET " + handler.path + " HTTP/1.1"
        handler.client_address = ("127.0.0.1", 12345)

        with mock.patch("werkzeug.serving._log") as logged:
            handler.log_request(200, 123)

        message = logged.call_args.args[2]
        self.assertNotIn("secret-query", message)
        self.assertNotIn("secret-title", message)


if __name__ == "__main__":
    unittest.main()
