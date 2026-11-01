// Sizes the list view and its loading skeleton must share.
//
// A row is 72 base units tall and the skeleton stands in for it during load;
// if the two disagree the placeholder rows stop lining up with the real ones.
// The number lives here once so both views and the row read the same value.
var ROW_HEIGHT_BASE = 72;

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
        PREFETCH_FRACTION: PREFETCH_FRACTION,
        shouldFetchMore: shouldFetchMore
    };
}
