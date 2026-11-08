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
// live panel can hold (`fits`), so the chapter is never clipped on both sides.
// Narrowing applies at once, before anything moves. Widening waits until the
// panel has FINISHED its animation (`liveWidth` reached `targetWidth`), so the
// one reflow lands on a still frame instead of on the first animated frame
// (owner, 2026-11-08: a mini hitch when the novel reader opens). A caller that
// passes no target width keeps the old behaviour: widen as soon as it fits.
// A panel constrained below the compact target (a small screen) still gets the
// largest measure that fits: the initial 0 is not a measure, it is "nothing
// measured yet".
function shownMeasure(current, wanted, liveWidth, targetWidth) {
    var fits = columnWidth(liveWidth);
    // Nothing measured yet: take the target, or what a small panel can hold.
    if (current <= 0) return Math.min(wanted, fits);
    // The live panel shrank under the shown measure: take what still fits.
    if (current > fits) return fits;
    // Narrowing (and an unchanged measure) applies at once, before anything
    // moves. Widening needs the panel animation to be over.
    if (wanted <= current) return wanted;
    var target = Number(targetWidth);
    if (!isFinite(target)) return wanted <= fits ? wanted : current;
    if (liveWidth < target - 0.5) return current;
    return wanted <= fits ? wanted : fits;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        MAX_MEASURE: MAX_MEASURE,
        SIDE_GUTTER: SIDE_GUTTER,
        columnWidth: columnWidth,
        shownMeasure: shownMeasure
    };
}
