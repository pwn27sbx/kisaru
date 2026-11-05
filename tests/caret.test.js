"use strict";

// The search caret's horizontal rule.
//
// At position 0 the bar must stand in the reserved room to the LEFT of the
// first character. Once there is a character before the cursor, the bar must
// sit AT the cursor instead: the negative offset that is right for an empty
// field would land it on the last letter.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");

const caret = require("../services/caret.js");

const W = 2;
const GAP = 2;

test("at the start the bar stands before the first character", () => {
    assert.equal(caret.barX(0, W, GAP), -W - GAP);
});

test("with text before it the bar sits at the cursor, never on a letter", () => {
    // Middle and end: both are cursor positions over existing text.
    assert.equal(caret.barX(1, W, GAP), 0);
    assert.equal(caret.barX(6, W, GAP), 0);
    assert.equal(caret.barX(40, W, GAP), 0);
});

test("a negative or missing position is treated as the empty start", () => {
    assert.equal(caret.barX(-1, W, GAP), -W - GAP);
    assert.equal(caret.barX(undefined, W, GAP), -W - GAP);
});
