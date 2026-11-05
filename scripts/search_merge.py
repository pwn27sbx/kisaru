"""Merge the answers of several sources into one ranked search page.

Every active source is asked for a search, so the same work is often listed by
more than one of them and the best match may come from the last source in the
chain. This module owns the two rules that make the merged page useful:

* **one entry per work** — titles are compared folded (case, accents and
  punctuation do not count), and the entry kept is the one from the earliest
  source in the chain;
* **deliberate variants stay apart** — the dedupe key is the WHOLE title, so
  "Solo Leveling" and "Solo Leveling sin Censura" are two different editions,
  not one entry.

Ranking is against what was typed, also folded: exact title first, then the
same work with harmless edition qualifiers, then a prefix, then the query
inside the title, then titles that carry every word, then whatever else the
sources returned. Nothing is dropped; the near matches simply sink.

Paging lives in `merge()` too: a page is the union of every source's window at
the same offset, so `window` is the largest window a source actually returned
(and `hasMore` is true when any source says there is more). `manga_chain.search`
turns that into `nextOffset`.
"""

import re
import unicodedata

import titles

# Score tiers, highest first. The numbers are only compared, never displayed.
EXACT = 1000        # the whole title, folded
SAME_WORK = 900     # the same work once edition qualifiers are dropped
PREFIX = 800        # the title starts with what was typed
CONTAINS = 700      # what was typed appears, word-aligned, inside the title
ALL_WORDS = 600     # every word typed appears somewhere in the title
PARTIAL_BASE = 500  # partial word overlap, scaled by coverage


def fold(text):
    """Lowercase, accent-free, punctuation-free form used for every comparison."""
    decomposed = unicodedata.normalize("NFKD", str(text or ""))
    plain = "".join(ch for ch in decomposed if not unicodedata.combining(ch))
    return re.sub(r"[^a-z0-9]+", " ", plain.lower()).strip()


def score(query, title):
    """How well `title` answers `query`, folded; higher is a better match."""
    wanted = fold(query)
    candidate = fold(title)
    if not wanted or not candidate:
        return 0
    if wanted == candidate:
        return EXACT
    # titles.titles_match already drops harmless edition qualifiers; feed it the
    # folded forms so accent and case never decide a match.
    if titles.titles_match(wanted, candidate):
        return SAME_WORK
    if candidate.startswith(wanted + " "):
        return PREFIX
    if (" " + wanted + " ") in (" " + candidate + " "):
        return CONTAINS
    wanted_words = wanted.split()
    candidate_words = set(candidate.split())
    shared = sum(1 for word in wanted_words if word in candidate_words)
    if shared == len(wanted_words):
        return ALL_WORDS
    return max(1, round(PARTIAL_BASE * shared / len(wanted_words)))


def merge(answers, query):
    """Dedupe and rank the answers of every source.

    `answers` is an ordered list of `(source_name, page)` pairs, in chain order,
    where `page` is a source's search answer (or None when it answered nothing).
    Returns `{"items": [(source_name, item)], "hasMore": bool, "window": int}`.

    The order of `answers` is the tie-breaker: two equally ranked titles keep the
    source order, and a duplicate keeps the entry from the earlier source.
    """
    chain_position = {}
    for index, (source, _page) in enumerate(answers):
        chain_position.setdefault(source, index)

    seen = set()
    rows = []
    window = 0
    has_more = False

    for source, page in answers:
        if not page:
            continue
        results = page.get("results") or []
        window = max(window, len(results))
        has_more = has_more or bool(page.get("hasMore"))
        for index, item in enumerate(results):
            title = item.get("title", "")
            key = fold(title)
            if key:
                if key in seen:
                    continue
                seen.add(key)
            rows.append((source, item, index))

    rows.sort(key=lambda row: (
        -score(query, row[1].get("title", "")),
        chain_position[row[0]],
        row[2],
    ))
    return {
        "items": [(source, item) for source, item, _index in rows],
        "hasMore": has_more,
        "window": window,
    }
