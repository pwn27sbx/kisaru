// Pure helpers for HentaiLA as a normal anime source. Privacy remains the
// existing hidden-entry/private-folder rule shared by every source.

var PREFIX = "hentaila:";
var OFF_VALUES = ["0", "false", "off", "no"];

function isHentaiId(id) {
    return String(id === undefined || id === null ? "" : id).indexOf(PREFIX) === 0;
}

function sourceEnabled(setting, environmentValue) {
    if (setting === false) return false;
    var env = String(environmentValue === undefined || environmentValue === null ? "" : environmentValue)
        .trim().toLowerCase();
    return OFF_VALUES.indexOf(env) < 0;
}

function withoutSource(entries) {
    return (entries || []).filter(function(entry) {
        return !isHentaiId(entry && entry.id);
    });
}

function coverUrl(raw, mangaApiUrl) {
    var value = String(raw === undefined || raw === null ? "" : raw);
    if (value.length === 0) return "";
    return String(mangaApiUrl || "").replace(/\/$/, "") + "/image?url=" + encodeURIComponent(value);
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        PREFIX: PREFIX,
        isHentaiId: isHentaiId,
        sourceEnabled: sourceEnabled,
        withoutSource: withoutSource,
        coverUrl: coverUrl
    };
}
