// WCAG contrast helpers for the card text tokens. Hex in, ratio out; the same
// mix the QML palette uses (a plain sRGB channel blend), so a test can pin the
// token against the theme without a Wayland session.
function channel(value) {
    var c = parseInt(value, 16) / 255;
    return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}

function luminance(hex) {
    var text = String(hex).replace("#", "");
    var r = channel(text.slice(0, 2));
    var g = channel(text.slice(2, 4));
    var b = channel(text.slice(4, 6));
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function ratio(a, b) {
    var la = luminance(a);
    var lb = luminance(b);
    var hi = Math.max(la, lb);
    var lo = Math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
}

function mix(a, b, t) {
    var left = String(a).replace("#", "");
    var right = String(b).replace("#", "");
    var out = "";
    for (var i = 0; i < 6; i += 2) {
        var value = Math.round(parseInt(left.slice(i, i + 2), 16)
            + (parseInt(right.slice(i, i + 2), 16) - parseInt(left.slice(i, i + 2), 16)) * t);
        out += (value < 16 ? "0" : "") + value.toString(16);
    }
    return "#" + out;
}

// The formula behind Colors.card_secondary.
function cardSecondary(muted, onSurface) {
    return mix(muted, onSurface, 0.9);
}

function normalizeHex(value) {
    if (value === null || value === undefined) return null;
    var text = String(value).trim().replace(/^#/, "");
    if (/^[0-9a-fA-F]{6}$/.test(text)) return "#" + text.toLowerCase();
    if (/^[0-9a-fA-F]{8}$/.test(text)) return "#" + text.slice(2).toLowerCase();
    return null;
}

// Nearest mix of `color` toward `onSurface` that reaches `minRatio` (default
// 4.5:1) against `bg`, keeping the theme's hue. Returns `color` unchanged when
// it already passes or when an input has not loaded yet.
function statusText(color, bg, onSurface, minRatio) {
    var targetRatio = minRatio || 4.5;
    var cHex = normalizeHex(color);
    var bgHex = normalizeHex(bg);
    if (!cHex || !bgHex) return color;
    if (ratio(cHex, bgHex) >= targetRatio) return color;

    var tHex = normalizeHex(onSurface);
    if (!tHex) tHex = luminance(bgHex) < 0.5 ? "#ffffff" : "#000000";
    if (ratio(tHex, bgHex) < targetRatio) {
        var extreme = luminance(bgHex) < 0.5 ? "#ffffff" : "#000000";
        tHex = ratio(extreme, bgHex) > ratio(tHex, bgHex) ? extreme : tHex;
    }

    var lo = 0;
    var hi = 1;
    for (var i = 0; i < 14; i++) {
        var mid = (lo + hi) / 2;
        if (ratio(mix(cHex, tHex, mid), bgHex) >= targetRatio) hi = mid;
        else lo = mid;
    }
    return mix(cHex, tHex, hi);
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        luminance: luminance,
        ratio: ratio,
        mix: mix,
        cardSecondary: cardSecondary,
        statusText: statusText
    };
}
