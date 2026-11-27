// Pure rules for the private anime section. UI isolation matches manga's
// private mode: the prefix is hidden while Privacy.locked, covers use the
// existing manga image proxy, and the feature defaults on.

var PREFIX = "hentaila:";
var OFF_VALUES = ["0", "false", "off", "no"];

function isPrivateId(id) {
    return String(id === undefined || id === null ? "" : id).indexOf(PREFIX) === 0;
}

function sourceEnabled(setting, environmentValue) {
    if (setting === false) return false;
    var env = String(environmentValue === undefined || environmentValue === null ? "" : environmentValue)
        .trim().toLowerCase();
    return OFF_VALUES.indexOf(env) < 0;
}

function visibleLibrary(entries, locked) {
    var list = entries || [];
    if (locked !== true) return list.slice();
    return list.filter(function(entry) {
        return !isPrivateId(entry && entry.id);
    });
}

function coverUrl(raw, mangaApiUrl) {
    var value = String(raw === undefined || raw === null ? "" : raw);
    if (value.length === 0) return "";
    return String(mangaApiUrl || "").replace(/\/$/, "") + "/image?url=" + encodeURIComponent(value);
}

function searchUrl(apiUrl, query, page) {
    return String(apiUrl || "").replace(/\/$/, "") + "/hentaila/search?q="
        + encodeURIComponent(query) + "&page=" + encodeURIComponent(page || 1);
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        PREFIX: PREFIX,
        isPrivateId: isPrivateId,
        sourceEnabled: sourceEnabled,
        visibleLibrary: visibleLibrary,
        coverUrl: coverUrl,
        searchUrl: searchUrl
    };
}
