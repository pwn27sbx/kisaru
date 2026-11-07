"""The documented dev setup must be reproducible.

The README told a contributor to run the Python suite with the system
interpreter and there was no requirements file, so the run silently skipped
the backend tests. The installer ran `pip install --upgrade` with unpinned
names (audit 2026-11-06, findings 9, 10 and 37).

Run from the repo root:
    python3 -m unittest tests.test_requirements
"""

import os
import re
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def read(relative):
    with open(os.path.join(ROOT, relative), encoding="utf-8") as fh:
        return fh.read()


def requirement_blocks(text):
    """One logical requirement per yield, with its backslash continuations."""
    block = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        block.append(stripped)
        if not stripped.endswith("\\"):
            joined = " ".join(part.rstrip("\\").strip() for part in block)
            block = []
            if joined and not joined.startswith("-r "):
                yield joined


class RequirementsTest(unittest.TestCase):
    def test_a_runtime_lock_exists_and_is_pinned_with_hashes(self):
        text = read("requirements.txt")
        lines = list(requirement_blocks(text))
        self.assertTrue(lines, "requirements.txt has no requirements")
        for line in lines:
            self.assertIn("==", line, line)
            self.assertIn("--hash=sha256:", line, line)

    def test_the_runtime_lock_names_the_three_backend_packages(self):
        text = read("requirements.txt")
        for package in ("flask", "requests", "curl-cffi"):
            self.assertRegex(text, r"(?mi)^%s==" % re.escape(package))

    def test_the_dev_requirements_build_on_the_lock(self):
        text = read("requirements-dev.txt")
        self.assertIn("-r requirements.txt", text)
        self.assertRegex(text, r"(?m)^pip-tools==")

    def test_the_installer_installs_the_lock_with_hash_checking(self):
        text = read("install.sh")
        self.assertIn("requirements.txt", text)
        self.assertIn("--require-hashes", text)
        self.assertNotIn("--upgrade", text)

    def test_the_readme_documents_the_venv(self):
        text = read("README.md")
        self.assertIn("requirements-dev.txt", text)
        self.assertIn("python3 -m venv", text)

    def test_dependabot_watches_the_pip_lock(self):
        text = read(".github/dependabot.yml")
        self.assertIn("pip", text)
        self.assertIn("requirements.txt", text)


if __name__ == "__main__":
    unittest.main()
