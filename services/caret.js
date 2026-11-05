// Where the search caret's visible bar stands.
//
// TextInput writes the cursorDelegate's x from the cursor rectangle, so the
// delegate is a zero-width anchor and the bar is its child. At position 0 the
// bar takes the reserved room to the LEFT of the first character; at any other
// position that same offset would land it on the previous letter, so it stays
// at the cursor instead.
function barX(cursorPosition, barWidth, gap) {
    var position = Number(cursorPosition);
    var width = Number(barWidth);
    var air = Number(gap);
    if (!isFinite(position) || position <= 0) {
        return -(isFinite(width) ? width : 0) - (isFinite(air) ? air : 0);
    }
    return 0;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { barX: barX };
}
