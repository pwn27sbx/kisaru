"""mangafire.to source (multi-language catalogue) — same JSON contract as manga_server.py.

mangafire.to is a React SPA backed by a JSON API. The site itself is not
scrapable (the HTML is an empty shell), but the API is public once every
request carries a `vrf` signature derived from its own query string. Without
it the API answers:

    HTTP 403 {"message": "Missing token."}

The algorithm is ported from the Mihon extension maintained in
keiyoushi/extensions-source (src/all/mangafire/.../VrfSigner.kt): the canonical
string is the API path without the `/api` prefix plus the parameters sorted by
name, values decoded and `key[]` rewritten as `key[0]`, `key[1]`, …; it is then
signed with three chained byte-substitution stages and base64url-encoded
without padding. It has no time window, session or cookie: it is a pure
function of the string.

Endpoints (verified 2026-11):

    search    GET /api/titles?keyword=Q&languages[]=es-la&languages[]=es&page=N&limit=24
    listing   GET /api/titles?order[chapter_updated_at]=desc  (latest)
              GET /api/titles?order[views_7d]=desc            (hot)
    detail    GET /api/titles/<hid>                            -> data.{title,synopsisHtml,genres,…}
    chapters  GET /api/titles/<hid>/chapters?language=es-la&limit=200&order=desc&page=1&sort=number
    reader    GET /api/chapters/<id>                           -> data.pages[].url
    image     https://pwN.mfcdn2.xyz/…  (403 Cloudflare without Referer https://mangafire.to/)

Language: the site separates `es-la` (LatAm, usually complete) from `es` (a
handful of chapters), so a series is asked for `es-la` first and only falls back
to `es` when it has none. `QS_CONTENT_LANG` does not apply: this module is only
reachable from the Spanish chain.

Notes:
  * a series id is the five-character `hid` (`rl2vm`), not the slug;
  * a chapter id is the numeric API id, which is what /api/chapters/<id> wants;
  * the API marks a request burst with a transient 403 (`Missing token.`) that
    the same URL survives a second later, so _request retries a 403 and never
    treats it as a dead source;
  * chapter numbers are floats (271.5 exists), normalised like zonatmo.org.

The parsers are pure and fixture-tested; the tests never touch the network.
"""

import base64
import json
import re
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from html import unescape as _html_unescape

import app_meta

BASE = "https://mangafire.to"
PROXY_PORT = 5150  # same image proxy as manga_server.py
USER_AGENT = app_meta.user_agent()
PAGE_LIMIT = 24
CHAPTER_LIMIT = 200       # the API caps a chapter page at 200
CHAPTER_PAGES = 10        # hard stop so a broken `hasNext` cannot loop forever

# The API and the reader CDN both expect the site as referer (the CDN answers
# 403 Cloudflare without it); manga_server's image proxy sends the same value.
REFERER = "https://mangafire.to/"

ATTEMPTS = 3
INTERVAL = 0.4  # ~2.5 req/s; the API throttles bursts with a transient 403

# ── vrf signer (ported from the Mihon extension's VrfSigner.kt) ────────────
_TABLE_1 = (
    "yINlmUNho8VYJT+ibTIP+9ESiULpVEtMOoD6U6lRE0R/xwXo/Xp9NrUgC4cw/Lmo33vUyjUE4"
    "0kUoEWIr/fxfNNcq2s79ShQ5NhNrFnJ4hXPwOu/SuXzIbuTQKGFvfm08E9jvCfqAtoDqvQq3dVW"
    "PQFmJjgvkISBeXY3BgANR+yVnjGbcxZ47d6kLNfZPIayTq3/YGySb1KuVZodWp/WGNAO5pfMcpaK"
    "53Hhs0allBszaMaxuouOwdxbwgxIw6YunSsXjI05Yi0j9j4eHKfSXR8Ifo/Od+8iamRfCXTyvm7NGR"
    "GYdcQ0ywcK/u6RXhrbcCm4t2eCtrDgQVecJGkQ+A=="
)
_KEY_1 = "0Ec58JOY3uBzJK9m3zqIOpdlF7UFiax9DmA="
_TABLE_2 = (
    "IUFltCxD3Oc2cwCgkJffthaOg9cgPUb0LgW6H/VtfcF0kc5F25t+aWj6JH9VOhOaY0rAFdUxlDnl"
    "5BLNvwEJvQtP5qcw7vdb/K+chnbwnspSHT8mz5lqwz41TezG0hkO06FTjJZhsyNuFLDpD2ZZxQj/Q"
    "IRcF90zpmQ7Byu483WsQqUE0C342HL+JXngRB6fRzxRyVTaKu83h7UYTJ0QMt6ixFh6S3F8gqkKw"
    "rGTL3jHNBsD45UnifK8+RGtishQV2K3rujLKEkiZxpr2dYcudFW4oFsDKhad3CLBvuyTqsCo4B7mL"
    "5IKQ1vXo/MOOvq1I1d8ar9X6Ttu5KF4fZgiA=="
)
_KEY_2 = "AAdjb1iPY8CiDmq9H34tKTBF8a3oDQ=="
_TABLE_3 = (
    "NQHlu1/wVO5EmkwQymF810qqY2xG1k2obcas4Z9mCsPEIFl9pRIjFxbJ7ybMHbBckT5Ton85E0F"
    "OeHezbh/mjlEYpmpnlXOS8dgrqeq2KfxImTh1YK9y0PeMNhzA1OQzSY9brYOJq/l2QnE/hwOeZIh"
    "PixVSKIUlDb5vLcH6RWKxkIEMuP0bDwIqQ71AJJaEaMJL7A6YtyIwoRT+L5v4aZzodN/0+3nOGsf"
    "blFjgxSfPzVDjNFeNl5P26+kEC/8AHgdrpAbt3hHz3HrRN1Y6e+JHgF7ncFWnoF0y3THL1S71WgW"
    "GCa6KtSzTCCG58n68nTyj2T3Sshk7utqCtMi/ZQ=="
)
_KEY_3 = "DELOJgPsVaCcblDtTGMdHzM="

