// The novel reader's measure, and why it must not follow the panel animation.
//
// The panel animates its implicitWidth between 550 (compact) and the screen
// width (fullscreen). The chapter used to take its measure from that animated
// width, so the whole chapter reflowed on every frame of the animation as soon
// as the panel dropped below 768 px — the owner's "lag al final" (2026-11-08).
// The measure now comes from the panel's target width, so the chapter reflows
// once per toggle; this file is the one place that decides the number.
var MAX_MEASURE = 720;
// 24 px between the text and each edge, so the measure never touches the panel.
var SIDE_GUTTER = 48;

// The column width for the panel width the reader is heading to. Never
// negative: a panel narrower than the gutters has no room for text.
function columnWidth(availableWidth) {
    var width = Number(availableWidth);
    if (!isFinite(width)) return 0;
    return Math.max(0, Math.min(width - SIDE_GUTTER, MAX_MEASURE));
}

// Which measure the reader may show right now.
//
// The target measure is known the moment the mode toggles, but the panel is
// still animating towards its new width. The reader never shows more than the
// live panel can hold (`fits`), so the chapter is never clipped on both sides;
// narrowing applies at once, and widening waits until the panel is wide enough
// — still a single reflow, a few frames later. A panel constrained below the
// compact target (a small screen) still gets the largest measure that fits:
// the initial 0 is not a measure, it is "nothing measured yet".
function shownMeasure(current, wanted, liveWidth) {
    var fits = columnWidth(liveWidth);
    if (current <= 0) return Math.min(wanted, fits);
    if (wanted <= fits) return wanted;
    if (current > fits) return fits;
    return current;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        MAX_MEASURE: MAX_MEASURE,
        SIDE_GUTTER: SIDE_GUTTER,
        columnWidth: columnWidth,
        shownMeasure: shownMeasure
    };
}
