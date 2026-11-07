"""What the local image proxy is allowed to fetch.

`/image?url=` used to fetch any http(s) URL, loopback and LAN included, so a
page (or a redirect) could make a backend reach services only this machine
sees (audit 2026-11-06, finding 18). The proxy now fetches only public
addresses: http(s), a resolvable name, and every resolved address outside the
private, loopback, link-local and reserved ranges.
"""

import ipaddress
import socket
from urllib.parse import urlsplit


class BlockedTarget(ValueError):
    """The proxy refused a URL that is not a public image address."""


_BLOCKED_NAMES = ("localhost",)
_BLOCKED_SUFFIXES = (".localhost", ".local", ".internal", ".home.arpa", ".lan")


def _resolve(host, port):
    infos = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    return [info[4][0] for info in infos]


def _is_public(address):
    """False for loopback, private, link-local, reserved, multicast and 0.0.0.0."""
    try:
        ip = ipaddress.ip_address(str(address).split("%", 1)[0])
    except ValueError:
        return False
    return ip.is_global and not ip.is_multicast


def proxy_target_allowed(url, resolver=None):
    """True when `url` is an http(s) URL whose every address is public."""
    try:
        parts = urlsplit(str(url or ""))
    except ValueError:
        return False
    if parts.scheme not in ("http", "https"):
        return False

    host = (parts.hostname or "").lower()
    if not host:
        return False
    try:
        literal = ipaddress.ip_address(host.split("%", 1)[0])
    except ValueError:
        literal = None
    if literal is not None:
        return literal.is_global and not literal.is_multicast

    if host in _BLOCKED_NAMES or any(host.endswith(suffix) for suffix in _BLOCKED_SUFFIXES):
        return False

    resolver = resolver or _resolve
    try:
        addresses = resolver(host, parts.port or (443 if parts.scheme == "https" else 80))
    except (OSError, UnicodeError):
        return False
    if not addresses:
        return False
    return all(_is_public(address) for address in addresses)
