#!/usr/bin/env python3
"""Move this app's local data from the inherited names to `kisaru`.

Owner decisions D3, D6 and D4 of the migration plan
(`2026-11-01-kisaru-rename-migration-plan.md`).

What it does, and what it deliberately does not:

* **Copies, never moves**: the inherited files stay in place, so the rollback is
  "delete the new ones" and this tool can be re-run safely.
* **Dry-run by default**: without `--apply` it prints exactly what it would copy
  and writes nothing.
* **Idempotent**: a marker records what was copied (with a sha256 per file); a
  second run with the same content does nothing.
* **Refuses to guess**: if the destination already holds different content and
  there is no marker, it stops instead of overwriting the user's data.
* **Refuses to hide secrets**: it never writes a secrets file inside a git work
  tree (`~/.config/kisaru` is a symlink to the public checkout).

Usage:
    tools/migrate_to_kisaru.py                  # show the plan
    tools/migrate_to_kisaru.py --apply          # copy
    tools/migrate_to_kisaru.py --apply --home /tmp/fake   # for tests
"""

import argparse
import datetime
import hashlib
import json
import os
import shutil
import sys

TOOL = "migrate_to_kisaru"
VERSION = 1
MARKER_NAME = ".migrated-from-qs-novelmangareader.json"


def _sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _files_of(path):
    if os.path.isfile(path):
        return [path]
    found = []
    for root, _dirs, names in os.walk(path):
        for name in sorted(names):
            found.append(os.path.join(root, name))
    return found


def _tree_hashes(path):
    return {os.path.relpath(f, path): _sha256(f) for f in _files_of(path)}


def _inside_git(path):
    probe = os.path.abspath(path)
    while True:
        if os.path.exists(os.path.join(probe, ".git")):
            return True
        parent = os.path.dirname(probe)
        if parent == probe:
            return False
        probe = parent


class Step:
    def __init__(self, label, src, dst, secrets=False):
        self.label = label
        self.src = src
        self.dst = dst
        self.secrets = secrets

    @property
    def exists(self):
        return os.path.exists(self.src)

    def same(self):
        """True when the destination already holds exactly this content."""
        if not os.path.exists(self.dst):
            return False
        if os.path.isfile(self.src):
            if not os.path.isfile(self.dst):
                return False
            return _sha256(self.src) == _sha256(self.dst)
        if not os.path.isdir(self.dst):
            return False
        return _tree_hashes(self.src) == _tree_hashes(self.dst)

    def conflicts(self):
        """The destination holds something else, so copying would overwrite it."""
        return os.path.exists(self.dst) and not self.same()

    def describe(self):
        return "{}: {} -> {}".format(self.label, self.src, self.dst)


def build_steps(home, xdg_data=None, xdg_cache=None, xdg_config=None):
    data = xdg_data or os.path.join(home, ".local", "share")
    cache = xdg_cache or os.path.join(home, ".cache")
    config = xdg_config or os.path.join(home, ".config")

    new_data = os.path.join(data, "kisaru")
    new_cache = os.path.join(cache, "kisaru")
    old_data = os.path.join(home, ".local", "share")

    steps = [
        # The QML libraries (owner decision D6).
        Step("manga library",
             os.path.join(old_data, "quickshell", "manga_library.json"),
             os.path.join(new_data, "manga_library.json")),
        Step("anime library",
             os.path.join(old_data, "quickshell", "anime_library.json"),
             os.path.join(new_data, "anime_library.json")),
        Step("novel library",
             os.path.join(old_data, "quickshell", "new_novel_library.json"),
             os.path.join(new_data, "new_novel_library.json")),
        # The backends' own data, one folder each so the two `downloads/`
        # directories cannot collide.
        Step("manga data",
             os.path.join(old_data, "quickshell-manga"),
             os.path.join(new_data, "manga")),
        Step("novel data",
             os.path.join(old_data, "quickshell-novel"),
             os.path.join(new_data, "novel")),
        # Caches: covers and chapter lists.
        Step("cover cache",
             os.path.join(cache, "qs-novelmangareader", "covers"),
             os.path.join(new_cache, "covers")),
        Step("chapter cache",
             os.path.join(cache, "quickshell-novel", "chapters"),
             os.path.join(new_cache, "chapters")),
        # The canary's secrets, outside any checkout (owner decision D3).
        Step("canary secrets",
             os.path.join(config, "qs-nmr", "canary.env"),
             os.path.join(config, "kisaru-canary", "canary.env"),
             secrets=True),
    ]
    return steps


