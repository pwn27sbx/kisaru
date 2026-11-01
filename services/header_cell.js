// Which paint a header cell asks for (owner, rounds 5-7).
//
// Every cell of the header row must look like the active filter chip: a solid
// accent block with the label in the on-accent colour. That is a small state
// machine (pressed beats hover, hover beats selected) and it lived as nested
// ternaries in the delegate, where no test could see it.
//
// This module answers WHICH paint applies — a fill role, a label role and a
// weight role. It does not choose colours: the delegate maps each answer to its
// Style call (pressedFillFor, hoverFillFor, Colors.primary), which is where a
// theme change still lands.
//
// Round 6 (shared components) removed the `fullHeight` parameter: the header is
// one strip of full-height cells in all three panels, so the boxed/anime
// variants this used to switch no longer exist.
//
// Round 7 (A-8) made the selected label DARK and BOLD everywhere. The kit's
// Button derives its selected label from the theme's `selected-color`, which in
// this theme is the light accent itself, so a `selected: true` Button painted a
// light label on the orange fill; the header cells never used Button and were
// dark, which is the reading the owner asked to have everywhere.

var FILL = { NONE: "none", HOVER: "hover", PRESSED: "pressed", SOLID: "solid" };
var LABEL = { MUTED: "muted", ON: "on" };

// state: { current, hovered, pressed }
function cellStyle(state) {
    state = state || {};
    var selected = !!state.current;
    return {
        // Selected is a SOLID accent fill with the on-accent label, the Stow
        // Sync look the owner picked (round 6): the tint-and-ring reading is
        // gone, and hover keeps its own tint.
        fill: selected
            ? (state.pressed ? FILL.PRESSED : FILL.SOLID)
            : (state.pressed ? FILL.PRESSED
                : state.hovered ? FILL.HOVER
                : FILL.NONE),
        label: selected ? LABEL.ON : LABEL.MUTED,
        // The selected label is bold, so "current" reads at a glance and not
        // only by fill (owner, A-8).
        strong: selected
    };
}

// A tab badge exists only when there is something to count: "Library" alone
// beats "Library 0" (owner, A-8).
function showBadge(count) {
    var n = Number(count);
    return isFinite(n) && n > 0;
}

if (typeof module !== "undefined" && module.exports)
    module.exports = {
        FILL: FILL,
        LABEL: LABEL,
        cellStyle: cellStyle,
        showBadge: showBadge
    };
