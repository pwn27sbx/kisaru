"""The small CLI and launch-path defects.

`ensure_instance` always slept a fixed 3 s, the mpv URL went in without `--`,
and `--debug` enabled the Werkzeug debugger (audit 2026-11-06, findings 21, 22
and 36). Finding 20 (documenting `privado` in the help) is not here on
purpose: an existing test keeps the private mode out of the help, so it is an
owner decision, not a defect to fix silently.

Run from the repo root:
    python3 -m unittest tests.test_cli_small_fixes
"""

import os
import re
import stat
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def read(relative):
    with open(os.path.join(ROOT, relative), encoding="utf-8") as fh:
        return fh.read()


class EnsureInstanceTest(unittest.TestCase):
    def test_it_polls_until_the_ipc_answers_instead_of_sleeping_fixed(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = os.path.join(tmp, "config")
            os.makedirs(os.path.join(config, "kisaru"))
            open(os.path.join(config, "kisaru", "shell.qml"), "w").close()
            log = os.path.join(tmp, "qs.log")
            bin_dir = os.path.join(tmp, "bin")
            os.makedirs(bin_dir)
            fake = os.path.join(bin_dir, "qs")
            with open(fake, "w") as fh:
                fh.write("""#!/usr/bin/env bash
echo "$*" >> "%s"
case "$*" in
    *"ipc show"*)
        n=$(grep -c "ipc show" "%s")
        (( n >= 3 )) && exit 0
        exit 1
        ;;
esac
exit 0
""" % (log, log))
            os.chmod(fake, os.stat(fake).st_mode | stat.S_IXUSR)

            env = dict(os.environ,
                       PATH=bin_dir + os.pathsep + os.environ["PATH"],
                       XDG_CONFIG_HOME=config)
            result = subprocess.run(
                ["bash", os.path.join(ROOT, "bin", "kisaru"), "anime"],
                capture_output=True, text=True, timeout=30, env=env,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = open(log).read()
            self.assertGreaterEqual(calls.count("ipc show"), 3, calls)
            self.assertIn("ipc call animePlayer toggle", calls)


class MpvTest(unittest.TestCase):
    def test_the_url_is_passed_after_a_double_dash(self):
        text = read("modules/anime/components/DetailView.qml")
        self.assertRegex(text, r'args\.push\("--"\)\s*\n\s*args\.push\(url\)')


class AnimeDebugTest(unittest.TestCase):
    def test_the_debug_flag_does_not_start_the_interactive_debugger(self):
        text = read("scripts/anime_server.py")
        self.assertNotIn("debug=args.debug", text)
        self.assertIn("debug=False", text)


if __name__ == "__main__":
    unittest.main()
