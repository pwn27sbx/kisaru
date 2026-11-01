// Which paint a header cell asks for (owner, rounds 5-6).
//
// Every cell of the header row must look like the active filter chip: accent
// tint when selected, cancelled by hover/press, accent ring only on the
// selected cell. That is a small state machine (pressed beats hover, hover
// beats selected) and it lived as nested ternaries in the delegate, where no
// test could see it.
//
// This module answers WHICH paint applies — a fill role, a label role and a
// visibility flag. It does not choose colours or widths: the delegate maps each
// answer to its Style call (selectedFillFor, selectedStateColor,
// Style.normalBorderWidth in Colors.primary), which is where a theme change
// still lands.
//
// Round 6 (shared components) removed the `fullHeight` parameter: the header is
// one strip of full-height cells in all three panels, so the boxed/anime
// variants this used to switch no longer exist.

var FILL = { NONE: "none", SELECTED: "selected", HOVER: "hover", PRESSED: "pressed" };
var LABEL = { MUTED: "muted", SELECTED: "selected" };

// state: { current, hovered, pressed }
function cellStyle(state) {
    state = state || {};
    return {
        fill: state.pressed ? FILL.PRESSED
            : state.hovered ? FILL.HOVER
            : state.current ? FILL.SELECTED
            : FILL.NONE,
        label: state.current ? LABEL.SELECTED : LABEL.MUTED,
        // The ring belongs to being selected, not to being hovered.
        showRing: !!state.current
    };
}

if (typeof module !== "undefined" && module.exports)
    module.exports = { FILL: FILL, LABEL: LABEL, cellStyle: cellStyle };
