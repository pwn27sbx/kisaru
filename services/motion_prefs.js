// Reads the desktop's "reduce motion" preference.
//
// The app has no motion setting of its own and should not gain one: the honest
// source is the desktop's switch. GTK writes `gtk-enable-animations` into its
// settings.ini, which is where Omarchy's themes and the GTK apps agree on it.
// `KISARU_REDUCED_MOTION=1` is the explicit override for anyone whose desktop
// never writes that file, and it wins.
function reducedFromGtk(text) {
    if (!text) return false;
    var lines = String(text).split(/\r?\n/);
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (line.indexOf("gtk-enable-animations") !== 0) continue;
        var value = line.split("=").slice(1).join("=").trim().toLowerCase();
        if (value === "false" || value === "0" || value === "no") return true;
    }
    return false;
}

// The env var is an explicit yes; anything else defers to the desktop.
function reduced(envValue, gtkText) {
    if (String(envValue || "").trim() === "1") return true;
    return reducedFromGtk(gtkText);
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        reducedFromGtk: reducedFromGtk,
        reduced: reduced
    };
}
