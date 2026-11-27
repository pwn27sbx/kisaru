"""HTTP contracts for HentaiLA as a normal anime source."""

import ast
import os
import sys
import unittest
from pathlib import Path
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
class NormalSourceRoutesTest(unittest.TestCase):
    def setUp(self):
        self.client = anime_server.app.test_client()
        patcher = mock.patch.dict(os.environ, {"QS_HENTAILA_SOURCE": "on"})
        patcher.start()
        self.addCleanup(patcher.stop)
        hentaila_source.clear_cache()

    def test_normal_search_falls_back_to_hentaila_and_prefixes_ids(self):
        with mock.patch.object(anime_server, "search_anime", return_value=[]), \
             mock.patch.object(anime_server.jkanime_source, "search", return_value=[]), \
             mock.patch.object(hentaila_source, "search", return_value={
                 "results": [dict(ITEM)], "hasMore": True, "nextPage": 2,
             }) as search:
            response = self.client.get("/search", query_string={"q": "sample", "mode": "sub"})
        self.assertEqual(response.status_code, 200)
        body = response.get_json()
        self.assertEqual(body["count"], 1)
        self.assertEqual(body["results"][0]["id"], "hentaila:item-one")
        search.assert_called_once_with("sample", 1)

    def test_existing_primary_results_keep_the_current_fallback_order(self):
        primary = [dict(ITEM, id="primary")]
        with mock.patch.object(anime_server, "search_anime", return_value=primary), \
             mock.patch.object(anime_server.jkanime_source, "search") as jkanime, \
             mock.patch.object(hentaila_source, "search") as hentaila:
            response = self.client.get("/search", query_string={"q": "sample"})
        self.assertEqual(response.get_json()["results"], primary)
        jkanime.assert_not_called()
        hentaila.assert_not_called()

    def test_kill_switch_off_skips_hentaila_without_breaking_normal_search(self):
        with mock.patch.dict(os.environ, {"QS_HENTAILA_SOURCE": "off"}), \
             mock.patch.object(anime_server, "search_anime", return_value=[]), \
             mock.patch.object(anime_server.jkanime_source, "search", return_value=[]), \
             mock.patch.object(hentaila_source, "search") as search:
            response = self.client.get("/search", query_string={"q": "sample"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["results"], [])
        search.assert_not_called()

    def test_generic_episodes_route_dispatches_hentaila_ids(self):
        with mock.patch.object(hentaila_source, "series", return_value=dict(SERIES)) as series, \
             mock.patch.object(anime_server, "episodes_list") as primary:
            response = self.client.get("/episodes", query_string={"id": "hentaila:item-one"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["episodes"], ["1", "2"])
        series.assert_called_once_with("item-one")
        primary.assert_not_called()

    def test_generic_links_route_dispatches_hentaila_ids(self):
        with mock.patch.object(hentaila_source, "links", return_value=[dict(LINK)]) as links, \
             mock.patch.object(anime_server, "get_episode_links") as primary:
            response = self.client.get(
                "/links", query_string={"id": "hentaila:item-one", "ep": "1"}
            )
        self.assertEqual(response.status_code, 200)
        body = response.get_json()
        self.assertEqual(body["selected"]["provider"], "HentaiLA")
        self.assertEqual(body["show_id"], "hentaila:item-one")
        links.assert_called_once_with("item-one", "1")
        primary.assert_not_called()

    def test_disabled_hentaila_detail_routes_do_not_reach_upstream(self):
        with mock.patch.dict(os.environ, {"QS_HENTAILA_SOURCE": "off"}), \
             mock.patch.object(hentaila_source, "series") as series, \
             mock.patch.object(hentaila_source, "links") as links:
            episodes = self.client.get("/episodes", query_string={"id": "hentaila:item-one"})
            stream = self.client.get(
                "/links", query_string={"id": "hentaila:item-one", "ep": "1"}
            )
        self.assertEqual(episodes.status_code, 404)
        self.assertEqual(stream.status_code, 404)
        self.assertEqual(episodes.get_json(), {"error": "source_disabled"})
        self.assertEqual(stream.get_json(), {"error": "source_disabled"})
        series.assert_not_called()
        links.assert_not_called()

    def test_source_errors_never_expose_provider_data(self):
        with mock.patch.object(hentaila_source, "series", side_effect=hentaila_source.SourceError("network_error")):
            response = self.client.get("/episodes", query_string={"id": "hentaila:item-one"})
        self.assertEqual(response.status_code, 502)
        self.assertEqual(response.get_json(), {"error": "source_unavailable"})

    def test_empty_hentaila_links_have_a_fixed_no_stream_error(self):
        with mock.patch.object(hentaila_source, "links", return_value=[]):
            response = self.client.get(
                "/links", query_string={"id": "hentaila:item-one", "ep": "1"}
            )
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.get_json(), {"error": "no_stream"})

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

    def test_access_log_redacts_normal_search_queries_and_source_ids(self):
        from werkzeug.serving import WSGIRequestHandler

        tree = ast.parse(Path(anime_server.__file__).read_text(encoding="utf-8"))
        node = next(
            item for item in ast.walk(tree)
            if isinstance(item, ast.ClassDef)
            and any(isinstance(base, ast.Name) and base.id == "WSGIRequestHandler" for base in item.bases)
        )
        namespace = {"WSGIRequestHandler": WSGIRequestHandler}
        exec(
            compile(ast.Module(body=[node], type_ignores=[]), anime_server.__file__, "exec"),
            namespace,
        )
        handler = object.__new__(namespace[node.name])
        handler.command = "GET"
        handler.request_version = "HTTP/1.1"
        handler.client_address = ("127.0.0.1", 12345)

        for request_path, secret in (
            ("/search?q=secret-query&title=secret-title", "secret-query"),
            ("/episodes?id=hentaila%3Asecret-slug", "secret-slug"),
        ):
            with self.subTest(path=request_path):
                handler.path = request_path
                handler.requestline = "GET " + handler.path + " HTTP/1.1"
                with mock.patch("werkzeug.serving._log") as logged:
                    handler.log_request(200, 123)
                message = logged.call_args.args[2]
                self.assertNotIn(secret, message)
                self.assertNotIn("secret-title", message)


if __name__ == "__main__":
    unittest.main()
