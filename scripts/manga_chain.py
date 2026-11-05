"""Manga source chain (Spanish): MangaDex -> InManga -> zonatmo -> zonatmo_org -> manhwaweb.

Every endpoint returns the same JSON contract as manga_server.py, with item ids
prefixed by the source (``mangadex:<id>`` / ``inmanga:<id>`` / ``zonatmo:<id>`` /
``zonatmo_org:<id>``) so info()/pages() can route back to the source that
produced them.

Language fall-through: MangaDex (es-la / es) is tried first; when it has no
chapters in the preferred language, InManga (Spanish-only) is tried by title,
then the two zonatmo backends (zonatmo.net JSON API, then zonatmo.org HTML).
When none has Spanish, info() returns {"error": "Sin capitulos en espanol"}
(decision (b): never fall back to English content).

Failover / mirrors: zonatmo.net and zonatmo.org are two INDEPENDENT backends for
the same Spanish catalogue (different protocols), so they are not identical
mirrors. Failover happens through the chain order — a source that raises (dead
domain, timeout) is skipped and the next is tried — and each provider
short-caches a dead domain so a burst does not hammer it. ``SOURCE_MIRRORS``
records the alternate domain per backend.

Source selection: QS_MANGA_SOURCE = mangadex | inmanga | zonatmo | zonatmo_org |
manhwaweb | weebcentral | auto. auto uses the content language (QS_CONTENT_LANG): Spanish ->
the chain, otherwise WeebCentral (handled by manga_server.py).
"""

import os
import re
import threading
import time

import error_report

import content_lang
import inmanga_source
import manga_sources
import search_merge
import titles
import manhwaweb_source
import zonatmo_org_source
import zonatmo_source

NO_SPANISH_MESSAGE = "Sin capítulos en español"

# How long a search waits for ONE source, in seconds. The sources run in
# parallel, so this is the whole search's ceiling when a source hangs: a dead
# domain or a slow mirror is skipped instead of holding the page. Overridable
# because a slow network may need more than the default (6 s).
SEARCH_SOURCE_TIMEOUT = 6.0


def _search_timeout():
    raw = os.environ.get("QS_MANGA_SEARCH_TIMEOUT", "").strip()
    if raw:
        try:
            return float(raw)
        except ValueError:
            pass
    return SEARCH_SOURCE_TIMEOUT


_MODULES = {
    "mangadex": manga_sources,
    "inmanga": inmanga_source,
    "zonatmo": zonatmo_source,
    "zonatmo_org": zonatmo_org_source,
    "manhwaweb": manhwaweb_source,
}
_FORCED = ("mangadex", "inmanga", "zonatmo", "zonatmo_org", "manhwaweb", "weebcentral", "mangaplus")

# Alternate domain per zonatmo backend (for diagnostics / health reporting).
SOURCE_MIRRORS = {
    "zonatmo": ("zonatmo.net",),
    "zonatmo_org": ("zonatmo.org",),
}


def mirrors_for(source):
    """Alternate domains recorded for `source` (empty when it has none)."""
    return SOURCE_MIRRORS.get(source, ())


def spanish_sources(env=None, langs=None):
    """The Spanish sources the chain tries, in order.

    WeebCentral is the English fallback (plan decision (b)), not a Spanish
    source, so it is excluded — the UI notice names only the ES sources that
    were actually consulted (plan §F3).
    """
    return [name for name in active_chain(env, langs) if name != "weebcentral"]


def active_chain(env=None, langs=None):
    """Ordered list of source names to try for the current configuration."""
    forced = (env if env is not None else os.environ.get("QS_MANGA_SOURCE", "")).strip().lower()
    if forced in _FORCED:
        return [forced]
    preferred = content_lang.content_langs() if langs is None else langs
    for tag in preferred:
        base = str(tag).strip().lower().split("-", 1)[0].split("_", 1)[0]
        if base == "es":
            return ["mangadex", "inmanga", "zonatmo", "zonatmo_org", "manhwaweb"]
    return ["weebcentral"]


