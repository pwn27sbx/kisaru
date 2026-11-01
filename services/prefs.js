// Pure helpers for <config>/qs-novelmangareader/settings.json.
//
// The file holds the user's preferences and is shared by the language toggle
// and the readers:
//
//   {
//     "language": "es",       // UI language (WU-11)
//     "scrollFactor": 2,      // reader wheel speed, 0.5..5
//     "viewMode": "grid",     // legacy: manga's layout before per-panel keys
//     "viewMode.manga": "grid", "viewMode.anime": "grid", "viewMode.novel": "grid"
//     "animeMode": "sub"      // anime audio: "sub" | "dub" (owner, round 6)
//   }
//
// Every writer must preserve the keys it does not own: the language toggle
// used to serialise `{language}` alone, which would drop a scrollFactor the
// user had set. `withLanguage()` merges into whatever is already there.

var DEFAULT_SCROLL_FACTOR = 2;
// 0.5 is half the fastest "slow" a reader wants on a long strip; 5 already
// moves ~1.3 notches per page, so 10 was a jump bigger than a page.
var MIN_SCROLL_FACTOR = 0.5;
var MAX_SCROLL_FACTOR = 5;

// The manga Browse/Library layout. Grid is what every user had before the
// toggle existed, so it is the default when the key is missing or unreadable.
var DEFAULT_VIEW_MODE = "grid";
var VIEW_MODES = ["grid", "list"];

// The anime panel's audio mode. It used to be a local property that started at
// "sub" on every launch, so a DUB choice was lost on restart (owner, round 6).
var DEFAULT_ANIME_MODE = "sub";
var ANIME_MODES = ["sub", "dub"];

function parseSettings(text) {
    try {
        var data = JSON.parse(String(text || ""));
        return (data && typeof data === "object" && !Array.isArray(data)) ? data : {};
    } catch (e) {
        return {};
    }
}

// A usable wheel multiplier: numbers and numeric strings accepted, clamped and
// rounded to one decimal (a slider with step 0.1 accumulates 1.2000000001).
function normalizeScrollFactor(value) {
    var number = Number(value);
    if (!isFinite(number) || number <= 0)
        return DEFAULT_SCROLL_FACTOR;
    var clamped = Math.min(MAX_SCROLL_FACTOR, Math.max(MIN_SCROLL_FACTOR, number));
    return Math.round(clamped * 10) / 10;
}

// The single place the UI language is coerced: anything Spanish-ish ("es",
// "es-419", "ES") becomes "es"; everything else becomes "en".
function normalizeLanguage(value) {
    return String(value || "").trim().toLowerCase().indexOf("es") === 0 ? "es" : "en";
}

// "grid" | "list", and nothing else: a hand-edited settings.json, an older
// file without the key, or an object where a string belongs all fall back to
// the default instead of leaving the views with a layout they cannot build.
// The layouts live per panel now (owner, round 6): each one remembers its own
// grid/list choice. The old single key is read as manga's value, so an upgrade
// keeps the layout the user already had instead of resetting it.
var VIEW_MODE_PANELS = ["manga", "anime", "novel"];

function viewModeKey(panel) {
    return "viewMode." + String(panel || "manga");
}

function viewModeFor(data, panel) {
    var settings = (data && typeof data === "object") ? data : {};
    var own = settings[viewModeKey(panel)];
    if (own !== undefined && own !== null && own !== "")
        return normalizeViewMode(own);
    // Only manga inherits the legacy key: the other two never had one.
    if (panel === "manga")
        return normalizeViewMode(settings.viewMode);
    return DEFAULT_VIEW_MODE;
}

function normalizeViewMode(value) {
    var mode = String(value === undefined || value === null ? "" : value).trim().toLowerCase();
    return VIEW_MODES.indexOf(mode) >= 0 ? mode : DEFAULT_VIEW_MODE;
}

// "sub" | "dub" and nothing else: a hand-edited file or a missing key falls
// back to the default instead of leaving the panel asking for an unknown mode.
function normalizeAnimeMode(value) {
    var mode = String(value === undefined || value === null ? "" : value).trim().toLowerCase();
    return ANIME_MODES.indexOf(mode) >= 0 ? mode : DEFAULT_ANIME_MODE;
}

// The rows the anime settings page draws, built from the same table the
// normalizer validates: a mode added in one place cannot go missing in the
// other. The labels are key caps, not UI copy, so they do not go through i18n.
var ANIME_MODE_OPTIONS = ANIME_MODES.map(function (id) {
    return { id: id, label: id.toUpperCase() };
});

// Same document with ONE key set and everything else left alone. This is the
// only writer shape the app uses: the language row and the scroll slider each
// own their key, and neither may drop the other's.
function withSetting(text, key, value) {
    var data = parseSettings(text);
    data[String(key)] = value;
    return JSON.stringify(data, null, 2) + "\n";
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        DEFAULT_SCROLL_FACTOR: DEFAULT_SCROLL_FACTOR,
        MIN_SCROLL_FACTOR: MIN_SCROLL_FACTOR,
        MAX_SCROLL_FACTOR: MAX_SCROLL_FACTOR,
        parseSettings: parseSettings,
        normalizeScrollFactor: normalizeScrollFactor,
        withSetting: withSetting,
        normalizeLanguage: normalizeLanguage,
        DEFAULT_VIEW_MODE: DEFAULT_VIEW_MODE,
        normalizeViewMode: normalizeViewMode,
        VIEW_MODE_PANELS: VIEW_MODE_PANELS,
        viewModeKey: viewModeKey,
        viewModeFor: viewModeFor,
        DEFAULT_ANIME_MODE: DEFAULT_ANIME_MODE,
        ANIME_MODE_OPTIONS: ANIME_MODE_OPTIONS,
        normalizeAnimeMode: normalizeAnimeMode
    };
}
