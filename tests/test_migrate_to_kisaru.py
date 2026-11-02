"""The local data migration (owner decisions D3, D4 and D6).

Every test runs against a throw-away HOME in a temporary directory: the real
~/.local, ~/.cache and ~/.config are never read or written.
"""

import json
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))

import migrate_to_kisaru as mig


class Base(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp(prefix="kisaru-home-")
        self.addCleanup(shutil.rmtree, self.home, True)
        self.data = os.path.join(self.home, ".local", "share")
        self.cache = os.path.join(self.home, ".cache")
        self.config = os.path.join(self.home, ".config")
        self.legacy_libs = os.path.join(self.data, "quickshell")
        os.makedirs(self.legacy_libs)

    def write(self, path, text):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)
        return path

    def run_tool(self, *extra):
        return mig.main(["--home", self.home, "--data", self.data,
                         "--cache", self.cache, "--config", self.config, *extra])


class DryRun(Base):
    def test_nothing_is_written_without_apply(self):
        self.write(os.path.join(self.legacy_libs, "manga_library.json"), '{"a": 1}')
        self.assertEqual(self.run_tool(), 0)
        self.assertFalse(os.path.exists(os.path.join(self.data, "kisaru", "manga_library.json")))


class Copy(Base):
    def test_the_library_is_copied_and_the_inherited_file_stays(self):
        src = self.write(os.path.join(self.legacy_libs, "manga_library.json"), '{"a": 1}')
        self.assertEqual(self.run_tool("--apply"), 0)
        dst = os.path.join(self.data, "kisaru", "manga_library.json")
        self.assertTrue(os.path.isfile(dst))
        self.assertTrue(os.path.isfile(src), "the inherited library was removed")
        with open(dst, encoding="utf-8") as fh:
            self.assertEqual(fh.read(), '{"a": 1}')

    def test_the_secrets_keep_mode_600(self):
        src = self.write(os.path.join(self.config, "qs-nmr", "canary.env"), "TOKEN=1\n")
        os.chmod(src, 0o600)
        self.assertEqual(self.run_tool("--apply"), 0)
        dst = os.path.join(self.config, "kisaru-canary", "canary.env")
        self.assertEqual(os.stat(dst).st_mode & 0o777, 0o600)

    def test_the_cover_cache_is_copied_file_by_file(self):
        self.write(os.path.join(self.cache, "qs-novelmangareader", "covers", "a.img"), "x")
        self.write(os.path.join(self.cache, "qs-novelmangareader", "covers", "b.img"), "y")
        self.assertEqual(self.run_tool("--apply"), 0)
        new = os.path.join(self.cache, "kisaru", "covers")
        self.assertEqual(sorted(os.listdir(new)), ["a.img", "b.img"])

    def test_the_two_download_folders_do_not_collide(self):
        self.write(os.path.join(self.data, "quickshell-manga", "downloads", "m", "ch1.txt"), "m")
        self.write(os.path.join(self.data, "quickshell-novel", "downloads", "n", "ch1.txt"), "n")
        self.assertEqual(self.run_tool("--apply"), 0)
        self.assertTrue(os.path.isfile(os.path.join(self.data, "kisaru", "manga", "downloads", "m", "ch1.txt")))
        self.assertTrue(os.path.isfile(os.path.join(self.data, "kisaru", "novel", "downloads", "n", "ch1.txt")))


class Idempotence(Base):
    def test_a_second_run_does_nothing_and_says_so(self):
        self.write(os.path.join(self.legacy_libs, "manga_library.json"), '{"a": 1}')
        self.assertEqual(self.run_tool("--apply"), 0)
        marker = mig.load_marker(mig.marker_path(self.home, self.data))
        self.assertEqual(len(marker["entries"]), 1)
        self.assertEqual(self.run_tool("--apply"), 0)
        with open(mig.marker_path(self.home, self.data), encoding="utf-8") as fh:
            self.assertEqual(json.load(fh)["entries"], marker["entries"])


class Refusals(Base):
    def test_a_destination_with_other_content_is_not_overwritten(self):
        self.write(os.path.join(self.legacy_libs, "manga_library.json"), '{"old": 1}')
        self.write(os.path.join(self.data, "kisaru", "manga_library.json"), '{"new": 1}')
        self.assertEqual(self.run_tool("--apply"), 2)
        with open(os.path.join(self.data, "kisaru", "manga_library.json"), encoding="utf-8") as fh:
            self.assertEqual(fh.read(), '{"new": 1}')

    def test_secrets_are_never_written_inside_a_git_work_tree(self):
        os.makedirs(os.path.join(self.home, ".git"))
        self.write(os.path.join(self.config, "qs-nmr", "canary.env"), "TOKEN=1\n")
        self.assertEqual(self.run_tool("--apply"), 2)
        self.assertFalse(os.path.exists(os.path.join(self.config, "kisaru-canary", "canary.env")))

    def test_an_empty_run_is_clean(self):
        self.assertEqual(self.run_tool("--apply"), 0)


class Layout(Base):
    def test_the_plan_names_every_artifact_the_app_reads(self):
        labels = [s.label for s in mig.build_steps(self.home, self.data, self.cache, self.config)]
        self.assertEqual(labels, [
            "manga library", "anime library", "novel library", "manga data", "novel data",
            "cover cache", "chapter cache", "canary secrets",
        ])

    def test_the_marker_lives_under_the_data_root_not_the_config_one(self):
        # ~/.config/kisaru is a symlink to the checkout on the real machine, so
        # the marker must never be derived from it.
        self.assertEqual(mig.marker_path(self.home, self.data),
                         os.path.join(self.data, "kisaru", mig.MARKER_NAME))

    def test_a_second_run_replaces_only_what_the_marker_recorded(self):
        self.write(os.path.join(self.legacy_libs, "manga_library.json"), '{"v": 1}')
        self.assertEqual(self.run_tool("--apply"), 0)
        # The user edits the migrated copy; a re-run must not undo that.
        dst = os.path.join(self.data, "kisaru", "manga_library.json")
        self.write(dst, '{"v": 1, "edited": true}')
        self.assertEqual(self.run_tool("--apply"), 2)
        with open(dst, encoding="utf-8") as fh:
            self.assertIn("edited", fh.read())

    def test_an_interrupted_copy_leaves_no_partial_tree_behind(self):
        self.write(os.path.join(self.data, "quickshell-manga", "downloads", "a", "x.txt"), "x")
        self.assertEqual(self.run_tool("--apply"), 0)
        self.assertFalse(os.path.exists(os.path.join(self.data, "kisaru", "manga.partial")))

    def test_a_secret_already_in_place_still_gets_mode_600(self):
        self.write(os.path.join(self.config, "qs-nmr", "canary.env"), "TOKEN=1\n")
        dst = os.path.join(self.config, "kisaru-canary", "canary.env")
        self.write(dst, "TOKEN=1\n")
        os.chmod(dst, 0o644)
        self.run_tool("--apply")
        self.assertEqual(os.stat(dst).st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