def split_id(prefixed):
    """``"mangadex:abc"`` -> ``("mangadex", "abc")``."""
    name, _, raw = (prefixed or "").partition(":")
    return (name, raw) if raw else ("", prefixed or "")


def _prefix_item(name, item):
    return {**item, "id": f"{name}:{item.get('id', '')}"}


def _prefix_list(name, items):
    return [_prefix_item(name, item) for item in items]


def _prefix_info(name, data):
    return {
        **data,
        "id": f"{name}:{data.get('id', '')}",
        "chapters": [{**c, "id": f"{name}:{c.get('id', '')}"} for c in data.get("chapters", [])],
    }


def _report(error, source="", op=""):
    """Report a swallowed source error. Never raises: the reader comes first."""
    try:
        error_report.report(error, source=source, op=op)
    except Exception:  # noqa: BLE001
        pass


def _try(call, default=None, *, source="", op=""):
    """Run `call`, returning `default` when a source raises.

    A dead domain (DNS/timeout) or a flaky parser must never break the whole
    chain: the source is skipped and the next one is tried. The error is
    reported first, because swallowing it is what hid the 2026-10-27 break.
    """
    try:
        return call()
    except Exception as error:  # noqa: BLE001 — a dead/flaky source must not break the chain
        _report(error, source, op)
        return default


def _first_match(module, title, source=""):
    """Best matching series id in `module` for `title`, or "".

    Only a title that actually matches is accepted, so a fall-through never
    adopts an unrelated series.
    """
    try:
        result = module.search(title, None, 0, "Best Match")
    except Exception as error:  # noqa: BLE001 — a flaky source must not break the chain
        _report(error, source, "search")
        return ""
    for item in result.get("results") or []:
        if titles.titles_match(title, item.get("title", "")):
            return item.get("id", "")
    return ""


def title_hint(prefixed_id):
    """Human title guessed from an id, for when its source cannot answer.

    ``"zonatmo:tienda-del-placer"`` -> ``"Tienda Del Placer"``. A dead backend
    used to abort the whole fall-through because no title was known yet, so a
    live source later in the chain was never tried.
    """
    slug = str(prefixed_id or "").rstrip("/").rsplit("/", 1)[-1]
    slug = re.sub(r"^[a-z_]+:", "", slug)
    words = [w for w in re.split(r"[-_]+", slug) if w and not w.isdigit()]
    return " ".join(w[:1].upper() + w[1:] for w in words)


def _search_one(name, query, mtype, offset, sort, answers):
    """Ask one source and leave its page in `answers` (thread target)."""
    module = _MODULES.get(name)
    if module is None:
        return
    answers[name] = _try(lambda: module.search(query, mtype, offset, sort), None,
                         source=name, op="search")


def _search_answers(chain, query, mtype, offset, sort):
    """Every source's answer, in chain order, each bounded by the time limit.

    Sources run in parallel and are joined against ONE deadline, so a hanging
    source costs the search at most `timeout()` and never blocks the others.
    A source that raises is reported and skipped, exactly like the other
    endpoints in this chain.
    """
    answers = {}
    workers = []
    for name in chain:
        if _MODULES.get(name) is None:
            continue
        worker = threading.Thread(target=_search_one, name=f"search-{name}", daemon=True,
                                  args=(name, query, mtype, offset, sort, answers))
        worker.start()
        workers.append((name, worker))
    deadline = time.monotonic() + _search_timeout()
    for name, worker in workers:
        worker.join(max(0.0, deadline - time.monotonic()))
        if worker.is_alive():
            # The HTTP call may still finish later; its page is simply not used.
            _report(TimeoutError("search timed out"), name, "search")
    return [(name, answers[name]) for name, _worker in workers if name in answers]


def _search_first(query, mtype=None, offset=0, sort="Best Match"):
    """First source with results (the catalog path, unchanged).

    Browse asks for a listing through the search endpoint (`q=a`, sorted by
    popularity); merging every source there would turn the catalog into a
    ranked search, so that path keeps the old first-answer behaviour.
    """
    for name in active_chain():
        module = _MODULES.get(name)
        if module is None:
            continue
        result = _try(lambda: module.search(query, mtype, offset, sort), None,
                      source=name, op="search")
        if result and result.get("results"):
            return {**result, "results": _prefix_list(name, result["results"])}
    return {"results": [], "hasMore": False, "nextOffset": offset}


