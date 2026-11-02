"""The app's identity and the shared path rule (owner decisions D6, D8).

No network, no real HOME: every check runs inside a temporary directory.
"""

import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

import app_meta


class UserAgent(unittest.TestCase):
    def test_the_user_agent_is_kisaru_with_the_manifest_version(self):
        ua = app_meta.user_agent()
        self.assertTrue(ua.startswith("kisaru/"), ua)
        self.assertIn("+https://github.com/pwn27sbx/kisaru", ua)
        manifest = os.path.join(
            os.path.dirname(__file__), "..", "omarchy", "pwnsxb.kisaru", "manifest.json"
        )
        with open(manifest, encoding="utf-8") as fh:
            self.assertEqual(app_meta.version(), json.load(fh)["version"])

    def test_an_unreadable_manifest_does_not_break_the_user_agent(self):
        saved = app_meta._MANIFEST, app_meta._version
        app_meta._MANIFEST, app_meta._version = "/nonexistent/manifest.json", None
        try:
            self.assertEqual(app_meta.version(), "0")
            self.assertIn("kisaru/0 ", app_meta.user_agent())
        finally:
            app_meta._MANIFEST, app_meta._version = saved


class PathRule(unittest.TestCase):
    def test_new_directory_wins_when_both_exist(self):
        with tempfile.TemporaryDirectory() as tmp:
            new, old = os.path.join(tmp, "new"), os.path.join(tmp, "old")
            os.makedirs(new), os.makedirs(old)
            self.assertEqual(app_meta.resolve_dir(new, old), new)

    def test_inherited_directory_is_used_while_it_is_the_only_one(self):
        with tempfile.TemporaryDirectory() as tmp:
            new, old = os.path.join(tmp, "new"), os.path.join(tmp, "old")
            os.makedirs(old)
            self.assertEqual(app_meta.resolve_dir(new, old), old)

    def test_neither_existing_means_the_new_name(self):
        with tempfile.TemporaryDirectory() as tmp:
            new, old = os.path.join(tmp, "new"), os.path.join(tmp, "old")
            self.assertEqual(app_meta.resolve_dir(new, old), new)

    def test_the_inherited_roots_ignore_xdg_on_purpose(self):
        # The old code wrote ~/.local/share and ~/.cache literally; pointing the
        # fallback at XDG_DATA_HOME would look in the wrong place.
        self.assertTrue(app_meta.LEGACY_DATA_HOME.endswith("/.local/share"))
        self.assertTrue(app_meta.LEGACY_CACHE_HOME.endswith("/.cache"))

    def test_content_decides_between_the_two_roots(self):
        with tempfile.TemporaryDirectory() as tmp:
            new, old = os.path.join(tmp, "new"), os.path.join(tmp, "old")
            os.makedirs(new)                      # e.g. only the venv lives here
            os.makedirs(os.path.join(old, "downloads"))
            self.assertEqual(
                app_meta.resolve_by_content(new, old, ("favorites.json", "downloads")), old)
            os.makedirs(os.path.join(new, "downloads"))
            self.assertEqual(
                app_meta.resolve_by_content(new, old, ("favorites.json", "downloads")), new)

            empty, older = os.path.join(tmp, "e"), os.path.join(tmp, "o")
            os.makedirs(empty)
            self.assertEqual(app_meta.resolve_by_content(empty, older, ("downloads",)), empty)

    def test_xdg_homes_are_respected(self):
        env = {"XDG_CACHE_HOME": "/c", "XDG_DATA_HOME": "/d", "XDG_CONFIG_HOME": "/g"}
        self.assertEqual(app_meta.cache_home(env), "/c")
        self.assertEqual(app_meta.data_home(env), "/d")
        self.assertEqual(app_meta.config_home(env), "/g")


class CanarySecrets(unittest.TestCase):
    def test_the_secrets_file_prefers_the_new_folder_and_sits_outside_the_repo(self):
        with tempfile.TemporaryDirectory() as cfg:
            env = {"XDG_CONFIG_HOME": cfg}
            self.assertEqual(app_meta.canary_env_path(env),
                             os.path.join(cfg, "kisaru-canary", "canary.env"))
            self.assertNotIn("/Projects/", app_meta.canary_env_path(env))

    def test_the_inherited_secrets_file_is_used_while_it_is_the_only_one(self):
        with tempfile.TemporaryDirectory() as cfg:
            env = {"XDG_CONFIG_HOME": cfg}
            legacy = os.path.join(cfg, "qs-nmr")
            os.makedirs(legacy)
            old = os.path.join(legacy, "canary.env")
            open(old, "w").close()
            self.assertEqual(app_meta.canary_env_path(env), old)

            new = os.path.join(cfg, "kisaru-canary", "canary.env")
            os.makedirs(os.path.dirname(new))
            open(new, "w").close()
            self.assertEqual(app_meta.canary_env_path(env), new)


class CoverCache(unittest.TestCase):
    def test_the_cover_cache_follows_the_new_name_and_falls_back(self):
        try:
            import manga_server
        except Exception as exc:  # flask/requests missing
            self.skipTest(f"manga_server unavailable: {exc}")

        with tempfile.TemporaryDirectory() as cache:
            saved = os.environ.get("XDG_CACHE_HOME")
            os.environ["XDG_CACHE_HOME"] = cache
            try:
                # Nothing exists yet: the new folder (the writer's target).
                self.assertEqual(manga_server.img_cache_dir(),
                                 os.path.join(cache, "kisaru", "covers"))
                # Only the inherited cache exists: read it, do not start empty.
                legacy = os.path.join(cache, "qs-novelmangareader", "covers")
                os.makedirs(legacy)
                self.assertEqual(manga_server.img_cache_dir(), legacy)
                # Both: the new one wins.
                os.makedirs(os.path.join(cache, "kisaru", "covers"))
                self.assertEqual(manga_server.img_cache_dir(),
                                 os.path.join(cache, "kisaru", "covers"))
            finally:
                if saved is None:
                    os.environ.pop("XDG_CACHE_HOME", None)
                else:
                    os.environ["XDG_CACHE_HOME"] = saved


if __name__ == "__main__":
    unittest.main()
