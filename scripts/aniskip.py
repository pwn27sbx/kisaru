"""Clean-room AniSkip v2 client, MAL ID resolver, and XDG disk cache for Kisaru.

Uses only the Python standard library (`urllib.request`) plus Kisaru's own
`app_meta` and `titles` helpers so it runs both inside the app venv and in
isolated unit tests.
"""

import json
import math
import os
import re
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

import app_meta
import titles

ANISKIP_BASE = "https://api.aniskip.com/v2/skip-times"
ANILIST_URL = "https://graphql.anilist.co"
JIKAN_SEARCH_URL = "https://api.jikan.moe/v4/anime"

SKIP_TYPES = ("op", "ed", "recap", "mixed-op", "mixed-ed")

HTTP_TIMEOUT = 4.0
TOTAL_BUDGET_SEC = 8.0
MIN_BUDGET_LEFT_SEC = 0.1
TTL_MAL_OK = 30 * 86400
TTL_MAL_MISS = 7 * 86400
TTL_EPISODE_OK = 7 * 86400
TTL_EPISODE_MISS = 24 * 3600
MAX_EPISODE_CACHE_FILES = 2000

MIN_INTERVAL_SEC = 5.0
MAX_OP_ED_SEC = 300.0
DURATION_TOLERANCE_SEC = 5.0

_JIKAN_MIN_INTERVAL = 0.5
_jikan_lock = threading.Lock()
_jikan_last = [0.0]

_cache_lock = threading.Lock()

ANILIST_SEARCH_GQL = """
query ($search: String) {
  Page(page: 1, perPage: 5) {
    media(search: $search, type: ANIME) {
      id
      idMal
      title {
        romaji
        english
        native
      }
      synonyms
      seasonYear
      episodes
      format
    }
  }
}
""".strip()

_SOURCE_TAG_RE = re.compile(
    r"[\(\[\{]\s*(?:sub|dub|latino|español|espanol|audio\s+latino|castellano|"
    r"tv|uncensored|censored|hd|sub\s+español|sub\s+espanol)\s*[\)\]\}]",
    re.IGNORECASE,
)
_ES_ORDINAL_SEASON_RE = re.compile(
    r"\b(\d+)(?:da|ra|ta|na|ma|va|st|nd|rd|th)?\s+temporada\b",
    re.IGNORECASE,
)
_ES_SEASON_RE = re.compile(r"\btemporada\s+(\d+)\b", re.IGNORECASE)
_ES_PART_RE = re.compile(r"\bparte\s+(\d+)\b", re.IGNORECASE)
_EN_ORDINAL_SEASON_RE = re.compile(
    r"\b(\d+)(?:st|nd|rd|th)\s+season\b",
    re.IGNORECASE,
)
_SEASON_NUM_RE = re.compile(r"\bseason\s+(\d+)\b", re.IGNORECASE)
_PART_NUM_RE = re.compile(r"\bpart\s+(\d+)\b", re.IGNORECASE)


def reset_rate_limit_state() -> None:
    """Reset process-wide throttle timestamps (used by tests)."""
    with _jikan_lock:
        _jikan_last[0] = 0.0


def parse_episode_number(episode) -> int | None:
    """Strictly parse a positive integer episode number; reject specials/halves."""
    raw = str(episode if episode is not None else "").strip()
    if not re.fullmatch(r"\d+", raw):
        return None
    num = int(raw)
    return num if num > 0 else None


def parse_positive_int(value) -> int | None:
    raw = str(value if value is not None else "").strip()
    if not re.fullmatch(r"\d+", raw):
        return None
    num = int(raw)
    return num if num > 0 else None