def search(query, mtype=None, offset=0, sort="Best Match", merge=False):
    """Search EVERY active source and return one merged, ranked page.

    The old chain stopped at the first source with results: MangaDex's near
    matches for a Spanish query hid the ManhwaWeb title that actually matched.
    Now every source answers (in parallel, each bounded by the time limit), the
    pages are deduplicated by folded title and ranked against the query, and the
    ids keep the prefix of the source that produced them.

    Only a real search merges: browse lists through `_search_first` (see it),
    so the catalog keeps its old shape.

    Paging: `offset` is the window start asked of EVERY source, so a page is the
    union of the sources' windows at that offset. `nextOffset` advances by the
    largest window a source returned, which is what keeps the sources from being
    asked for the same items twice; `hasMore` is true when any source has more.
    Deduplication is per page (the endpoint is stateless), so an item that moves
    between sources' windows can show up on a later page.
    """
    if not merge:
        return _search_first(query, mtype, offset, sort)
    offset = max(0, int(offset or 0))
    answers = _search_answers(active_chain(), query, mtype, offset, sort)
    merged = search_merge.merge(answers, query)
    results = [_prefix_item(source, item) for source, item in merged["items"]]
    window = merged["window"]
    return {
        "results": results,
        "hasMore": merged["hasMore"],
        "nextOffset": offset + window if window else offset,
    }


def latest(page=1):
    for name in active_chain():
        module = _MODULES.get(name)
        if module is None:
            continue
        result = _try(lambda: module.latest(page), None, source=name, op="latest")
        if result and result.get("results"):
            return {**result, "results": _prefix_list(name, result["results"])}
    return {"results": [], "hasMore": False, "nextPage": page + 1}


def hot():
    for name in active_chain():
        module = _MODULES.get(name)
        if module is None:
            continue
        items = _try(lambda: module.hot(), None, source=name, op="hot")
        if items:
            return _prefix_list(name, items)
    return []


def info(prefixed_id):
    """Detail for `prefixed_id`, from the first source that has Spanish chapters.

    The answer carries ``originId`` — the id the caller asked for — because the
    responding source may be a different one (zonatmo.net is down, zonatmo.org
    answers). The reader stores reading progress against the entry the user
    opened, not against whichever backend happened to reply; without this, a
    fallback silently stopped updating the library.
    """
    requested = prefixed_id
    name, raw = split_id(prefixed_id)
    if name not in _MODULES:
        # Legacy / unprefixed id: best effort with the first source in the chain.
        chain = active_chain()
        name, raw = (chain[0] if chain else ""), prefixed_id
    else:
        chain = active_chain()
    if name not in chain:
        chain = [name] + list(chain)
    start = chain.index(name)

    title = ""
    hint = title_hint(raw)
    for policy in chain[start:]:
        module = _MODULES.get(policy)
        if module is None:
            continue
        if policy == name:
            data = _try(lambda: module.info(raw), None, source=policy, op="info")
        else:
            # A source that raised left no title behind; the id slug is enough
            # to keep the fall-through alive (2026-10-27, zonatmo.net 404s).
            if not (title or hint):
                break
            match = _first_match(module, title or hint, policy)
            if not match:
                continue
            data = _try(lambda: module.info(match), None, source=policy, op="info")
        if not data:
            continue
        title = title or data.get("title", "")
        if data.get("chapters"):
            return {**_prefix_info(policy, data), "originId": requested}
    return {"error": NO_SPANISH_MESSAGE, "title": title or hint}


def pages(prefixed_chapter_id):
    name, raw = split_id(prefixed_chapter_id)
    module = _MODULES.get(name)
    if module is None:
        return []
    # pages() never used _try, so a reader failure was invisible; report it and
    # re-raise to keep the 500 the caller already handles.
    try:
        return module.pages(raw)
    except Exception as error:  # noqa: BLE001
        _report(error, name, "pages")
        raise
