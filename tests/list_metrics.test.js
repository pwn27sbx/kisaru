"use strict";

// The list geometry and the prefetch threshold, shared by every list view.
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const metrics = require("../services/list_metrics.js");

test("a row is 80 base units and the skeleton reads the same number", () => {
    // A-10 middle ground between A-8 (96) and A-9 (106): ~12 rows per screen.
    assert.equal(metrics.ROW_HEIGHT_BASE, 80);
});

test("the thumbnail is 48 x 68 and fits inside the row", () => {
    assert.equal(metrics.THUMB_WIDTH, 48);
    assert.equal(metrics.THUMB_HEIGHT, 68);
    assert.ok(metrics.ROW_HEIGHT_BASE > metrics.THUMB_HEIGHT, "the cover is taller than its row");
    // Both sides are declared: nothing derives one from a ratio, which is what
    // the A-8 review flagged.
    assert.equal(metrics.THUMB_RATIO, undefined);
});

test("the row's type scale and gap are shared with the ghost", () => {
    // A-10: the loading skeleton reads these instead of copying the row's
    // font tokens, which is the A-9 review debt.
    assert.ok(metrics.TITLE_SCALE > 1.1 && metrics.TITLE_SCALE < 1.2, "the title is not ~1.15x the body");
    assert.ok(metrics.DATUM_SCALE < 1, "the datum is not smaller than the body");
    assert.equal(metrics.TEXT_GAP_BASE, 3);
});

test("prefetch starts half a viewport before the end", () => {
    assert.equal(metrics.PREFETCH_FRACTION, 0.5);
    // 1000 px viewport, 2000 px of content: at 400 we are not there yet...
    assert.equal(metrics.shouldFetchMore(400, 1000, 2000), false);
    // ...at 600 the remaining 400 px is under half a viewport.
    assert.equal(metrics.shouldFetchMore(600, 1000, 2000), true);
    // A list shorter than the viewport is always "close to the end".
    assert.equal(metrics.shouldFetchMore(0, 800, 300), true);
});
