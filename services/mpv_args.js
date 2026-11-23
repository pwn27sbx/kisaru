// Pure mpv command-line builder for modules/anime/components/DetailView.qml.
// Extracted so option escaping, per-show/global skip gating, and dynamic API
// URL wiring are unit-tested in Node (tests/mpv_args.test.js).

function _sanitizeOptVal(value) {
    // Strip commas and newlines that could split mpv --script-opts entries.
    return String(value === undefined || value === null ? "" : value)
        .replace(/[\r\n,]/g, "");
}

function buildMpvArgs(opts) {
    var cfg = opts || {};
    var url = String(cfg.url || "");
    if (url.length === 0) {
        return [];
    }

    var args = [
        "mpv",
        "--fs",
        "--force-window=yes",
        "--title=" + (cfg.title || "Anime"),
        "--no-terminal"
    ];

    if (cfg.referer && String(cfg.referer).length > 0) {
        args.push("--referrer=" + String(cfg.referer));
    }
    if (cfg.subtitle && String(cfg.subtitle).length > 0) {
        args.push("--sub-file=" + String(cfg.subtitle));
    }

    var skipMode = String(cfg.skipMode || "off");
    var apiUrl = _sanitizeOptVal(cfg.apiUrl).trim();
    var scriptPath = String(cfg.skipScriptPath || "").trim();
    var showId = _sanitizeOptVal(cfg.showId).trim();
    var episode = _sanitizeOptVal(cfg.episode).trim();

    if (skipMode !== "off"
            && !cfg.showSkipDisabled
            && apiUrl.length > 0
            && scriptPath.length > 0
            && showId.length > 0
            && episode.length > 0) {
        args.push("--script=" + scriptPath);
        var scriptOpts = [
            "kisaru_skip-api=" + apiUrl,
            "kisaru_skip-show_id=" + showId,
            "kisaru_skip-ep=" + episode,
            "kisaru_skip-mode=" + _sanitizeOptVal(skipMode),
            "kisaru_skip-recap=" + (cfg.skipRecap === true ? "yes" : "no"),
            "kisaru_skip-lang=" + (cfg.lang === "es" ? "es" : "en")
        ];
        if (cfg.showTitle && String(cfg.showTitle).length > 0) {
            scriptOpts.push("kisaru_skip-title=" + encodeURIComponent(String(cfg.showTitle)));
        }
        args.push("--script-opts-append=" + scriptOpts.join(","));
    }

    // `--` keeps a URL starting with "-" from being parsed as an mpv option.
    args.push("--");
    args.push(url);
    return args;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { buildMpvArgs: buildMpvArgs };
}
