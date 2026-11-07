pragma Singleton
import Quickshell

// Shared XMLHttpRequest helpers for the backend-backed services (Manga, Anime,
// Novel), which each carried a byte-identical private copy of these.
//
// Every call builds its own request object, so nothing is shared between callers.
// A request that never answers used to leave its callback unrun forever and the
// panel's `isFetching…` flag stuck; both helpers now time out and report it
// (audit 2026-11-06, finding 16).
Singleton {
    property int timeout: 20000

    // onDone(err, body) — err is null on success, "HTTP <status>", "timeout"
    // or "network" otherwise.
    function get(url, onDone, timeoutMs) {
        _send("GET", url, null, onDone, timeoutMs)
    }

    function post(url, data, onDone, timeoutMs) {
        _send("POST", url, data, onDone, timeoutMs)
    }

    function _send(method, url, data, onDone, timeoutMs) {
        var settled = false

        function finish(err, body) {
            if (settled) return
            settled = true
            onDone(err, body)
        }

        var xhr = new XMLHttpRequest()
        xhr.timeout = timeoutMs === undefined ? timeout : timeoutMs
        xhr.ontimeout = function() { finish("timeout", null) }
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || settled) return
            if (xhr.status === 200) finish(null, xhr.responseText)
            else if (xhr.status === 0) finish("network", null)
            else finish("HTTP " + xhr.status, null)
        }
        xhr.open(method, url)
        if (method === "POST") xhr.setRequestHeader("Content-Type", "application/json")
        xhr.send(data === null ? null : JSON.stringify(data))
    }
}
