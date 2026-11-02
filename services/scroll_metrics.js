// The scrollbar's own lane, shared by the bar and by every view that has to
// leave room for it (owner, §30 of the components plan).
//
// The bar used to ride on top of the cards: the last column's title ran under
// it. A view that shows a StyledScrollBar now keeps `LANE` pixels of gutter on
// its right, so the bar never covers a card, a row or a paragraph.
var LANE = 8;

// How thick the handle is, in pixels. It was 3; option (b) asks for thinner.
var THICKNESS = 2;

// How long the bar stays visible after the last scroll or hover, in ms.
var IDLE_MS = 1000;

// The fade itself. Reduced motion turns this off (see services/motion_prefs.js).
var FADE_MS = 140;

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        LANE: LANE,
        THICKNESS: THICKNESS,
        IDLE_MS: IDLE_MS,
        FADE_MS: FADE_MS
    };
}
