#!/usr/bin/env python3
"""Kisaru private-mode helper. Standard library only.

    kisaru privado                 set or replace the secret word (no argument)
    privado.py --check <path>      read the candidate from stdin, print nothing

`--check` exits 0 on a match, 1 on no match and 2 on any error. The word never
enters argv, so it cannot reach a shell history or the process list; the app
writes it on stdin and closes the pipe.

The record lives in $XDG_DATA_HOME/kisaru/privacy.json (or
$HOME/.local/share/kisaru/privacy.json), mode 0600:

    {"v":1,"salt":"<32 hex>","tag":"<1 hex>","n":131072,"r":8,"p":1,"dk":"<64 hex>"}

word = fold(word) + trim, UTF-8. dk = scrypt(word, salt, n, r, p, dklen=32) and
tag is the first hex digit of MD5(salt + word), the cheap filter the app uses to
decide whether a keystroke is worth a helper run.
"""

import getpass
import hashlib
import hmac
import json
import os
import secrets
import sys
import tempfile
import unicodedata

VERSION = 1
MIN_WORD_LENGTH = 8
N = 131072
R = 8
P = 1
MAX_INPUT = 1024


def fold(text):
    """Lowercase, NFD, strip U+0300-036F, trim. Same rule as services/privacy.js."""
    folded = unicodedata.normalize("NFD", str(text).lower())
    folded = "".join(ch for ch in folded if not ("\u0300" <= ch <= "\u036f"))
    return folded.strip()


def data_dir():
    xdg = os.environ.get("XDG_DATA_HOME") or ""
    if xdg:
        return os.path.join(xdg, "kisaru")
    home = os.environ.get("HOME") or os.path.expanduser("~")
    return os.path.join(home, ".local", "share", "kisaru")


def privacy_path():
    return os.path.join(data_dir(), "privacy.json")


def derive(word, salt_hex):
    return hashlib.scrypt(
        word.encode("utf-8"),
        salt=bytes.fromhex(salt_hex),
        n=N,
        r=R,
        p=P,
        maxmem=2**28,
        dklen=32,
    )


def build_record(word):
    salt = secrets.token_hex(16)
    tag = hashlib.md5((salt + word).encode("utf-8")).hexdigest()[0]
    return {
        "v": VERSION,
        "salt": salt,
        "tag": tag,
        "n": N,
        "r": R,
        "p": P,
        "dk": derive(word, salt).hex(),
    }


def read_record(path):
    """Return the record, or None when it is missing or malformed."""
    try:
        with open(path, "rb") as handle:
            raw = handle.read(8192)
        data = json.loads(raw.decode("utf-8"))
    except Exception:
        return None
    if not isinstance(data, dict):
        return None
    if data.get("v") != VERSION:
        return None
    salt = data.get("salt")
    tag = data.get("tag")
    dk = data.get("dk")
    if not isinstance(salt, str) or len(salt) != 32:
        return None
    if not isinstance(tag, str) or len(tag) != 1:
        return None
    if not isinstance(dk, str) or len(dk) != 64:
        return None
    if data.get("n") != N or data.get("r") != R or data.get("p") != P:
        return None
    try:
        bytes.fromhex(salt)
        bytes.fromhex(dk)
    except ValueError:
        return None
    if any(ch not in "0123456789abcdef" for ch in salt + tag + dk):
        return None
    return data


def write_record(path, record):
    directory = os.path.dirname(path)
    os.makedirs(directory, mode=0o700, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=directory, prefix=".privacy-", suffix=".tmp")
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(record, handle)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def setup():
    path = privacy_path()
    if os.path.exists(path):
        answer = input("Ya hay una palabra secreta. ¿Reemplazarla? [s/N] ").strip().lower()
        if answer not in ("s", "si", "sí", "y", "yes"):
            return 1
    choice = getpass.getpass("Palabra secreta (mínimo 8 caracteres): ")
    again = getpass.getpass("Repite la palabra: ")
    if choice != again:
        print("Las palabras no coinciden.", file=sys.stderr)
        return 2
    word = fold(choice)
    if len(word) < MIN_WORD_LENGTH:
        print("La palabra debe tener al menos 8 caracteres.", file=sys.stderr)
        return 2
    write_record(path, build_record(word))
    return 0


def check(path):
    try:
        raw = sys.stdin.buffer.read(MAX_INPUT)
        word = fold(raw.decode("utf-8", "replace"))
        record = read_record(path)
        if record is None:
            return 2
        got = derive(word, record["salt"])
        return 0 if hmac.compare_digest(got, bytes.fromhex(record["dk"])) else 1
    except Exception:
        return 2


def main(argv):
    if len(argv) == 1:
        return setup()
    if len(argv) == 3 and argv[1] == "--check":
        return check(argv[2])
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
