// Sizes the list view and its loading skeleton must share.
//
// A row is 96 base units tall and the skeleton stands in for it during load;
// if the two disagree the placeholder rows stop lining up with the real ones.
// The number lives here once so both views and the row read the same value.
//
// Round 7 (A-8) grew the row from 72: the owner asked for bigger thumbnails, a
// two-line title and a normal-size meta line, and none of that fits in 72. The
// cover width and the row height are declared together so the thumbnail cannot
// end up taller than its row, and the prefetch threshold is expressed as a
// fraction of the viewport, so it does not need retuning with the row size.
var ROW_HEIGHT_BASE = 96;

// The thumbnail: 56 px wide, 2:3 like the grid's poster (so a cover crops the
// same way in both views). At 96 base units the row leaves ~8 above and below.
var THUMB_WIDTH = 56;
var THUMB_RATIO = 0.7;

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
        THUMB_RATIO: THUMB_RATIO,
        PREFETCH_FRACTION: PREFETCH_FRACTION,
        shouldFetchMore: shouldFetchMore
    };
}
