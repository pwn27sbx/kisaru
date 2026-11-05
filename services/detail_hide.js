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

// state: { configured, locked, hidden }
function toggle(state) {
    var s = state || {};
    if (s.configured !== true) return ACTION.IGNORE;
    if (s.locked === true)
        return s.hidden === true ? ACTION.LEAVE : ACTION.HIDE_LEAVE;
    return s.hidden === true ? ACTION.UNHIDE_STAY : ACTION.HIDE_STAY;
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
        pickerShowsHidden: pickerShowsHidden
    };
}
