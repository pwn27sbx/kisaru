#!/usr/bin/env python3
"""Move this app's local data from the inherited names to `kisaru`.

The owner decisions D3, D6 and D4 recorded for the rename.

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

# Exit statuses: 0 nothing to do or done, 2 conflicts found and nothing written.
OK = 0
BLOCKED = 2


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
    legacy_data = os.path.join(home, ".local", "share")

    steps = [
        # The QML libraries (owner decision D6).
        Step("manga library",
             os.path.join(legacy_data, "quickshell", "manga_library.json"),
             os.path.join(new_data, "manga_library.json")),
        Step("anime library",
             os.path.join(legacy_data, "quickshell", "anime_library.json"),
             os.path.join(new_data, "anime_library.json")),
        Step("novel library",
             os.path.join(legacy_data, "quickshell", "new_novel_library.json"),
             os.path.join(new_data, "new_novel_library.json")),
        # The backends' own data, one folder each so the two `downloads/`
        # directories cannot collide.
        Step("manga data",
             os.path.join(legacy_data, "quickshell-manga"),
             os.path.join(new_data, "manga")),
        Step("novel data",
             os.path.join(legacy_data, "quickshell-novel"),
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


def _matches_marker(step, done):
    """True when the destination still holds exactly what the marker recorded."""
    recorded = done.get(step.dst) or []
    if isinstance(recorded, str):
        recorded = [{"rel": os.path.basename(step.dst), "sha256": recorded}]
    current = ({os.path.relpath(f, step.dst): _sha256(f) for f in _files_of(step.dst)}
               if os.path.isdir(step.dst)
               else {os.path.basename(step.dst): _sha256(step.dst)})
    return {e["rel"]: e["sha256"] for e in recorded} == current


def assess(steps, marker):
    """(to_copy, already, blocked): what the run would do, and why it cannot."""
    done = {}
    for entry in (marker or {}).get("entries", []):
        done.setdefault(entry["dst"], []).append(entry)
    to_copy, already, blocked = [], [], []
    for step in steps:
        if not step.exists:
            continue
        if step.secrets and _inside_git(os.path.dirname(step.dst)):
            blocked.append((step, "refusing to write secrets inside a git work tree"))
            continue
        if step.same() and not step.secrets:
            already.append(step)
            continue
        # A secrets file that is already in place still goes through the copy:
        # that is what normalises its mode to 600.
        if step.conflicts():
            if step.dst not in done:
                blocked.append((step, "destination has content and there is no marker for it"))
                continue
            # A marker is not permission to overwrite an edited copy: only the
            # content this tool recorded may be replaced.
            if not _matches_marker(step, done):
                blocked.append((step, "destination changed since the last run; not overwriting it"))
                continue
        to_copy.append(step)
    return to_copy, already, blocked


def copy_step(step):
    """Copy one step into place and return one provenance entry per file."""
    entries = []
    is_tree = os.path.isdir(step.src)
    base = step.src if is_tree else os.path.dirname(step.src)
    before = [(os.path.relpath(f, base), _sha256(f)) for f in _files_of(step.src)]

    os.makedirs(os.path.dirname(step.dst), exist_ok=True)
    # Copy next to the destination and swap it in, so an interrupted run never
    # leaves a half-written tree that a retry would see as a conflict.
    staging = step.dst + ".partial"
    if os.path.exists(staging):
        shutil.rmtree(staging, ignore_errors=True) if os.path.isdir(staging) else os.remove(staging)
    if is_tree:
        shutil.copytree(step.src, staging)
        os.replace(staging, step.dst)
    else:
        shutil.copy2(step.src, staging)
        os.replace(staging, step.dst)
    if step.secrets:
        os.chmod(step.dst, 0o600)

    for rel, digest in before:
        entries.append({"dst": step.dst, "rel": rel, "sha256": digest})
    return entries


def _write_marker(path, home, entries):
    record = {
        "tool": TOOL,
        "version": VERSION,
        "at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "home": home,
        "entries": entries,
    }
    tmp = path + ".partial"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(record, fh, indent=2, sort_keys=True)
        fh.write("\n")
    os.replace(tmp, path)


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
        return BLOCKED
    if not to_copy:
        print("\nnothing to do")
        return OK
    if not args.apply:
        print("\ndry run: pass --apply to copy (the inherited files are left in place)")
        return OK

    entries = list((marker or {}).get("entries", []))
    os.makedirs(os.path.dirname(mpath), exist_ok=True)
    for step in to_copy:
        entries.extend(copy_step(step))
        _write_marker(mpath, home, entries)
        print("  copied {}".format(step.label))

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