def clean_anime_title(title: str) -> str:
    """Strip source audio/language tags and normalize EN/ES season/part labels."""
    text = str(title or "").strip()
    if not text:
        return ""
    text = _SOURCE_TAG_RE.sub(" ", text)
    text = _ES_ORDINAL_SEASON_RE.sub(r"Season \1", text)
    text = _ES_SEASON_RE.sub(r"Season \1", text)
    text = _ES_PART_RE.sub(r"Part \1", text)
    text = _EN_ORDINAL_SEASON_RE.sub(r"Season \1", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def _extract_season_and_part(cleaned_title: str) -> tuple[int | None, int | None]:
    sm = _SEASON_NUM_RE.search(cleaned_title)
    pm = _PART_NUM_RE.search(cleaned_title)
    return (int(sm.group(1)) if sm else None, int(pm.group(1)) if pm else None)


# ── HTTP transport ──────────────────────────────────────────────────────────

def _default_http(url: str, method: str = "GET", body: bytes | None = None,
                  headers: dict | None = None, timeout: float = HTTP_TIMEOUT) -> tuple[int, str]:
    req_headers = {"User-Agent": app_meta.user_agent()}
    if headers:
        req_headers.update(headers)
    req = urllib.request.Request(url, data=body, headers=req_headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        text = ""
        try:
            text = exc.read().decode("utf-8", "replace")
        except Exception:  # noqa: BLE001
            pass
        return exc.code, text


def _remaining_timeout(deadline: float | None) -> float | None:
    """Return clamped per-call timeout within the total request budget, or None if expired."""
    if deadline is None:
        return HTTP_TIMEOUT
    rem = deadline - time.monotonic()
    if rem <= MIN_BUDGET_LEFT_SEC:
        return None
    return min(HTTP_TIMEOUT, rem)


def _jikan_throttle(deadline: float | None = None) -> bool:
    with _jikan_lock:
        wait = _jikan_last[0] + _JIKAN_MIN_INTERVAL - time.monotonic()
        if wait > 0:
            if deadline is not None and (time.monotonic() + wait + MIN_BUDGET_LEFT_SEC) >= deadline:
                return False
            time.sleep(wait)
        _jikan_last[0] = time.monotonic()
    return True


# ── Disk cache (XDG_CACHE_HOME/kisaru/aniskip) ──────────────────────────────

def _cache_root() -> str:
    return os.path.join(app_meta.cache_home(), app_meta.CACHE_DIR, "aniskip")


def _mal_cache_path() -> str:
    return os.path.join(_cache_root(), "mal_ids.json")


def _episode_cache_path(mal_id: int, episode: int) -> str:
    return os.path.join(_cache_root(), "episodes", f"{mal_id}_{episode}.json")


def _atomic_write_json(path: str, payload: dict) -> None:
    parent = os.path.dirname(path)
    os.makedirs(parent, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(prefix=".tmp-", suffix=".json", dir=parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, ensure_ascii=False)
        os.replace(tmp_path, path)
    except Exception:  # noqa: BLE001
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


def _read_json(path: str) -> dict | None:
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else None
    except (OSError, ValueError):
        return None


def _prune_episode_cache(ep_dir: str) -> None:
    try:
        entries = [
            os.path.join(ep_dir, name)
            for name in os.listdir(ep_dir)
            if name.endswith(".json")
        ]
    except OSError:
        return
    if len(entries) <= MAX_EPISODE_CACHE_FILES:
        return
    entries.sort(key=lambda p: os.path.getmtime(p))
    for old in entries[: len(entries) - MAX_EPISODE_CACHE_FILES]:
        try:
            os.unlink(old)
        except OSError:
            pass


def _load_mal_cache_entry(show_id: str) -> dict | None:
    with _cache_lock:
        table = _read_json(_mal_cache_path()) or {}
    entry = table.get(show_id)
    if not isinstance(entry, dict):
        return None
    ttl = TTL_MAL_OK if entry.get("mal_id") else TTL_MAL_MISS
    if time.time() - float(entry.get("checked_at", 0)) < ttl:
        return entry
    return None


def _save_mal_cache_entry(show_id: str, mal_id: int | None, source: str) -> None:
    with _cache_lock:
        path = _mal_cache_path()
        table = _read_json(path) or {}
        table[show_id] = {
            "mal_id": mal_id,
            "source": source,
            "checked_at": time.time(),
        }
        _atomic_write_json(path, table)


# ── MAL ID resolution with multi-signal confidence check ────────────────────

def _candidate_matches(query_titles: list[str], candidate: dict,
                       year: int | None, episode: int) -> bool:
    mal_id = parse_positive_int(candidate.get("mal_id"))
    if not mal_id:
        return False

    cand_titles = [
        clean_anime_title(t)
        for t in candidate.get("titles", [])
        if t and str(t).strip()
    ]
    if not cand_titles:
        return False

    matched_title = False
    for q in query_titles:
        q_season, q_part = _extract_season_and_part(q)
        for ct in cand_titles:
            if not titles.titles_match(q, ct):
                continue
            c_season, c_part = _extract_season_and_part(ct)
            if q_season != c_season or q_part != c_part:
                continue
            matched_title = True
            break
        if matched_title:
            break

    if not matched_title:
        return False

    cand_year = parse_positive_int(candidate.get("year"))
    if year and cand_year and abs(year - cand_year) > 1:
        return False

    cand_eps = parse_positive_int(candidate.get("episodes"))
    if cand_eps and episode > cand_eps:
        return False

    return True


def _pick_best_candidate(query_titles: list[str], candidates: list[dict],
                         year: int | None, episode: int) -> int | None:
    matches = [
        c for c in candidates
        if _candidate_matches(query_titles, c, year, episode)
    ]
    if not matches:
        return None
    if len(matches) == 1:
        return parse_positive_int(matches[0].get("mal_id"))

    # Tie-breaker: prefer TV over OVA/SPECIAL/MOVIE/MUSIC.
    tv_matches = [c for c in matches if str(c.get("format") or "").upper() == "TV"]
    if len(tv_matches) == 1:
        return parse_positive_int(tv_matches[0].get("mal_id"))

    # Ambiguous even after format tie-breaker -> fail safe (no skip).
    unique_ids = {parse_positive_int(c.get("mal_id")) for c in (tv_matches or matches)}
    if len(unique_ids) == 1:
        return next(iter(unique_ids))
    return None


def _query_anilist(query: str, http_get, deadline: float | None = None) -> list[dict] | None:
    timeout = _remaining_timeout(deadline)
    if timeout is None:
        return None
    body = json.dumps({
        "query": ANILIST_SEARCH_GQL,
        "variables": {"search": query},
    }).encode("utf-8")
    try:
        status, raw = http_get(
            ANILIST_URL,
            method="POST",
            body=body,
            headers={"Content-Type": "application/json", "Accept": "application/json"},
            timeout=timeout,
        )
    except Exception:  # noqa: BLE001
        return None
    if status != 200:
        return None
    try:
        data = json.loads(raw)
        media = (data.get("data") or {}).get("Page", {}).get("media") or []
    except (ValueError, AttributeError):
        return None

    out = []
    for item in media:
        title_obj = item.get("title") or {}
        all_titles = [
            title_obj.get("romaji"),
            title_obj.get("english"),
            title_obj.get("native"),
            *(item.get("synonyms") or []),
        ]
        out.append({
            "mal_id": item.get("idMal"),
            "titles": [t for t in all_titles if t],
            "year": item.get("seasonYear"),
            "episodes": item.get("episodes"),
            "format": item.get("format") or "",
        })
    return out


def _query_jikan(query: str, http_get, deadline: float | None = None) -> list[dict] | None:
    if len(query) < 2:
        return []
    if not _jikan_throttle(deadline):
        return None
    timeout = _remaining_timeout(deadline)
    if timeout is None:
        return None
    url = f"{JIKAN_SEARCH_URL}?{urllib.parse.urlencode({'q': query, 'limit': 5})}"
    try:
        status, raw = http_get(url, method="GET", timeout=timeout)
    except Exception:  # noqa: BLE001
        return None
    if status != 200:
        return None
    try:
        data = json.loads(raw)
        items = data.get("data") or []
    except (ValueError, AttributeError):
        return None

    out = []
    for item in items:
        all_titles = [
            item.get("title"),
            item.get("title_english"),
            item.get("title_japanese"),
            *(item.get("title_synonyms") or []),
        ]
        out.append({
            "mal_id": item.get("mal_id"),
            "titles": [t for t in all_titles if t],
            "year": item.get("year"),
            "episodes": item.get("episodes"),
            "format": item.get("type") or "",
        })
    return out


def resolve_mal_id(show_id: str, meta: dict | None, episode: int,
                   http_get=None, deadline: float | None = None) -> tuple[int | None, str]:
    """Resolve a Kisaru show to a MyAnimeList ID with fail-safe confidence checks."""
    http = http_get or _default_http
    meta = meta or {}

    # Tier 1: native MAL ID from AllAnime SHOW_META_GQL.
    native_mal = parse_positive_int(meta.get("malId") or meta.get("mal_id"))
    if native_mal:
        return native_mal, "allanime"

    # Tier 2: persistent disk cache (positive + negative TTL).
    if show_id:
        cached = _load_mal_cache_entry(show_id)
        if cached is not None:
            return parse_positive_int(cached.get("mal_id")), str(cached.get("source") or "cache")

    # Tier 3: title resolution (AniList GraphQL -> Jikan v4 fallback).
    raw_titles = [
        meta.get("name"),
        meta.get("englishName") or meta.get("english_name"),
        meta.get("nativeName") or meta.get("native_name"),
    ]
    cleaned_titles = []
    seen = set()
    for t in raw_titles:
        c = clean_anime_title(t or "")
        if c and c.lower() not in seen:
            seen.add(c.lower())
            cleaned_titles.append(c)

    if not cleaned_titles:
        return None, "missing_title"

    year = parse_positive_int(meta.get("year"))
    primary_query = cleaned_titles[0]

    anilist_cands = _query_anilist(primary_query, http, deadline=deadline)
    if anilist_cands is not None:
        picked = _pick_best_candidate(cleaned_titles, anilist_cands, year, episode)
        if picked:
            if show_id:
                _save_mal_cache_entry(show_id, picked, "anilist")
            return picked, "anilist"

    jikan_cands = _query_jikan(primary_query, http, deadline=deadline)
    if jikan_cands is not None:
        picked = _pick_best_candidate(cleaned_titles, jikan_cands, year, episode)
        if picked:
            if show_id:
                _save_mal_cache_entry(show_id, picked, "jikan")
            return picked, "jikan"

    # Only negative-cache when at least one upstream actually answered cleanly.
    if show_id and (anilist_cands is not None or jikan_cands is not None):
        _save_mal_cache_entry(show_id, None, "miss")
    return None, "not_found"


# ── AniSkip v2 fetch & interval sanitization ────────────────────────────────

def _safe_finite_float(value, default: float = 0.0) -> float:
    try:
        num = float(value)
        return num if math.isfinite(num) else default
    except (TypeError, ValueError):
        return default


def sanitize_intervals(raw_results: list[dict], duration: float = 0.0) -> list[dict]:
    """Filter malformed/vandalized intervals and clamp within duration tolerance."""
    cleaned = []
    dur = _safe_finite_float(duration, 0.0)
    has_dur = dur > 0.0
    for item in raw_results or []:
        if not isinstance(item, dict):
            continue
        interval = item.get("interval") or {}
        try:
            start = float(interval.get("startTime"))
            end = float(interval.get("endTime"))
        except (TypeError, ValueError):
            continue
        if not (math.isfinite(start) and math.isfinite(end)):
            continue
        skip_type = str(item.get("skipType") or "").strip().lower()
        if skip_type not in SKIP_TYPES:
            continue
        if start < 0 or end <= start:
            continue
        length = end - start
        if length < MIN_INTERVAL_SEC:
            continue
        if skip_type in ("op", "ed", "mixed-op", "mixed-ed") and length > MAX_OP_ED_SEC:
            continue
        if has_dur:
            if start >= dur:
                continue
            if end > dur + DURATION_TOLERANCE_SEC:
                continue
            if end > dur:
                end = dur
            if (end - start) < MIN_INTERVAL_SEC:
                continue
        ep_len = _safe_finite_float(item.get("episodeLength"), 0.0)
        if ep_len < 0.0:
            ep_len = 0.0
        cleaned.append({
            "skip_type": skip_type,
            "skip_id": str(item.get("skipId") or f"{skip_type}:{start:.1f}:{end:.1f}"),
            "start_time": round(start, 3),
            "end_time": round(end, 3),
            "episode_length": ep_len,
        })
    cleaned.sort(key=lambda x: x["start_time"])
    return cleaned


def _fetch_aniskip_once(mal_id: int, episode: int, episode_length: float,
                        http_get, deadline: float | None = None) -> tuple[str, list[dict]]:
    timeout = _remaining_timeout(deadline)
    if timeout is None:
        return "error", []
    params = [("types[]", t) for t in SKIP_TYPES]
    safe_len = _safe_finite_float(episode_length, 0.0)
    ep_len_val = int(round(safe_len)) if safe_len > 0.0 else 0
    params.append(("episodeLength", str(ep_len_val)))
    url = f"{ANISKIP_BASE}/{mal_id}/{episode}?{urllib.parse.urlencode(params)}"
    try:
        status, raw = http_get(url, method="GET", timeout=timeout)
    except Exception:  # noqa: BLE001
        return "error", []
    if status == 404:
        return "not_found", []
    if status != 200:
        return "error", []
    try:
        data = json.loads(raw)
    except ValueError:
        return "error", []
    if not data.get("found"):
        return "not_found", []
    return "ok", data.get("results") or []


def get_skip_times(show_id: str, episode, meta: dict | None = None,
                   duration: float = 0.0, http_get=None,
                   total_budget: float = TOTAL_BUDGET_SEC) -> dict:
    """Resolve MAL ID and return sanitized AniSkip intervals with disk cache."""
    http = http_get or _default_http
    deadline = time.monotonic() + max(0.0, _safe_finite_float(total_budget, TOTAL_BUDGET_SEC))
    ep_num = parse_episode_number(episode)
    if ep_num is None:
        return {
            "found": False,
            "mal_id": None,
            "source": "",
            "intervals": [],
            "cached": False,
            "stale": False,
            "reason": "non_integer_episode",
        }

    dur = _safe_finite_float(duration, 0.0)
    if dur < 0.0:
        dur = 0.0

    mal_id, source = resolve_mal_id(show_id, meta, ep_num, http_get=http, deadline=deadline)
    if not mal_id:
        return {
            "found": False,
            "mal_id": None,
            "source": source,
            "intervals": [],
            "cached": False,
            "stale": False,
            "reason": "mal_id_not_found",
        }

    cache_path = _episode_cache_path(mal_id, ep_num)
    with _cache_lock:
        cached_entry = _read_json(cache_path)

    if cached_entry is not None:
        ttl = TTL_EPISODE_OK if cached_entry.get("found") else TTL_EPISODE_MISS
        age = time.time() - float(cached_entry.get("fetched_at", 0))
        if age < ttl:
            raw_cached = cached_entry.get("raw_results") or []
            intervals = sanitize_intervals(raw_cached, duration=dur)
            return {
                "found": bool(intervals),
                "mal_id": mal_id,
                "source": source,
                "intervals": intervals,
                "cached": True,
                "stale": False,
                "reason": "ok" if intervals else "not_found",
            }

    state, raw_results = _fetch_aniskip_once(mal_id, ep_num, dur, http, deadline=deadline)
    if state == "not_found" and dur > 0:
        # Retry once with wildcard episodeLength=0 to tolerate encode-length drift.
        state, raw_results = _fetch_aniskip_once(mal_id, ep_num, 0.0, http, deadline=deadline)

    if state == "error":
        # Offline / 429 / 5xx fallback: serve stale cache if available.
        if cached_entry is not None and cached_entry.get("found"):
            stale_intervals = sanitize_intervals(cached_entry.get("raw_results") or [], duration=dur)
            if stale_intervals:
                return {
                    "found": True,
                    "mal_id": mal_id,
                    "source": source,
                    "intervals": stale_intervals,
                    "cached": True,
                    "stale": True,
                    "reason": "stale_cache",
                }
        return {
            "found": False,
            "mal_id": mal_id,
            "source": source,
            "intervals": [],
            "cached": False,
            "stale": False,
            "reason": "upstream_unavailable",
        }

    intervals = sanitize_intervals(raw_results, duration=dur)
    with _cache_lock:
        _atomic_write_json(cache_path, {
            "mal_id": mal_id,
            "episode": ep_num,
            "found": bool(raw_results),
            "raw_results": raw_results,
            "fetched_at": time.time(),
        })
        _prune_episode_cache(os.path.dirname(cache_path))

    return {
        "found": bool(intervals),
        "mal_id": mal_id,
        "source": source,
        "intervals": intervals,
        "cached": False,
        "stale": False,
        "reason": "ok" if intervals else "not_found",
    }
