// Sizes the list view and its loading skeleton must share.
//
// A row is 106 base units tall and the skeleton stands in for it during load;
// if the two disagree the placeholder rows stop lining up with the real ones.
// The number lives here once so both views and the row read the same value.
//
// Round 7 (A-8) grew the row from 72 to 96 for a bigger thumbnail and a
// two-line title. Round 8 (A-9) took the sketch's proportions: a tall 64 x 90
// cover that nearly spans the row, a large bold title and a small muted datum
// under it. Both thumbnail sides are declared, so nothing divides by a "ratio"
// that could be read either way; the prefetch threshold is a fraction of the
// viewport and does not need retuning with the row size.
var ROW_HEIGHT_BASE = 106;

// The thumbnail: 64 x 90, a real 2:3-ish cover (64/90 = 0.71, the same crop the
// grid's poster takes). At 106 the row leaves 8 above and below.
var THUMB_WIDTH = 64;
var THUMB_HEIGHT = 90;

// How close to the end a list may scroll before it asks for the next page,
// as a fraction of the viewport. One number, shared by every list, so tuning
// the prefetch distance is not four edits that can drift apart.
var PREFETCH_FRACTION = 0.5;

// True when the list is close enough to the end to fetch more.
function shouldFetchMore(contentY, height, contentHeight) {
    return contentY + height > contentHeight - height * PREFETCH_FRACTION;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        ROW_HEIGHT_BASE: ROW_HEIGHT_BASE,
        THUMB_WIDTH: THUMB_WIDTH,
        THUMB_HEIGHT: THUMB_HEIGHT,
        PREFETCH_FRACTION: PREFETCH_FRACTION,
        shouldFetchMore: shouldFetchMore
    };
}
