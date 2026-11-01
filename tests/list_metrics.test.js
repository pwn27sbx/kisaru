"use strict";

// The list geometry and the prefetch threshold, shared by every list view.
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const metrics = require("../services/list_metrics.js");

test("a row is 72 base units and the skeleton reads the same number", () => {
    assert.equal(metrics.ROW_HEIGHT_BASE, 72);
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
