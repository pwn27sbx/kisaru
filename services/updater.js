// Release check for the update banner, pure JS so `node --test` covers it.
//
// Two sources feed one decision:
//   * the installed manifest (`omarchy/pwnsxb.kisaru/manifest.json`) holds the
//     local version;
//   * `scripts/update-check.sh` prints the checkout state and the remote tags.
//
// Only numbered releases count (owner decision): a tag must be exactly
// `vX.Y.Z`. Prereleases (`v1.2.3-rc.1`), annotated-tag peeled lines
// (`...^{}`) and anything else are ignored, so a branch push or a release
// candidate never turns into a banner.
//
// Top-level functions only: QML imports this file with
// `import "updater.js" as Core`, while `node --test` reads the guarded
// `module.exports` at the bottom (the same shape as services/omarchy_version.js).

// "1.2.3" -> { major: 1, minor: 2, patch: 3 }; anything else -> null.
function parseVersion(text) {
    var value = String(text === undefined || text === null ? "" : text).trim()
    var match = value.match(/^(\d+)\.(\d+)\.(\d+)$/)
    if (!match) return null
    return { major: Number(match[1]), minor: Number(match[2]), patch: Number(match[3]) }
}

// -1 / 0 / 1, or null when either side is not a plain X.Y.Z version.
function compareVersions(a, b) {
    var left = parseVersion(a)
    var right = parseVersion(b)
    if (left === null || right === null) return null
    if (left.major !== right.major) return left.major < right.major ? -1 : 1
    if (left.minor !== right.minor) return left.minor < right.minor ? -1 : 1
    if (left.patch !== right.patch) return left.patch < right.patch ? -1 : 1
    return 0
}

// A tag reference, as `git ls-remote --tags --refs` prints the ref part:
// "refs/tags/v1.2.3" -> "1.2.3"; malformed or prerelease -> "".
function versionFromTag(ref) {
    var text = String(ref === undefined || ref === null ? "" : ref).trim()
    if (text.indexOf("refs/tags/") === 0) text = text.slice("refs/tags/".length)
    var match = text.match(/^v(\d+\.\d+\.\d+)$/)
    return match ? match[1] : ""
}

// One `git ls-remote` line: "<sha>\trefs/tags/v1.2.3". Blank lines, peeled
// lines and non-release tags are skipped.
function parseTags(output) {
    var tags = []
    var lines = String(output === undefined || output === null ? "" : output).split("\n")
    for (var i = 0; i < lines.length; i++) {
        var fields = lines[i].trim().split(/\s+/)
        if (fields.length === 0 || fields[0] === "") continue
        var version = versionFromTag(fields[fields.length - 1])
        if (version !== "") tags.push(version)
    }
    return tags
}

// The highest release among already-normalised versions ("" when none).
function highestVersion(tags) {
    var best = ""
    for (var i = 0; i < (tags || []).length; i++) {
        var candidate = String(tags[i] || "")
        if (parseVersion(candidate) === null) continue
        if (best === "" || compareVersions(candidate, best) > 0) best = candidate
    }
    return best
}

// The remote version to offer, or "" when there is nothing newer.
function updateAvailable(local, tags) {
    if (parseVersion(local) === null) return ""
    var best = highestVersion(Array.isArray(tags) ? tags : parseTags(tags))
    if (best === "") return ""
    return compareVersions(best, local) > 0 ? best : ""
}

// The installed manifest's version, or "" when the file is missing, is not
// JSON, or does not carry a plain X.Y.Z version.
function versionFromManifest(text) {
    try {
        var data = JSON.parse(String(text === undefined || text === null ? "" : text))
        var version = data && typeof data.version === "string" ? data.version.trim() : ""
        return parseVersion(version) === null ? "" : version
    } catch (e) {
        return ""
    }
}

// The key=value lines `scripts/update-check.sh` prints. `error` is true when
// the remote could not be read (offline, timeout, missing git).
function parseCheck(text) {
    var result = { checkout: false, branch: "", dirty: false, tags: [], error: false }
    var lines = String(text === undefined || text === null ? "" : text).split("\n")
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (line === "") continue
        var split = line.indexOf("=")
        if (split < 0) continue
        var key = line.slice(0, split)
        var value = line.slice(split + 1)
        if (key === "checkout") result.checkout = value === "yes"
        else if (key === "branch") result.branch = value
        else if (key === "dirty") result.dirty = value === "yes"
        else if (key === "error") result.error = true
        else if (key === "tag") {
            var version = versionFromTag(value)
            if (version !== "") result.tags.push(version)
        }
    }
    return result
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        parseVersion: parseVersion,
        compareVersions: compareVersions,
        versionFromTag: versionFromTag,
        parseTags: parseTags,
        highestVersion: highestVersion,
        updateAvailable: updateAvailable,
        versionFromManifest: versionFromManifest,
        parseCheck: parseCheck
    }
}
