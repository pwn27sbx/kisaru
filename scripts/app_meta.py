"""The app's own identity and the path rule it shares with the QML.

Owner decision D8: the product is the one making the outbound request, so the
user agent names `kisaru` and points at this project's repository, with the
version read from the bar widget's manifest instead of a hard-coded string.

Owner decision D6: config and data moved to `kisaru`; the inherited names are
read only while they are the only ones that exist, and a fresh install writes
to the new name. `app_paths.js` holds the same rule for the QML side; the two
must agree, which is what tests/test_app_paths_python.py pins.
"""

import json
import os

REPO_URL = "https://github.com/pwn27sbx/kisaru"

CONFIG_DIR = "kisaru"
LEGACY_CONFIG_DIR = "qs-novelmangareader"

DATA_DIR = "kisaru"
LEGACY_DATA_DIR = "qs-novelmangareader"

CACHE_DIR = "kisaru"
LEGACY_CACHE_DIR = "qs-novelmangareader"

# The inherited locations were written with a literal `~/.local/share` (not
# XDG_DATA_HOME), so the fallback must look there even when the variable is set.
LEGACY_LIBRARY_DIR = "quickshell"
LEGACY_NOVEL_DIR = "quickshell-novel"
LEGACY_DATA_HOME = os.path.join(os.path.expanduser("~"), ".local", "share")
LEGACY_CACHE_HOME = os.path.join(os.path.expanduser("~"), ".cache")

_MANIFEST = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "omarchy", "pwnsxb.kisaru", "manifest.json"
)

_version = None


def version():
    """The widget manifest's version, or "0" when it cannot be read."""
    global _version
    if _version is None:
        try:
            with open(_MANIFEST, encoding="utf-8") as fh:
                _version = str(json.load(fh)["version"])
        except (OSError, ValueError, KeyError, TypeError):
            _version = "0"
    return _version


def user_agent():
    return "kisaru/{} (+{})".format(version(), REPO_URL)


def resolve_dir(new_path, old_path):
    """The new directory when it exists, the inherited one while it is the only
    one, and the new one when neither does (a fresh install)."""
    if os.path.isdir(new_path):
        return new_path
    if os.path.isdir(old_path):
        return old_path
    return new_path


def resolve_by_content(new_base, old_base, markers):
    """Base directory by what it CONTAINS, not by the directory itself existing.

    The new data root also holds the venv, so "the folder is there" says nothing
    about the user's data being there; a marker file or folder decides.
    """
    for marker in markers:
        if os.path.exists(os.path.join(new_base, marker)):
            return new_base
        if os.path.exists(os.path.join(old_base, marker)):
            return old_base
    return new_base


def resolve_file(new_path, old_path):
    """The new file when it exists, the inherited one while it is the only one."""
    if os.path.isfile(new_path):
        return new_path
    if os.path.isfile(old_path):
        return old_path
    return new_path


def canary_env_path(env=None):
    """The canary's secrets file: ~/.config/kisaru-canary/canary.env.

    It sits outside the repository on purpose: `~/.config/kisaru` is a symlink to
    the checkout, and a secrets file there would sit inside a public git tree.
    """
    base = config_home(env)
    return resolve_file(
        os.path.join(base, "kisaru-canary", "canary.env"),
        os.path.join(base, "qs-nmr", "canary.env"),
    )


def cache_home(env=None):
    env = os.environ if env is None else env
    return env.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")


def data_home(env=None):
    env = os.environ if env is None else env
    return env.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local", "share")


def config_home(env=None):
    env = os.environ if env is None else env
    return env.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
