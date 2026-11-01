// Pure composition rules for the manga card (plan Fase 2).
//
// No QML/Quickshell dependency on purpose: "chapter · status" and its
// orphan-separator rules are unit-tested from tests/manga_card.test.js without
// a Wayland session.
//
// `chapter` must be treated as optional. The listings of MangaDex / zonatmo /
// zonatmo.org / ManhwaWeb carry it; the searches of zonatmo.org / WeebCentral /
// InManga do not, and library entries store no work metadata at all. A missing
// half drops its segment AND the separator that would otherwise dangle.

var SEPARATOR = " · ";

// ---------------------------------------------------------------- geometry
//
// One source of truth for the manga card's box. BrowseView's grid and the
// SkeletonGrid that stands in for it while the first page loads both read
// these, so a ghost card and a real card are the same height and the panel
// does not jump when the covers arrive.
//
// COVER_RATIO is Stitch's `aspect-[3/4.4]`: the cover is the card's width
// times 4.4 / 3 tall. INFO_BASE is the content-sized band under it — two
// title lines, the meta row and the p-2 padding — in DESIGN pixels at the
// current font sizes. Callers scale it with Style.space(), exactly like the
// card's own padding, so it follows the theme instead of being a second,
// unscalable number.
var COVER_RATIO = 4.4 / 3;
var INFO_BASE = 66;

// null / undefined / whitespace-only all mean "no value".
function clean(value) {
    if (value === undefined || value === null) return "";
    return String(value).trim();
}

// metaLine("105", "Ongoing", t) -> t("ch|105") + " · Ongoing"
//
// `t` is called once per chapter segment and receives the whole "ch|105"
// string, so the module needs no language table: the caller maps that segment
// to "Ch. 105" / "Cap. 105" (see tSegment below). `status` is expected to be
// display-ready (already through I18n.tData); an unknown status passes through
// unchanged, like every other data value in this app.
function metaLine(chapter, status, t) {
    var parts = [];
    var ch = clean(chapter);
    var st = clean(status);
    if (ch !== "") parts.push(t("ch|" + ch));
    if (st !== "") parts.push(st);
    return parts.join(SEPARATOR);
}

// Adapt an I18n.t-style t(key, params) to metaLine's one-segment translator:
// "ch|105" -> t("ch", { 1: "105" }); anything without a value is a plain key.
function tSegment(t) {
    return function (segment) {
        var raw = String(segment);
        var cut = raw.indexOf("|");
        if (cut < 0) return t(raw);
        return t(raw.slice(0, cut), { 1: raw.slice(cut + 1) });
    };
}

// Exposed for the Node test runner only; QML's import ignores `module`.
// The adapter both views share: decodes metaLine's segment ("ch|105") and words
// it with `t`. Forwarding the raw key here would print "ch|105" on screen — the
// decode is the whole point.
function translator(t) {
    return tSegment(t);
}

// ---------------------------------------------------------------- status tone
//
// The stitch card colours the status on the right of its meta row by state.
// The sources hand over the same state in English ("Ongoing", "Completed") or
// in their own Spanish ("En curso", "Finalizado", "Cancelado"), so the lookup
// normalises both sides before matching. The four answers are the only tone
// names QML knows: `done` (the accent), `live` and `muted` (muted text) and
// `warn` (the theme's urgent colour). An unknown status is `muted`: it must
// still paint, just without a claim.

// Diacritics the Spanish statuses use, lowered before matching. Kept as a
// table instead of String.prototype.normalize() because the QML JS engine is
// not guaranteed to implement it.
var ACCENTS = {
    "á": "a", "à": "a", "ä": "a", "â": "a",
    "é": "e", "è": "e", "ë": "e", "ê": "e",
    "í": "i", "ì": "i", "ï": "i", "î": "i",
    "ó": "o", "ò": "o", "ö": "o", "ô": "o",
    "ú": "u", "ù": "u", "ü": "u", "û": "u",
    "ñ": "n", "ç": "c"
};

// One tone per known status, keyed by the normalised value.
var TONE_BY_STATUS = {
    // Finished.
    "completed": "done",
    "finished": "done",
    "completado": "done",
    "completada": "done",
    "finalizado": "done",
    "finalizada": "done",
    // Still publishing.
    "ongoing": "live",
    "on going": "live",
    "publishing": "live",
    "up to date": "live",
    "en curso": "live",
    "publicandose": "live", // "Publicándose"
    "al dia": "live",       // "Al día"
    // Stopped, one way or another.
    "hiatus": "warn",
    "paused": "warn",
    "pausado": "warn",
    "pausada": "warn",
    "en pausa": "warn",
    "cancelled": "warn",
    "canceled": "warn",
    "cancelado": "warn",
    "cancelada": "warn",
    "dropped": "warn"
};

// Lower-case, strip the accents and collapse the spacing, so "Publicándose "
// and "PUBLICANDOSE" are the same key.
function normalizeStatus(value) {
    var raw = clean(value).toLowerCase();
    var out = "";
    for (var i = 0; i < raw.length; i++) {
        var ch = raw.charAt(i);
        out += ACCENTS[ch] || ch;
    }
    return out.replace(/\s+/g, " ").trim();
}

// statusTone("En curso") -> "live"; statusTone("desconocido") -> "muted".
function statusTone(status) {
    var tone = TONE_BY_STATUS[normalizeStatus(status)];
    // A plain lookup would hand back Object.prototype members for a status
    // like "constructor"; only the four strings above are tones.
    return typeof tone === "string" ? tone : "muted";
}

// The four tone names statusTone can answer with. The views map each one to a
// `Colors.*` role, so a tone added here needs a colour there: keeping the list
// exported lets the probe fail instead of an unknown tone silently painting.
var TONES = ["done", "live", "warn", "muted"];

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        metaLine: metaLine,
        tSegment: tSegment,
        translator: translator,
        statusTone: statusTone,
        COVER_RATIO: COVER_RATIO,
        INFO_BASE: INFO_BASE,
        TONES: TONES
    };
}
