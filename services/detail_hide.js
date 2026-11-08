// What a title's Detail does when the hide switch is pressed, and what its
// folder list may show.
//
// Owner (2026-11-05): pressing Ocultar inside a manhwa must not throw him out
// of the Detail — he hides the title there and then files it into a hidden
// folder. So the unlocked press only marks the title hidden and stays; the lock
// lands when the Detail is left, which is when the title must leave the
// Library. While locked the switch keeps its old job: hide and go back.
//
// Pure, so the three panels read one rule instead of three copies, and a node
// test can pin every branch without a screen.

// The actions travel as constants, never as bare strings: the QML compares
// against them, so a new branch cannot fall silently into another one.
var ACTION = {
    IGNORE: "ignore",
    HIDE_LEAVE: "hide-leave",
    LEAVE: "leave",
    HIDE_STAY: "hide-stay",
    UNHIDE_STAY: "unhide-stay"
};

// state: { configured, locked, hidden, folderHidden }
function toggle(state) {
    var s = state || {};
    if (s.configured !== true) return ACTION.IGNORE;
    // A title its folder already hides has nothing to press: the switch is
    // locked on. Filing it elsewhere is the folder picker's job.
    if (s.folderHidden === true) return ACTION.IGNORE;
    if (s.locked === true)
        return s.hidden === true ? ACTION.LEAVE : ACTION.HIDE_LEAVE;
    return s.hidden === true ? ACTION.UNHIDE_STAY : ACTION.HIDE_STAY;
}

// What the switch shows.
//
// Owner (2026-11-08): a title filed into a hidden folder read as "not hidden",
// because the switch only looked at the title's own flag. The folder is what
// hides it, so the switch shows on and locked and the note names the folder.
// A title hidden by its own flag keeps today's rule: it reads as on while the
// word is unlocked and as off once the word locks it away.
//
// state: { locked, hidden, folderHidden, folderName }
function switchView(state) {
    var s = state || {};
    if (s.folderHidden === true)
        return { checked: true, noteFolder: s.folderName || "" };
    return {
        checked: s.locked !== true && s.hidden === true,
        noteFolder: ""
    };
}

// The folder list: a title that is not hidden keeps the current rule (hidden
// folders disappear while locked). A title that is ALREADY hidden may be filed
// into one of them at once, with no word — that is the whole point of hiding
// from the Detail.
//
// state: { locked, hidden }
function pickerShowsHidden(state) {
    var s = state || {};
    return s.locked !== true || s.hidden === true;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        ACTION: ACTION,
        toggle: toggle,
        switchView: switchView,
        pickerShowsHidden: pickerShowsHidden
    };
}
