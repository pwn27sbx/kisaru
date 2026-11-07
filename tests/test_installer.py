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
import stat
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


if __name__ == "__main__":
    unittest.main()
