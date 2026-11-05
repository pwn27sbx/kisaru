"use strict";

// How a merged search page moves the panel forward.
//
// The chain now asks every source, so a page is the union of their windows and
// can be shorter than the offset jump (dedupe) — or, defensively, report more
// results while the offset does not move. A page that does not advance must
// stop the paging, or scrolling would ask for the same window forever.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const paging = require("../services/search_paging.js");

const ROOT = path.resolve(__dirname, "..");
const read = (rel) => fs.readFileSync(path.join(ROOT, rel), "utf8");

test("a page advances by the offset the chain reports", () => {
    const page = paging.nextPage(0, { nextOffset: 30, hasMore: true }, 24);
    assert.equal(page.offset, 30);
    assert.equal(page.hasMore, true);
});

test("a short page still advances by the chain's offset, not by its length", () => {
    // Five sources merged and deduped into 12 items, but every source advanced
    // its own 30-item window: the next request must start at 30.
    const page = paging.nextPage(30, { nextOffset: 60, hasMore: true }, 12);
    assert.equal(page.offset, 60);
    assert.equal(page.hasMore, true);
});

test("the last page reports no more", () => {
    const page = paging.nextPage(0, { nextOffset: 30, hasMore: false }, 30);
    assert.equal(page.offset, 30);
    assert.equal(page.hasMore, false);
});

test("a page that does not move the offset stops the paging", () => {
    const page = paging.nextPage(30, { nextOffset: 30, hasMore: true }, 0);
    assert.equal(page.offset, 30);
    assert.equal(page.hasMore, false, "a stalled page would be fetched forever");
});

test("a missing offset falls back to the item count", () => {
    const page = paging.nextPage(30, { hasMore: true }, 7);
    assert.equal(page.offset, 37);
    assert.equal(page.hasMore, true);
});

test("garbage offsets cannot move the panel backwards", () => {
    assert.equal(paging.nextPage(30, { nextOffset: -5, hasMore: true }, 0).offset, 0);
    assert.equal(paging.nextPage(30, { nextOffset: -5, hasMore: true }, 0).hasMore, false);
    assert.equal(paging.nextPage(0, { nextOffset: "sixty", hasMore: true }, 4).offset, 4);
    assert.equal(paging.nextPage(undefined, {}, 0).offset, 0);
});

test("the panel pages through the shared rule, not with its own arithmetic", () => {
    const qml = read("services/Manga.qml");
    assert.match(qml, /SearchPaging\.nextPage\(/,
        "Manga.qml still advances the offset on its own");
    assert.match(qml, /hasMoreManga = page\.hasMore/,
        "the panel ignores the guarded hasMore");
});
