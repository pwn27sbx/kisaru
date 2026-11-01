// Sizes the list view and its loading skeleton must share.
//
// A row is 80 base units tall and the skeleton stands in for it during load;
// if the two disagree the placeholder rows stop lining up with the real ones.
// Everything the row and its ghost both need lives here, including the type
// scale, so the ghost cannot keep a stale copy of it (A-9 review debt).
//
// Round 7 (A-8) grew the row from 72 to 96; round 8 (A-9) took the sketch's
// proportions (a tall 64 x 90 cover, a heading-size title); round 9 (A-10)
// settled between the two: the owner found A-9 too big, so the cover is
// 48 x 68, the title is one step over the body size and the row is 80.
var ROW_HEIGHT_BASE = 80;

// The thumbnail: 48 x 68, the same 2:3-ish crop the grid's poster takes
// (48/68 = 0.71). At 80 the row leaves 6 above and below.
var THUMB_WIDTH = 48;
var THUMB_HEIGHT = 68;

// The title and the datum, as multiples of the body font size. The row and its
// loading ghost both compute their pixels from these, so raising the title
// raises the ghost's bar too.
var TITLE_SCALE = 1.167;
var DATUM_SCALE = 0.833;

// The breath between the title and the datum, in base units.
var TEXT_GAP_BASE = 3;

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
        TITLE_SCALE: TITLE_SCALE,
        DATUM_SCALE: DATUM_SCALE,
        TEXT_GAP_BASE: TEXT_GAP_BASE,
        PREFETCH_FRACTION: PREFETCH_FRACTION,
        shouldFetchMore: shouldFetchMore
    };
}
