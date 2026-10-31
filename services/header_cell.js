// Which paint a full-height header cell asks for (owner, round 5).
//
// The selected Browse / Library cell must look like the active filter chip:
// accent tint, 1 px accent ring, resolved state colour on the label. That is a
// small state machine (pressed beats hover, hover beats selected, the ring
// belongs to the selected full-height cell) and it lived as nested ternaries in
// the delegate, where no test could see it. Pure, so it can be pinned; the
// delegate only maps each answer to its Style call.

var FILL = { NONE: "none", SELECTED: "selected", HOVER: "hover", PRESSED: "pressed" };
var LABEL = { MUTED: "muted", TEXT: "text", SELECTED: "selected" };

function cellStyle(state) {
    state = state || {};
    return {
        fill: state.pressed ? FILL.PRESSED
            : state.hovered ? FILL.HOVER
            : state.current ? FILL.SELECTED
            : FILL.NONE,
        label: !state.current ? LABEL.MUTED
            : state.fullHeight ? LABEL.SELECTED
            : LABEL.TEXT,
        ring: !!state.fullHeight && !!state.current,
        hoverRing: !!state.hovered && !state.fullHeight
    };
}

if (typeof module !== "undefined" && module.exports)
    module.exports = { FILL: FILL, LABEL: LABEL, cellStyle: cellStyle };
