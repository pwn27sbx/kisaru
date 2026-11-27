"""Group duplicate chapter uploads (backend side).

A source can list the same chapter twice — "1" and "1.1", the second a later
re-upload — and a favourite's "new chapters" badge counted raw rows, so one
re-upload announced dozens of new chapters. This module is the Python side of
the rule the panel uses (services/chapters.js): the same corpus
tests/fixtures/chapter_versions.json pins both, so they cannot drift apart.

A ".1" only merges inside a generation: several such rows sharing a later
upload window, at least three of them, covering a quarter of the integer
chapters, with ids from another block, and no ".2" sibling on the same base
(split numbering). Everything else stays exactly as the source listed it.
"""

import re
from datetime import date, datetime, timedelta, timezone

REUPLOAD_FRACTION = "1"
SPLIT_FRACTION = "2"
GENERATION_WINDOW = timedelta(days=7)
MIN_GENERATION = 3
MIN_COVERAGE = 0.25

_DMY = re.compile(r"^(\d{1,2})/(\d{1,2})/(\d{4})$")
_ISO = re.compile(r"^(\d{4})-(\d{2})-(\d{2})")
_ID = re.compile(r"^(.*?)(\d+)$")


def _text(value):
    return "" if value is None else str(value).strip()


def _fraction(key):
    dot = key.rfind(".")
    return "" if dot < 0 else key[dot + 1:]


def _base(key):
    dot = key.rfind(".")
    return key if dot < 0 else key[:dot]


def _is_integer(key):
    return key != "" and key.isdigit()


def parse_date(value):
    """A chapter date, or None. The site answers day-first ("21/04/2026")."""
    text = _text(value)
    if text == "":
        return None
    match = _DMY.match(text)
    if match:
        try:
            return datetime(int(match.group(3)), int(match.group(2)), int(match.group(1)))
        except ValueError:
            return None
    match = _ISO.match(text)
    if not match:
        return None
    try:
        moment = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        try:
            return datetime(int(match.group(1)), int(match.group(2)), int(match.group(3)))
        except ValueError:
            return None
    if moment.tzinfo is not None:
        moment = moment.astimezone(timezone.utc).replace(tzinfo=None)
    return moment


def _id_block(value):
    """(prefix, trailing number) of an upload id, or None when it has none."""
    match = _ID.match(_text(value))
    return (match.group(1), int(match.group(2))) if match else None


def _rows_by_key(chapters):
    by_key = {}
    order = []
    for entry in chapters or []:
        if not entry:
            continue
        key = _text(entry.get("chapter"))
        if key not in by_key:
            by_key[key] = []
            order.append(key)
        by_key[key].append(entry)
    return by_key, order


def _families(by_key, order):
    """Candidate key -> base key for every generation the list proves."""
    bases = [key for key in order if _is_integer(key)]
    if not bases:
        return {}

    base_dates = {}
    base_blocks = []
    for base in bases:
        entries = by_key[base]
        moment = parse_date(entries[0].get("publishAt"))
        if moment is not None:
            base_dates[base] = moment
        block = _id_block(entries[0].get("id"))
        if block:
            base_blocks.append(block)

    facts = []
    for key in order:
        if _fraction(key) != REUPLOAD_FRACTION:
            continue
        base = _base(key)
        if len(by_key.get(base, [])) != 1:
            continue
        if any(other != key and _base(other) == base and _fraction(other) == SPLIT_FRACTION
               for other in order):
            continue
        if base not in base_dates:
            continue
        entry = by_key[key][0]
        moment = parse_date(entry.get("publishAt"))
        if moment is None or moment <= base_dates[base]:
            continue
        facts.append({"key": key, "base": base, "date": moment, "id": entry.get("id")})

    if len(facts) < MIN_GENERATION:
        return {}

    facts.sort(key=lambda fact: fact["date"])
    families = {}

    def close(cluster):
        if len(cluster) < MIN_GENERATION:
            return
        if len(cluster) / len(bases) < MIN_COVERAGE:
            return
        blocks = [_id_block(fact["id"]) for fact in cluster]
        if (all(blocks) and base_blocks
                and all(block[0] == blocks[0][0] for block in base_blocks + blocks)):
            candidates = [block[1] for block in blocks]
            originals = [block[1] for block in base_blocks]
            if min(candidates) <= max(originals) and max(candidates) >= min(originals):
                return                      # interleaved: not a later block
        for fact in cluster:
            families[fact["key"]] = fact["base"]

    cluster = [facts[0]]
    for fact in facts[1:]:
        if fact["date"] - cluster[-1]["date"] <= GENERATION_WINDOW:
            cluster.append(fact)
        else:
            close(cluster)
            cluster = [fact]
    close(cluster)
    return families


def grouped_numbers(chapters):
    """One entry per chapter, in source order (re-uploads folded onto their base)."""
    by_key, order = _rows_by_key(chapters)
    families = _families(by_key, order)
    return [key for key in order if key not in families]


def grouped_count(chapters):
    """How many chapters the list really has, re-uploads counted once."""
    return len(grouped_numbers(chapters))
