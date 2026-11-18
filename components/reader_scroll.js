// Decisions of the manga long-strip reader, kept pure so Node can test them.
//
// Scroll range. When a page above the viewport changes height, Qt's ListView
// moves the pages above and changes `originY`; `contentY` stays put, so the
// view already holds still. The real range is therefore
// [originY, originY + contentHeight - height]. Clamping to
// [0, contentHeight - height] parked the reader `originY` pixels above its
// end (9/13 jumped to 4/13), and compensating height changes by hand moved the
// view a second time, below every laid-out page (a blank 13/13).
//
// Ratio. The placeholder height ratio is learned from the first page that
// loads in a chapter, once: learning it on every load resized every
// placeholder each time and swung contentHeight and originY by tens of
// thousands of pixels.
//
// Retry. A failed page is retried once by itself after AUTO_RETRY_DELAY_MS,
// then only on click. A proxied page (`/image?url=...`) gets `&kr=<n>`, which
// the proxy ignores and which does not change its cache key, so Qt really
// refetches it instead of reattaching to the failed pixmap. An offline
// `file://` page is never retried by itself and never decorated.
//
// `wheel` is components/wheel_scroll.js, passed in because a QML JavaScript
// import cannot import another file the way Node does.
//
// Imported by modules/manga/components/ReaderView.qml, by
// tests/reader_scroll_unit.test.js and by tests/reader_scroll_harness.

var AUTO_RETRY_DELAY_MS = 3000;

// view: { contentY, contentHeight, height, originY, count } (a ListView works).
// Returns { kind: "ignore" }, { kind: "page", index } (position the view at
// that page) or { kind: "move", y, settling } (set contentY; `settling` means
// the list has no scrollable height yet).
function wheelPlan(wheel, view, angleDeltaY, pixelDeltaY, factor, visiblePage) {
    var step = wheel.stepOf(angleDeltaY, pixelDeltaY);
    var top = Number(view.originY) || 0;
    var range = (Number(view.contentHeight) || 0) - (Number(view.height) || 0);
    // Still laying out (contentHeight not known yet). Swallowing the event
    // made the reader look frozen; move without the upper clamp instead and
    // let the list re-measure.
    if (!(range > 0)) {
        if (!(view.count > 0))
            return { kind: "ignore" };
        return { kind: "move", y: Math.max(top, (Number(view.contentY) || 0) - step * (Number(factor) || 1)), settling: true };
    }
    var limit = top + range;
    var target = wheel.nextContentY(view.contentY, angleDeltaY, pixelDeltaY, factor, limit, top);
    // contentHeight is an ESTIMATE while pages are recycled and can fall short
    // of the real end: the pixel clamp then parks the reader on a fake bottom.
    // When that happens and pages remain, move by page instead; this uses the
    // laid-out items, not the estimate.
    if (target >= limit && step < 0 && visiblePage < view.count - 1)
        return { kind: "page", index: visiblePage + 1 };
    return { kind: "move", y: target, settling: false };
}

// The page under the viewport. indexAt answers -1 in an area the list has not
// laid out; keep the last answer then, clamped to the current chapter.
function pageAt(index, lastPage, count) {
    if (index >= 0)
        return index;
    return Math.max(0, Math.min(lastPage, count - 1));
}

function shouldLearnRatio(alreadyLearned, value) {
    return !alreadyLearned && value > 0.1 && value < 50;
}

function isProxied(url) {
    return typeof url === "string" && url.indexOf("/image?") >= 0;
}

function pageSource(url, attempt) {
    if (!url)
        return "";
    var n = Number(attempt) || 0;
    if (n > 0 && isProxied(url))
        return url + "&kr=" + n;
    return url;
}

function canAutoRetry(url, attempt) {
    return isProxied(url) && !(Number(attempt) > 0);
}

function attemptOf(attempts, index) {
    return (attempts && Number(attempts[index])) || 0;
}

// A new map, so a QML `property var` notices the change.
function bumpAttempt(attempts, index) {
    var out = {};
    for (var key in attempts)
        out[key] = attempts[key];
    out[index] = attemptOf(attempts, index) + 1;
    return out;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        AUTO_RETRY_DELAY_MS: AUTO_RETRY_DELAY_MS,
        wheelPlan: wheelPlan,
        pageAt: pageAt,
        shouldLearnRatio: shouldLearnRatio,
        pageSource: pageSource,
        canAutoRetry: canAutoRetry,
        attemptOf: attemptOf,
        bumpAttempt: bumpAttempt,
    };
}
