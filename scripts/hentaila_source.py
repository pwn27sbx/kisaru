"""Private anime source adapter.

The provider is server-rendered HTML. Search cards expose media links, series
pages carry SvelteKit episode data, and episode pages expose one /play/ loader.
The loader's module resolves a token to an HLS URL. Secondary /get/ embeds are
advertising/analytics surfaces and are never fetched.

Parsers are pure and fixture-tested. HTTP is rate-limited, size-bounded and
restricted to approved public HTTPS hosts. No query, title or URL is logged.
"""

import html as html_lib
import http.client
import re
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

from proxy_policy import proxy_target_allowed

BASE = "https://hentaila.com"
USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) "
    "Gecko/20100101 Firefox/128.0"
)
PROVIDER_HOSTS = frozenset({"hentaila.com"})
COVER_HOSTS = frozenset({"hentaila.com", "cdn.hentaila.com"})
PLAYER_HOSTS = frozenset({"hentaila.com", "cdn.dotanborito.net"})
STREAM_HOSTS = PLAYER_HOSTS

INTERVAL = 1.0
TIMEOUT = 25
MAX_HTML_BYTES = 2 * 1024 * 1024
PAGE_SIZE = 20

TTL_SEARCH = 600
TTL_SERIES = 1800
TTL_LINKS = 300

_lock = threading.Lock()
_last = [0.0]
_cache = {}
_cache_lock = threading.Lock()


class SourceError(ValueError):
    """A fixed-code failure safe to show without provider data."""

    def __init__(self, code):
        self.code = code
        super().__init__(code)


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_opener = urllib.request.build_opener(_NoRedirect)


def _rate_limit():
    with _lock:
        wait = _last[0] + INTERVAL - time.monotonic()
        if wait > 0:
            time.sleep(wait)
        _last[0] = time.monotonic()


def _cached(key, ttl, loader):
    now = time.monotonic()
    with _cache_lock:
        entry = _cache.get(key)
        if entry and now < entry[1]:
            return entry[0]
    value = loader()
    with _cache_lock:
        _cache[key] = (value, now + ttl)
    return value


def clear_cache():
    with _cache_lock:
        _cache.clear()


def validate_url(url, allowed_hosts=PROVIDER_HOSTS):
    try:
        parts = urllib.parse.urlsplit(str(url or ""))
        port = parts.port
    except (TypeError, ValueError):
        raise SourceError("invalid_url") from None
    host = (parts.hostname or "").lower().rstrip(".")
    if parts.scheme != "https" or host not in allowed_hosts:
        raise SourceError("blocked_url")
    if parts.username is not None or parts.password is not None:
        raise SourceError("blocked_url")
    if port is not None and port != 443:
        raise SourceError("blocked_url")
    if not proxy_target_allowed(url):
        raise SourceError("blocked_url")
    return parts


def _fetch(url, referer=None, allowed_hosts=PROVIDER_HOSTS):
    current = str(url or "")
    for _ in range(5):
        validate_url(current, allowed_hosts)
        if urllib.parse.urlsplit(current).path.startswith("/get/"):
            raise SourceError("blocked_path")
        headers = {
            "User-Agent": USER_AGENT,
            "Accept": "text/html,application/javascript,application/x-mpegURL;q=0.9,*/*;q=0.5",
            "Accept-Language": "es-ES,es;q=0.9",
        }
        if referer:
            validate_url(referer, allowed_hosts)
            headers["Referer"] = referer
        _rate_limit()
        request = urllib.request.Request(current, headers=headers)
        try:
            with _opener.open(request, timeout=TIMEOUT) as response:
                body = response.read(MAX_HTML_BYTES + 1)
                if len(body) > MAX_HTML_BYTES:
                    raise SourceError("response_too_large")
                return body.decode("utf-8", "replace"), response.geturl()
        except urllib.error.HTTPError as error:
            if error.code in (301, 302, 303, 307, 308):
                location = error.headers.get("Location", "")
                if not location:
                    raise SourceError("http_error") from None
                current = urllib.parse.urljoin(current, location)
                continue
            raise SourceError("http_error") from None
        except SourceError:
            raise
        except (urllib.error.URLError, http.client.HTTPException, TimeoutError, OSError):
            raise SourceError("network_error") from None
    raise SourceError("too_many_redirects")


