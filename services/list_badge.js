// Geometry the list badges (the "Ch. 262" pill) must agree on.
//
// The same pill stands in front of the rows of the three Detail lists (manga
// chapters, anime episodes, novel chapters). Its width used to follow its own
// text, so a wider number ("Ch. 262.2") pushed that row's title to a different
// x (owner, 2026-11-27). The column is now as wide as the widest badge of the
// list and every row uses it, so all titles start on one line.
//
// One module, because the measurement (components/BadgeColumn.qml) and the pill
// it sizes (components/ListBadge.qml) must never disagree on these numbers, and
// because the row separator and the row content have to share one inset.
var HEIGHT = 26;
var PADDING_X = 16;
var FONT_PIXEL_SIZE = 9;
var LETTER_SPACING = 0.5;

// The row's own content inset, both sides. The badge column starts here and the
// row separator runs from this left edge to the content's right edge: the fill
// spans the row box, the badge column and the separator share the content's
// edges (owner decision, 2026-11-27).
var ROW_INSET = 16;

// Width a badge column needs for `naturalWidths`, the implicit width of each
// badge's text. The sum is rounded up, so a fractional text advance can never
// leave the pill a fraction narrower than its own label.
function columnWidth(naturalWidths, paddingX) {
    var padding = paddingX === undefined ? PADDING_X : paddingX;
    var widest = 0;
    var list = Array.isArray(naturalWidths) ? naturalWidths : [];
    for (var i = 0; i < list.length; i++) {
        var width = Number(list[i]);
        if (isFinite(width) && width > widest) widest = width;
    }
    if (widest <= 0) return 0;
    return Math.ceil(widest + padding);
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        HEIGHT: HEIGHT,
        PADDING_X: PADDING_X,
        FONT_PIXEL_SIZE: FONT_PIXEL_SIZE,
        LETTER_SPACING: LETTER_SPACING,
        ROW_INSET: ROW_INSET,
        columnWidth: columnWidth
    };
}