_STAGES = (
    (base64.b64decode(_TABLE_1), base64.b64decode(_KEY_1), 0x5A),
    (base64.b64decode(_TABLE_2), base64.b64decode(_KEY_2), 0x35),
    (base64.b64decode(_TABLE_3), base64.b64decode(_KEY_3), 0xBA),
)

_STATUS = {
    "releasing": "Ongoing",
    "ongoing": "Ongoing",
    "finished": "Completed",
    "completed": "Completed",
    "hiatus": "Hiatus",
    "paused": "Hiatus",
    "discontinued": "Cancelled",
    "cancelled": "Cancelled",
    "canceled": "Cancelled",
}

_TYPE = {
    "manga": "MANGA",
    "manhwa": "MANHWA",
    "manhua": "MANHUA",
    "other": "OTHER",
    "novel": "NOVEL",
}

# ── rate limit + TTL cache ─────────────────────────────────────────────────
_lock = threading.Lock()
_last = [0.0]

_cache = {}
_cache_lock = threading.Lock()
TTL_SEARCH = 600
TTL_LIST = 300
TTL_INFO = 1800
TTL_PAGES = 3600


def _prune_cache(now):
    for key in [k for k, (_, expires) in _cache.items() if now >= expires]:
        _cache.pop(key, None)


def _cached(key, ttl, fn):
    now = time.monotonic()
    with _cache_lock:
        entry = _cache.get(key)
        if entry is not None and now >= entry[1]:
            del _cache[key]
            entry = None
        if entry is None:
            _prune_cache(now)
    if entry is not None:
        return entry[0]
    value = fn()
    with _cache_lock:
        _cache[key] = (value, time.monotonic() + ttl)
    return value


def _rate_limit():
    with _lock:
        wait = _last[0] + INTERVAL - time.monotonic()
        if wait > 0:
            time.sleep(wait)
        _last[0] = time.monotonic()


def proxy_url(img_url):
    if not img_url:
        return ""
    return f"http://127.0.0.1:{PROXY_PORT}/image?url={urllib.parse.quote(img_url, safe='')}"


# ── signature ──────────────────────────────────────────────────────────────

def sign(text):
    """The `vrf` value for the canonical string `text`."""
    data = str(text).encode("utf-8")
    for table, key, iv in _STAGES:
        out = bytearray(len(data))
        previous = iv
        size = len(key)
        for index, byte in enumerate(data):
            previous = table[(byte ^ key[index % size] ^ previous) & 0xFF]
            out[index] = previous
        data = bytes(out)
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def canonical(path, params):
    """The exact string the signature is computed over.

    Parameters sorted by name, values decoded, and `key[]` rewritten to
    `key[0]`, `key[1]`, … in the order the caller supplied them.
    """
    parts = []
    last = ""
    index = 0
    for key, value in sorted(params or [], key=lambda pair: pair[0]):
        if key.endswith("[]"):
            if last != key:
                index = 0
            last = key
            key = key.replace("[]", f"[{index}]")
            index += 1
        parts.append(f"{key}={value}")
    return path + ("?" + "&".join(parts) if parts else "")


