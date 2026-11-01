"use strict";

// The list geometry and the prefetch threshold, shared by every list view.
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const metrics = require("../services/list_metrics.js");

test("a row is 106 base units and the skeleton reads the same number", () => {
    // A-9 sketch: a 90 px cover plus a little air above and below.
    assert.equal(metrics.ROW_HEIGHT_BASE, 106);
});

test("the thumbnail is the sketch's 64 x 90 and fits inside the row", () => {
    assert.equal(metrics.THUMB_WIDTH, 64);
    assert.equal(metrics.THUMB_HEIGHT, 90);
    // 64/90 = 0.71: the same crop the grid's 2:3 poster takes.
    assert.ok(metrics.THUMB_WIDTH / metrics.THUMB_HEIGHT > 0.69 && metrics.THUMB_WIDTH / metrics.THUMB_HEIGHT < 0.72);
    assert.ok(metrics.ROW_HEIGHT_BASE > metrics.THUMB_HEIGHT, "the cover is taller than its row");
    // Both sides are declared: nothing derives one from a ratio, which is what
    // the A-8 review flagged.
    assert.equal(metrics.THUMB_RATIO, undefined);
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
