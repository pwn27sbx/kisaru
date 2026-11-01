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

var FILL = { NONE: "none", HOVER: "hover", PRESSED: "pressed", SOLID: "solid" };
var LABEL = { MUTED: "muted", ON: "on" };

// state: { current, hovered, pressed }
function cellStyle(state) {
    state = state || {};
    return {
        // Selected is a SOLID accent fill with the on-accent label, the Stow
        // Sync look the owner picked (round 6): the tint-and-ring reading is
        // gone, and hover keeps its own tint.
        fill: state.current
            ? (state.pressed ? FILL.PRESSED : FILL.SOLID)
            : (state.pressed ? FILL.PRESSED
                : state.hovered ? FILL.HOVER
                : FILL.NONE),
        label: state.current ? LABEL.ON : LABEL.MUTED
    };
}

if (typeof module !== "undefined" && module.exports)
    module.exports = { FILL: FILL, LABEL: LABEL, cellStyle: cellStyle };
