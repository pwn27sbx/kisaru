"""The installer ships what Omarchy needs, verified, and only those paths.

Findings 11, 13, 14, 19, 23 and 24 of the 2026-11-06 audit: an unverified
"latest" font download, a canary the docs run directly but that has no
shebang, a systemd unit pointing at a checkout path and the system Python,
apt/dnf and Sway paths for a project that requires Omarchy, no fontconfig
even though `fc-list` is used, and a `--copy` that left stale files behind.

Run from the repo root:
    python3 -m unittest tests.test_installer
"""

import os
import shlex
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def read(relative):
    with open(os.path.join(ROOT, relative), encoding="utf-8") as fh:
        return fh.read()


class FontTest(unittest.TestCase):
    def test_the_font_is_downloaded_from_a_pinned_release_and_verified(self):
        text = read("scripts/install-common.sh")
        self.assertNotIn("releases/latest", text)
        self.assertRegex(text, r"NERD_FONT_VERSION=\"[0-9]+\.[0-9]+\.[0-9]+\"")
        self.assertRegex(text, r"NERD_FONT_SHA256=\"[0-9a-f]{64}\"")
        self.assertIn("sha256sum", text)
        self.assertIn("NERD_FONT_SHA256", text)


class PackagesTest(unittest.TestCase):
    def test_fontconfig_is_a_dependency(self):
        install = read("install.sh")
        self.assertRegex(install, r"PACMAN_PKGS=\([^)]*fontconfig")
        self.assertRegex(install, r"PACMAN_PKGS=\([^)]*rsync")

    def test_the_installer_only_supports_arch(self):
        install = read("install.sh")
        common = read("scripts/install-common.sh")
        self.assertNotIn("APT_PKGS", install)
        self.assertNotIn("DNF_PKGS", install)
        self.assertNotIn("apt-get update", common)
        self.assertNotIn("dnf install", common)
        self.assertIn("solo admite Arch", common)

    def test_the_readme_drops_the_unsupported_compositor_and_distros(self):
        text = read("README.md")
        self.assertNotIn("Sway:", text)
        self.assertNotIn("dnf en Fedora", text)
        self.assertNotIn("apt en Debian", text)


class CopyTest(unittest.TestCase):
    def test_the_copy_update_deletes_stale_files_and_skips_development_folders(self):
        text = read("scripts/install-common.sh")
        self.assertIn("rsync", text)
        self.assertRegex(text, r"rsync[^\n]*--delete")
        for excluded in (".git", "odd", "tests", "settings.json", "colors/Colors.json"):
            self.assertIn(excluded, text, excluded)


class CanaryTest(unittest.TestCase):
    def test_the_canary_can_run_directly(self):
        path = os.path.join(ROOT, "scripts", "source_canary.py")
        with open(path, encoding="utf-8") as fh:
            first = fh.readline()
        self.assertTrue(first.startswith("#!"), first)
        mode = os.stat(path).st_mode
        self.assertTrue(mode & stat.S_IXUSR, "source_canary.py is not executable")

    def test_the_unit_uses_the_installed_config_and_venv(self):
        text = read("extras/systemd/kisaru-canary.service")
        self.assertIn("%h/.config/kisaru/scripts/source_canary.py", text)
        self.assertIn("%h/.local/share/kisaru/venv/bin/python3", text)
        self.assertNotIn("%h/Projects/kisaru", text)


class MarkerTest(unittest.TestCase):
    """Finding 34: the copy marker is kisaru's, and old copies still update.

    `install_config` used to recognise only `.package-export`, the marker the
    upstream shell generated. The marker is now kisaru's, and a copy made by
    an earlier install must keep being recognised when it is updated.
    """

    def setUp(self):
        tmp = tempfile.mkdtemp(prefix="kisaru-installer-")
        self.addCleanup(shutil.rmtree, tmp)
        self.src = os.path.join(tmp, "src")
        os.makedirs(self.src)
        with open(os.path.join(self.src, ".kisaru-package"), "w", encoding="utf-8") as fh:
            fh.write("Installed copy of kisaru by its install.sh; see NOTICE.\n")
        with open(os.path.join(self.src, "app.qml"), "w", encoding="utf-8") as fh:
            fh.write("// app\n")
        with open(os.path.join(self.src, "settings.json"), "w", encoding="utf-8") as fh:
            fh.write('{"from-source": true}\n')
        self.home = os.path.join(tmp, "home")
        self.target = os.path.join(self.home, ".config", "kisaru")

    def copy_install(self, marker):
        os.makedirs(self.target)
        if marker:
            with open(os.path.join(self.target, marker), "w", encoding="utf-8") as fh:
                fh.write("an earlier install\n")
        with open(os.path.join(self.target, "settings.json"), "w", encoding="utf-8") as fh:
            fh.write('{"mine": true}\n')
        with open(os.path.join(self.target, "stale.qml"), "w", encoding="utf-8") as fh:
            fh.write("// stale\n")

    def update(self):
        script = (
            "set -euo pipefail\n"
            f"SRC_DIR={shlex.quote(self.src)}\n"
            "MODE=copy\n"
            f"source {shlex.quote(os.path.join(ROOT, 'scripts', 'install-common.sh'))}\n"
            "install_config kisaru\n"
        )
        env = dict(
            os.environ,
            HOME=self.home,
            XDG_CONFIG_HOME=os.path.join(self.home, ".config"),
        )
        return subprocess.run(
            ["bash", "-c", script], env=env, capture_output=True, text=True
        )

    def test_an_install_with_the_old_marker_is_still_updated(self):
        self.copy_install(".package-export")
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(os.path.exists(os.path.join(self.target, ".kisaru-package")))
        self.assertFalse(os.path.exists(os.path.join(self.target, ".package-export")))
        with open(os.path.join(self.target, "settings.json"), encoding="utf-8") as fh:
            self.assertIn('"mine": true', fh.read())
        self.assertFalse(os.path.exists(os.path.join(self.target, "stale.qml")))

    def test_a_copy_that_already_has_the_new_marker_is_recognised(self):
        self.copy_install(".kisaru-package")
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(os.path.exists(os.path.join(self.target, "app.qml")))

    def test_a_folder_that_is_not_ours_is_left_alone(self):
        self.copy_install(None)
        result = self.update()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ya existe y no es kisaru", result.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.target, "app.qml")))
        self.assertTrue(os.path.exists(os.path.join(self.target, "stale.qml")))

    def test_the_repo_ships_its_own_marker(self):
        self.assertTrue(os.path.exists(os.path.join(ROOT, ".kisaru-package")))
        self.assertFalse(os.path.exists(os.path.join(ROOT, ".package-export")))
        marker = read(".kisaru-package")
        self.assertIn("kisaru", marker)
        self.assertNotIn("quickshell/packaging", marker)


if __name__ == "__main__":
    unittest.main()