def _clean_text(value):
    return html_lib.unescape(re.sub(r"<[^>]+>", "", value or "")).strip()


def _first_match(pattern, text, flags=re.S | re.I):
    match = re.search(pattern, text, flags)
    return match.group(1).strip() if match else ""


def _attr(attrs, name):
    match = re.search(rf"\b{re.escape(name)}\s*=\s*([\"'])(.*?)\1", attrs, re.I | re.S)
    return match.group(2).strip() if match else ""


def _media_slug(href):
    match = re.match(r"^/media/([^/?#]+)/?$", urllib.parse.urlsplit(href).path)
    return urllib.parse.unquote(match.group(1)) if match else ""


def parse_search(page):
    items = []
    blocks = re.findall(
        r'<article\b[^>]*class="[^"]*group/item[^"]*"[^>]*>(.*?)</article>',
        page,
        re.S | re.I,
    )
    for block in blocks:
        slug = ""
        for attrs in re.findall(r"<a\b([^>]+)>", block, re.I):
            href = _first_match(r'href="([^"]+)"', attrs, re.I)
            slug = _media_slug(href)
            if slug:
                break
        if not slug:
            continue
        name = _clean_text(_first_match(r"<h3\b[^>]*>(.*?)</h3>", block))
        cover = ""
        for attrs in re.findall(r"<img\b([^>]+)>", block, re.I):
            classes = _first_match(r'class="([^"]+)"', attrs, re.I)
            if "aspect-poster" in classes:
                cover = _first_match(r'src="([^"]+)"', attrs, re.I)
                break
        items.append({
            "id": slug,
            "name": name,
            "english_name": name,
            "native_name": "",
            "thumbnail": cover,
            "score": None,
            "episode_count": "",
            "available_episodes": {"sub": 1, "dub": 0, "raw": 0},
        })
    return items


def has_next_page(page, current_page):
    pages = []
    for href in re.findall(r'href="([^"]+)"', html_lib.unescape(page), re.I):
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(href).query)
        for value in query.get("page", []):
            try:
                pages.append(int(value))
            except ValueError:
                continue
    return any(value > int(current_page) for value in pages)


def parse_series(page):
    name = _clean_text(_first_match(r"<h1\b[^>]*>(.*?)</h1>", page))
    cover = ""
    for attrs in re.findall(r"<img\b([^>]+)>", page, re.I):
        classes = _first_match(r'class="([^"]+)"', attrs, re.I)
        if "aspect-poster" in classes:
            cover = _first_match(r'src="([^"]+)"', attrs, re.I)
            break

    numbers = []
    episode_data = re.search(r"episodes\s*:\s*\[(.*?)\]", page, re.S | re.I)
    if episode_data:
        for match in re.finditer(r"number\s*:\s*[\"']?([^,\"'}]+)", episode_data.group(1)):
            numbers.append(match.group(1).strip())
    if not numbers:
        for href in re.findall(r'href="([^"]+)"', page, re.I):
            match = re.match(r"^/media/[^/]+/([^/?#]+)/?$", urllib.parse.urlsplit(href).path)
            if match:
                numbers.append(urllib.parse.unquote(match.group(1)))

    def sort_key(value):
        try:
            return (0, float(value))
        except ValueError:
            return (1, value)

    return {
        "name": name,
        "thumbnail": cover,
        "episodes": sorted(set(numbers), key=sort_key),
    }


def parse_play_references(page):
    players = []
    seen = set()
    for attrs in re.findall(r"<iframe\b([^>]+)>", page, re.I):
        src = _attr(attrs, "src")
        if not src:
            continue
        try:
            player_url = urllib.parse.urljoin(BASE, src)
            parts = urllib.parse.urlsplit(player_url)
        except ValueError:
            raise SourceError("invalid_player") from None
        if not parts.path.startswith("/play/"):
            continue
        if (parts.hostname or "").lower() not in PLAYER_HOSTS:
            raise SourceError("blocked_player")
        match = re.fullmatch(r"/play/([A-Za-z0-9]{32})", parts.path)
        if not match:
            raise SourceError("invalid_player")
        if player_url in seen:
            raise SourceError("duplicate_player")
        seen.add(player_url)
        players.append((match.group(1), player_url))
    if not players:
        raise SourceError("player_not_found")
    return players


