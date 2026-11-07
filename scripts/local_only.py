"""Loopback-only guard shared by the local backends.

The manga and novel servers answer HTTP on 127.0.0.1 for the QML panel. Two
things that are not the panel can still reach that port: a page open in a
browser (a cross-site request) and a page whose domain resolves to loopback
(DNS rebinding). Both send a `Host` and, when crossing origins, an `Origin`
that a QML XMLHttpRequest never sends, so the servers can tell them apart
(audit 2026-11-06, findings 1 and 3).
"""

from urllib.parse import urlsplit

LOOPBACK_HOSTS = ("127.0.0.1", "localhost", "::1")


def is_loopback_host(host_header):
    """True when Host names this machine's loopback, or is absent.

    A browser always sends Host, so a page that resolves an attacker domain to
    127.0.0.1 (DNS rebinding) is the case this refuses. A missing Host cannot
    be a browser.
    """
    if not host_header:
        return True
    try:
        host = urlsplit("//" + host_header.strip()).hostname
    except ValueError:
        return False
    return (host or "").lower() in LOOPBACK_HOSTS


def is_allowed_origin(origin):
    """True when there is no browser origin, or it is a loopback page.

    QML's XMLHttpRequest sends no Origin (or a non-http one such as
    `file://`), so only an http(s) origin from another host is refused. A
    browser page always sends one, and that is what a cross-site request looks
    like.
    """
    if not origin:
        return True
    try:
        parts = urlsplit(origin)
    except ValueError:
        return False
    if parts.scheme not in ("http", "https"):
        return True
    return (parts.hostname or "").lower() in LOOPBACK_HOSTS