def marker_path(home, xdg_data=None):
    data = xdg_data or os.path.join(home, ".local", "share")
    return os.path.join(data, "kisaru", MARKER_NAME)


def load_marker(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def assess(steps, marker):
    """(to_copy, already, blocked): what the run would do, and why it cannot."""
    done = {entry["dst"]: entry["sha256"] for entry in (marker or {}).get("entries", [])}
    to_copy, already, blocked = [], [], []
    for step in steps:
        if not step.exists:
            continue
        if step.secrets and _inside_git(os.path.dirname(step.dst)):
            blocked.append((step, "refusing to write secrets inside a git work tree"))
            continue
        if step.same():
            already.append(step)
            continue
        if step.conflicts() and step.dst not in done:
            blocked.append((step, "destination has content and there is no marker for it"))
            continue
        to_copy.append(step)
    return to_copy, already, blocked


def copy_step(step):
    entries = []
    before = {os.path.abspath(step.src): _sha256(f) for f in _files_of(step.src)}
    os.makedirs(os.path.dirname(step.dst), exist_ok=True)
    if os.path.isdir(step.src):
        shutil.copytree(step.src, step.dst, dirs_exist_ok=True)
    else:
        shutil.copy2(step.src, step.dst)
        if step.secrets:
            os.chmod(step.dst, 0o600)
    for src, digest in before.items():
        rel = os.path.relpath(src, step.src if os.path.isdir(step.src) else os.path.dirname(step.src))
        entries.append({"dst": step.dst, "rel": rel, "sha256": digest})
    return entries


def run(args):
    home = os.path.abspath(args.home or os.path.expanduser("~"))
    env = os.environ
    xdg_data = args.data or env.get("XDG_DATA_HOME")
    xdg_cache = args.cache or env.get("XDG_CACHE_HOME")
    xdg_config = args.config or env.get("XDG_CONFIG_HOME")

    steps = build_steps(home, xdg_data, xdg_cache, xdg_config)
    mpath = marker_path(home, xdg_data)
    marker = load_marker(mpath)
    to_copy, already, blocked = assess(steps, marker)

    print("kisaru migration ({} v{})".format(TOOL, VERSION))
    print("home: {}".format(home))
    for step in already:
        print("  = {} (already there)".format(step.describe()))
    for step in to_copy:
        print("  + {}".format(step.describe()))
    for step, why in blocked:
        print("  ! {}: {}".format(step.describe(), why))

    if blocked:
        print("\nnothing written: resolve the conflicts above and run again")
        return 2
    if not to_copy:
        print("\nnothing to do")
        return 0
    if not args.apply:
        print("\ndry run: pass --apply to copy (the inherited files are left in place)")
        return 0

    entries = []
    for step in to_copy:
        entries.extend(copy_step(step))
        print("  copied {}".format(step.label))

    record = {
        "tool": TOOL,
        "version": VERSION,
        "at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "home": home,
        "entries": entries,
    }
    os.makedirs(os.path.dirname(mpath), exist_ok=True)
    with open(mpath, "w", encoding="utf-8") as fh:
        json.dump(record, fh, indent=2, sort_keys=True)
        fh.write("\n")
    print("\ncopied {} file(s); marker: {}".format(len(entries), mpath))
    print("the inherited files are untouched: remove them only after the checklist")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apply", action="store_true", help="copy instead of printing the plan")
    parser.add_argument("--home", help="home directory to operate on (tests)")
    parser.add_argument("--data", help="XDG_DATA_HOME override")
    parser.add_argument("--cache", help="XDG_CACHE_HOME override")
    parser.add_argument("--config", help="XDG_CONFIG_HOME override")
    return run(parser.parse_args(argv))


if __name__ == "__main__":
    sys.exit(main())