def parse_play_reference(page):
    players = parse_play_references(page)
    if len(players) != 1:
        raise SourceError("player_not_found")
    return players[0]


def parse_play_token(page):
    return parse_play_reference(page)[0]


def parse_player_module(page):
    for attrs in re.findall(r"<script\b([^>]+)>", page, re.I):
        script_type = _attr(attrs, "type")
        src = _attr(attrs, "src")
        if script_type == "module" and src.startswith("/assets/"):
            return src
    raise SourceError("player_module_not_found")


def parse_hls_base(script, base_url):
    match = re.search(r'https://[^"\'\s]+/m3u8/', script)
    if match:
        value = match.group(0)
    else:
        match = re.search(r'["\'](/[^"\']*m3u8/)["\']', script)
        if not match:
            raise SourceError("hls_not_found")
        value = match.group(1)
    url = urllib.parse.urljoin(base_url, value)
    validate_url(url, STREAM_HOSTS)
    return url


def _safe_slug(slug):
    if not re.fullmatch(r"[A-Za-z0-9-]+", str(slug or "")):
        raise SourceError("invalid_id")
    return slug


def _safe_episode(episode):
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)?", str(episode or "")):
        raise SourceError("invalid_episode")
    return str(episode)


def search(query, page=1):
    query = str(query or "").strip()
    if not query or len(query) > 120:
        raise SourceError("invalid_query")
    try:
        page = int(page or 1)
    except (TypeError, ValueError):
        raise SourceError("invalid_page") from None
    page = max(1, page)
    params = urllib.parse.urlencode({"search": query, "page": page})
    url = f"{BASE}/catalogo?{params}"

    def load():
        text, effective = _fetch(url)
        items = parse_search(text)
        for item in items:
            item["thumbnail"] = urllib.parse.urljoin(effective, item["thumbnail"])
        return items, has_next_page(text, page)

    items, has_more = _cached(f"search:{query}:{page}", TTL_SEARCH, load)
    return {
        "results": items,
        "hasMore": has_more,
        "nextPage": page + 1 if has_more else page,
    }


def series(slug):
    slug = _safe_slug(slug)
    url = f"{BASE}/media/{slug}"

    def load():
        text, effective = _fetch(url)
        result = parse_series(text)
        result["thumbnail"] = urllib.parse.urljoin(effective, result["thumbnail"])
        result["id"] = slug
        return result

    return _cached(f"series:{slug}", TTL_SERIES, load)


def links(slug, episode):
    slug = _safe_slug(slug)
    episode = _safe_episode(episode)
    episode_url = f"{BASE}/media/{slug}/{episode}"

    def load():
        page, _ = _fetch(episode_url)
        last_error = SourceError("player_not_found")
        for token, player_url in parse_play_references(page):
            try:
                player_page, _ = _fetch(
                    player_url, referer=episode_url, allowed_hosts=PLAYER_HOSTS
                )
                module = parse_player_module(player_page)
                module_url = urllib.parse.urljoin(player_url, module)
                script, effective = _fetch(
                    module_url, referer=player_url, allowed_hosts=PLAYER_HOSTS
                )
                hls_base = parse_hls_base(script, effective)
                stream_url = hls_base + token
                validate_url(stream_url, STREAM_HOSTS)
                return [{
                    "quality": "best",
                    "url": stream_url,
                    "type": "m3u8",
                    "provider": "HentaiLA",
                    "referer": player_url,
                    "subtitle": "",
                    "subtitle_label": "Español",
                }]
            except SourceError as error:
                last_error = error
        raise last_error

    return _cached(f"links:{slug}:{episode}", TTL_LINKS, load)


def proxy_cover(url, manga_base):
    raw = urllib.parse.urljoin(BASE, str(url or ""))
    validate_url(raw, COVER_HOSTS)
    return f"{str(manga_base).rstrip('/')}/image?url={urllib.parse.quote(raw, safe='')}"
