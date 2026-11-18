// Wheel arithmetic for the readers, kept pure so Node can test it.
//
// A wheel event carries `angleDelta` (eighths of a degree, 120 per notch on a
// mouse) OR only `pixelDelta` (a touchpad). Both mean "scroll this way", so the
// step keeps the SAME sign — a handler that negates pixelDelta scrolls the
// wrong way on a touchpad. The factor multiplies the step; the result is
// clamped to [minY, limit] so the reader never runs past its own ends.
//
// `minY` defaults to 0, which is the novel reader's Flickable. The manga long
// strip passes its ListView `originY`: when a page above the viewport changes
// height, Qt moves originY (it can go negative) and keeps contentY still, so
// its real range is [originY, originY + contentHeight - height]. A limit that
// is missing or below minY collapses onto minY.
//
// Imported by modules/*/components/ReaderView.qml, components/reader_scroll.js
// (passed in by its caller) and tests/wheel_scroll.test.js.

function stepOf(angleDeltaY, pixelDeltaY) {
    var angle = Number(angleDeltaY) || 0;
    if (angle !== 0)
        return angle;
    return Number(pixelDeltaY) || 0;
}

function nextContentY(currentY, angleDeltaY, pixelDeltaY, factor, limit, minY) {
    var step = stepOf(angleDeltaY, pixelDeltaY) * (Number(factor) || 1);
    var target = (Number(currentY) || 0) - step;
    var min = Number(minY) || 0;
    var max = Number(limit);
    if (!isFinite(max) || max < min)
        max = min;
    return Math.max(min, Math.min(max, target));
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { stepOf: stepOf, nextContentY: nextContentY };
}
