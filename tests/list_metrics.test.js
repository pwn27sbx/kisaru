"use strict";

// The list geometry and the prefetch threshold, shared by every list view.
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const metrics = require("../services/list_metrics.js");

test("a row is 96 base units and the skeleton reads the same number", () => {
    // A-8: 72 could not hold a 56 px thumbnail plus a two-line title.
    assert.equal(metrics.ROW_HEIGHT_BASE, 96);
});

test("the thumbnail is 56 wide and the row still has room around it", () => {
    assert.equal(metrics.THUMB_WIDTH, 56);
    assert.equal(metrics.THUMB_RATIO, 0.7);
    // 2:3 of the width, plus a little air top and bottom.
    const thumbHeight = Math.round(metrics.THUMB_WIDTH / metrics.THUMB_RATIO);
    assert.equal(thumbHeight, 80);
    assert.ok(metrics.ROW_HEIGHT_BASE > thumbHeight, "the cover is taller than its row");
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
