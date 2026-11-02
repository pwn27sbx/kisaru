"""The three backends must start from their real entry point.

The novel panel went down with "Request failed: HTTP 0 / Offline" because
scripts/novel_server/main.py imported a provider that could not find app_meta:
the sys.path it computed pointed at the repository root, one level too high.
Nothing in the suite noticed, because every test imports the modules after
putting scripts/ on the path itself, so the missing entry point was never the
thing under test.

These tests start each backend the way Quickshell does — a subprocess with the
app's interpreter and the script path — and require it to answer /health on a
port. `kisaru` is usually running and owns 5150/5151/5050, so each backend is
started with --port on a free port; the canonical default is pinned separately
through --help.
"""

import os
import socket
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
VENV_PYTHON = os.path.expanduser("~/.local/share/kisaru/venv/bin/python3")

BACKENDS = (
    ("anime", os.path.join("scripts", "anime_server.py"), 5050),
    ("manga", os.path.join("scripts", "manga_server.py"), 5150),
    ("novel", os.path.join("scripts", "novel_server", "main.py"), 5151),
)

START_TIMEOUT = 30


def interpreter():
    """The interpreter the app uses, or the one running the suite."""
    if os.access(VENV_PYTHON, os.X_OK):
        return VENV_PYTHON
    return sys.executable


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def health(port, timeout=1.0):
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/health",
                                    timeout=timeout) as response:
            return response.status, response.read()
    except (urllib.error.URLError, OSError):
        return None, b""


class BackendEntryPointTest(unittest.TestCase):
    def test_each_entry_point_imports_and_binds_a_port(self):
        for name, script, canonical in BACKENDS:
            with self.subTest(backend=name):
                port = free_port()
                log = tempfile.TemporaryFile()
                process = subprocess.Popen(
                    [interpreter(), script, "--port", str(port)],
                    cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                )
                try:
                    status, body = self._wait_health(port, process)
                    if status is None:
                        process.poll()
                        log.seek(0)
                        output = log.read().decode("utf-8", "replace")[-2000:]
                        self.fail("%s did not answer /health on %s (exit %s):\n%s"
                                  % (name, port, process.returncode, output))
                    self.assertEqual(status, 200, body[:200])
                finally:
                    process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=10)
                    log.close()

    def _wait_health(self, port, process):
        deadline = time.monotonic() + START_TIMEOUT
        while time.monotonic() < deadline:
            if process.poll() is not None:
                return None, b""
            status, body = health(port)
            if status is not None:
                return status, body
            time.sleep(0.25)
        return None, b""

    def test_each_entry_point_still_defaults_to_its_canonical_port(self):
        """--port exists so this guard can run while kisaru holds the real one."""
        for name, script, canonical in BACKENDS:
            with self.subTest(backend=name):
                result = subprocess.run(
                    [interpreter(), script, "--help"],
                    cwd=ROOT, capture_output=True, text=True, timeout=60,
                )
                self.assertEqual(result.returncode, 0, result.stderr[-800:])
                self.assertIn("default: %d" % canonical,
                              result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
