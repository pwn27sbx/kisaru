// The count segment of the status bar (owner, round 4).
//
// It used to be a whole row above the grid ("Results · 32 loaded"), with the
// Library showing its own number in its heading. Both moved here, into
// "● Online · 32 loaded", so the top zone keeps one control row.
//
// Pure rules, no QML: tests/status_line.test.js pins them without a Wayland
// session. The wording stays where the i18n tables live — this module only
// decides WHICH count the bar shows and how it is composed.

// "Nothing to say": no count, so the bar hides the separator too.
var NONE = -1;

// Which count belongs in the bar, or NONE.
//
//   - the settings page is not a list, so it shows nothing, even though the
//     tabs stay on screen behind it;
//   - Browse reports the LOADED count: the backend contract exposes `hasMore`,
//     never a catalogue total, so a total would be an invented number;
//   - Library reports its exact size, which is a real number.
function visibleCount(state) {
    state = state || {};
    if (state.settingsMode) return NONE;

    var value = state.tabIndex === 1 ? state.libraryCount : state.browseCount;
    var n = Number(value);
    // Not loaded yet (undefined/NaN) or a negative placeholder: nothing.
    if (!isFinite(n) || n < 0) return NONE;
    return Math.floor(n);
}

// The text for that segment, or "" when there is none.
//
// Browse uses the wording it already had ("32 loaded" / "32 cargados"), so the
// move does not introduce a second way to say the same thing. Library names
// what the number is ("1 in library" / "1 en la biblioteca"): a bare "0" next
// to the online dot said nothing about what was being counted (owner, round 6).
// `translate` is I18n.tn.
function format(count, tabIndex, translate) {
    if (count === NONE || count === null || count === undefined) return "";
    if (typeof translate !== "function") return String(count);
    return String(translate(tabIndex === 1 ? "status.inLibrary" : "header.loaded", count));
}

// The QML engine has no CommonJS `module`, so the same guard the other
// services use keeps this file importable from both sides.
// The whole bar segment for one panel: which count, and how it reads. The three
// panels call this and pass their own numbers, so the expression and the key
// names live in one place instead of being copied per panel.
function barText(state) {
    state = state || {};
    var text = format(visibleCount(state), state.tabIndex, state.translate);
    // Library also names the folder on screen; Browse has no folders.
    var folder = state.tabIndex === 1 && state.folderName ? String(state.folderName) : "";
    if (folder === "") return text;
    return text === "" ? folder : text + " · " + folder;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        NONE: NONE,
        visibleCount: visibleCount,
        format: format,
        barText: barText
    };
}