def signed_url(path, params):
    """The API URL for `path` with `vrf` appended."""
    signature = sign(canonical(path, params))
    query = urllib.parse.urlencode(params or [], doseq=True)
    url = f"{BASE}/api{path}" + ("?" + query if query else "")
    return url + ("&" if query else "?") + "vrf=" + signature


# ── pure parsers (fixture-tested) ──────────────────────────────────────────

def _strip_tags(text):
    return _html_unescape(re.sub(r"<[^>]+>", " ", text or "")).replace("\xa0", " ")


def _clean_text(text):
    return re.sub(r"\s+", " ", _strip_tags(text)).strip()


def _clean_number(value):
    try:
        number = float(value)
    except (TypeError, ValueError):
        return str(value).strip()
    return str(int(number)) if number == int(number) else str(number)


def _sort_key(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return float("inf")


def _iso(timestamp):
    try:
        moment = datetime.fromtimestamp(int(timestamp), timezone.utc)
    except (TypeError, ValueError, OSError):
        return ""
    return moment.strftime("%Y-%m-%dT%H:%M:%SZ")


def _status(value):
    text = str(value or "").strip()
    if not text:
        return ""
    return _STATUS.get(text.lower(), text[:1].upper() + text[1:])


def _type(value):
    text = str(value or "").strip()
    return _TYPE.get(text.lower(), text.upper())


def _poster(entry):
    poster = entry.get("poster") or {}
    return poster.get("medium") or poster.get("large") or poster.get("small") or ""


def _list_item(entry):
    return {
        "id": entry.get("hid") or "",
        "title": entry.get("title") or "",
        "image": proxy_url(_poster(entry)),
        "status": _status(entry.get("status")),
        "year": str(entry.get("year") or ""),
        "type": _type(entry.get("type")),
        "chapter": _clean_number(entry.get("latestChapter")) if entry.get("latestChapter") else "",
        "updatedAt": entry.get("chapterUpdatedAt") or "",
        "tags": [],
    }


def parse_items(payload):
    """Map a /api/titles page to contract list items."""
    return [_list_item(entry) for entry in (payload or {}).get("items") or []]


def parse_title(payload):
    """Build the contract info object from /api/titles/<hid> (no chapters yet)."""
    data = (payload or {}).get("data") or {}
    authors = []
    for entry in (data.get("authors") or []) + (data.get("artists") or []):
        name = _clean_text(entry.get("title"))
        if name and name not in authors:
            authors.append(name)
    tags = []
    for entry in (data.get("genres") or []) + (data.get("themes") or []) + (data.get("demographics") or []):
        name = _clean_text(entry.get("title"))
        if name and name not in tags:
            tags.append(name)
    return {
        "id": data.get("hid") or "",
        "title": data.get("title") or "",
        "description": _clean_text(data.get("synopsisHtml")),
        "status": _status(data.get("status")),
        "image": proxy_url(_poster(data)),
        "authors": authors,
        "tags": tags,
        "type": _type(data.get("type")),
        "year": str(data.get("year") or ""),
        "chapters": [],
    }


def parse_chapters(payload):
    """Map one /api/titles/<hid>/chapters page to contract chapters, ascending."""
    chapters = []
    seen = set()
    for entry in (payload or {}).get("items") or []:
        chapter_id = str(entry.get("id") or "")
        if not chapter_id or chapter_id in seen:
            continue
        seen.add(chapter_id)
        number = _clean_number(entry.get("number"))
        chapters.append({
            "_sort": _sort_key(entry.get("number")),
            "id": chapter_id,
            "chapter": number,
            "title": _clean_text(entry.get("name")) or f"Capítulo {number}",
            "group": "",
            "publishAt": _iso(entry.get("createdAt")),
        })
    chapters.sort(key=lambda chapter: chapter["_sort"])
    for chapter in chapters:
        chapter.pop("_sort", None)
    return chapters


def parse_pages(payload):
    """Map /api/chapters/<id> to [{page, img}] through the image proxy."""
    data = (payload or {}).get("data") or {}
    pages = []
    for index, entry in enumerate(data.get("pages") or []):
        url = (entry or {}).get("url") or ""
        if not url:
            continue
        pages.append({"page": index + 1, "img": proxy_url(url)})
    return pages


# ── HTTP (rate limited + cached) ───────────────────────────────────────────

def _request(url):
    request = urllib.request.Request(url, headers={
        "User-Agent": USER_AGENT,
        "Accept": "application/json",
        "Referer": REFERER,
    })
    last_error = None
    for attempt in range(ATTEMPTS):
        _rate_limit()
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return response.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as error:
            # 403 is both "the signature rotated" (permanent) and "slow down"
            # (transient); retrying tells them apart at the cost of two sleeps.
            if error.code == 403 or error.code == 429 or 500 <= error.code < 600:
                last_error = error
                time.sleep(0.8 * (attempt + 1))
                continue
            raise
        except Exception as error:  # noqa: BLE001 — DNS/connection reset/timeout
            last_error = error
            time.sleep(0.8 * (attempt + 1))
    raise last_error


def _get_json(path, params):
    return json.loads(_request(signed_url(path, params)))


# ── public API (mirrors manga_server.py) ───────────────────────────────────

def search(query, mtype=None, offset=0, sort="Best Match"):
    offset = max(0, int(offset or 0))
    page = offset // PAGE_LIMIT + 1
    params = [
        ("keyword", query),
        ("languages[]", "es-la"),
        ("languages[]", "es"),
        ("limit", PAGE_LIMIT),
        ("page", page),
    ]
    wanted = _TYPE.get(str(mtype or "").strip().lower())
    if wanted:
        params.append(("types", wanted.lower()))
    if str(sort).lower() in ("popularity", "popular"):
        params.append(("order[views_30d]", "desc"))
    key = "mf-search:" + canonical("", params)
    payload = _cached(key, TTL_SEARCH, lambda: _get_json("/titles", params))
    results = parse_items(payload)
    meta = (payload or {}).get("meta") or {}
    has_more = bool(meta.get("hasNext"))
    # The API pages by a fixed window, so a page that returned fewer items than
    # the limit still consumed a full page: advancing by the result count would
    # re-request the same page forever.
    consumed = PAGE_LIMIT if has_more else len(results)
    return {
        "results": results,
        "hasMore": has_more,
        "nextOffset": offset + consumed,
    }


def latest(page=1):
    page = max(int(page or 1), 1)
    params = [
        ("languages[]", "es-la"),
        ("languages[]", "es"),
        ("limit", PAGE_LIMIT),
        ("order[chapter_updated_at]", "desc"),
        ("page", page),
    ]
    key = f"mf-latest:{page}"
    payload = _cached(key, TTL_LIST, lambda: _get_json("/titles", params))
    results = parse_items(payload)
    return {
        "results": results,
        "hasMore": bool(((payload or {}).get("meta") or {}).get("hasNext")),
        "nextPage": page + 1,
    }


def hot():
    params = [
        ("languages[]", "es-la"),
        ("languages[]", "es"),
        ("limit", PAGE_LIMIT),
        ("order[views_7d]", "desc"),
    ]
    payload = _cached("mf-hot", TTL_LIST, lambda: _get_json("/titles", params))
    return parse_items(payload)


def _chapter_list(hid):
    """Every chapter in the preferred language, paging until the API is done."""
    for language in ("es-la", "es"):
        chapters = []
        seen = set()
        for page in range(1, CHAPTER_PAGES + 1):
            params = [
                ("language", language),
                ("limit", CHAPTER_LIMIT),
                ("order", "desc"),
                ("page", page),
                ("sort", "number"),
            ]
            payload = _get_json(f"/titles/{hid}/chapters", params)
            added = 0
            for chapter in parse_chapters(payload):
                if chapter["id"] in seen:
                    continue
                seen.add(chapter["id"])
                chapters.append(chapter)
                added += 1
            meta = (payload or {}).get("meta") or {}
            if not added or not meta.get("hasNext"):
                break
        if chapters:
            # Each page is sorted on its own, so the union has to be sorted once
            # more: page 1 holds the newest chapters, page 2 the oldest.
            chapters.sort(key=lambda chapter: _sort_key(chapter["chapter"]))
            return chapters
    return []


def info(hid):
    series = str(hid or "").strip()
    data = _cached(f"mf-title:{series}", TTL_INFO,
                   lambda: parse_title(_get_json(f"/titles/{series}", [])))
    if not data.get("id"):
        return data
    chapters = _cached(f"mf-chapters:{series}", TTL_INFO, lambda: _chapter_list(series))
    return {**data, "chapters": chapters}


def pages(chapter_id):
    chapter = str(chapter_id or "").strip()
    if not chapter:
        return []
    payload = _cached(f"mf-pages:{chapter}", TTL_PAGES,
                      lambda: _get_json(f"/chapters/{chapter}", []))
    return parse_pages(payload)
