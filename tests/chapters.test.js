"use strict";

// Tests for services/chapters.js — locating "the chapter where I left off".
//
// The library stores lastReadChapterNum as the string the reader saved
// ("105"), while a source may list the same chapter as "105.00"
// (zonatmo.org) or "Capítulo 105". After the 2026-10-27 source switch the
// stored lastReadChapterId stopped matching any row, so the "Last: Ch. N"
// badge had to compare numbers instead of ids.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");

const chapters = require("../services/chapters.js");

test("formatChapter keeps the digits and an optional decimal", () => {
    assert.equal(chapters.formatChapter("Capítulo 105.00"), "105.00");
    assert.equal(chapters.formatChapter("105"), "105");
    assert.equal(chapters.formatChapter("?45"), "45");
    assert.equal(chapters.formatChapter(""), "?");
    assert.equal(chapters.formatChapter(null), "?");
    assert.equal(chapters.formatChapter("extra"), "extra");
});

test("a stored 105 reaches the row listed as 105.00", () => {
    const list = [{ chapter: "106.00" }, { chapter: "105.00" }, { chapter: "104.00" }];
    assert.equal(chapters.chapterIndex(list, "105"), 1);
});

test("a decimal chapter never matches its integer neighbour", () => {
    const list = [{ chapter: "105" }, { chapter: "105.5" }];
    assert.equal(chapters.chapterIndex(list, "105.5"), 1);
    assert.equal(chapters.chapterIndex(list, "105"), 0);
});

test("an empty or missing list has no index", () => {
    assert.equal(chapters.chapterIndex([], "105"), -1);
    assert.equal(chapters.chapterIndex(null, "105"), -1);
    assert.equal(chapters.chapterIndex([{ chapter: "1" }], ""), -1);
});

test("the first matching row wins", () => {
    const list = [{ chapter: "7.00" }, { chapter: "7.0" }, { chapter: "8" }];
    assert.equal(chapters.chapterIndex(list, "7"), 0);
});

// ── adjacentChapter (N1 / A7) ────────────────────────────────────────────────

test("adjacentChapter moves in ascending chapter-number order regardless of source order", () => {
    const desc = [
        { id: "c3", chapter: "3" },
        { id: "c2", chapter: "2" },
        { id: "c1", chapter: "1" },
    ];
    assert.equal(chapters.adjacentChapter(desc, "c2", 1).id, "c3");
    assert.equal(chapters.adjacentChapter(desc, "c2", -1).id, "c1");
});

test("adjacentChapter returns null at the start and end of the list", () => {
    const list = [
        { id: "c1", chapter: "1" },
        { id: "c2", chapter: "2" },
    ];
    assert.equal(chapters.adjacentChapter(list, "c1", -1), null);
    assert.equal(chapters.adjacentChapter(list, "c2", 1), null);
});

test("adjacentChapter skips duplicate chapter numbers and picks the first in source order", () => {
    const list = [
        { id: "c11-a", chapter: "11" },
        { id: "c11-b", chapter: "11.00" },
        { id: "c10-a", chapter: "10" },
        { id: "c10-b", chapter: "10.00" },
        { id: "c9-a", chapter: "9" },
        { id: "c9-b", chapter: "9.0" },
    ];
    assert.equal(chapters.adjacentChapter(list, "c10-a", 1).id, "c11-a");
    assert.equal(chapters.adjacentChapter(list, "c10-b", 1).id, "c11-a");
    assert.equal(chapters.adjacentChapter(list, "c10-a", -1).id, "c9-a");
    assert.equal(chapters.adjacentChapter(list, "c10-b", -1).id, "c9-a");
});

test("adjacentChapter handles decimal chapters in numeric order", () => {
    const list = [
        { id: "c106", chapter: "106" },
        { id: "c105", chapter: "105" },
        { id: "c105_5", chapter: "105.5" },
    ];
    assert.equal(chapters.adjacentChapter(list, "c105", 1).id, "c105_5");
    assert.equal(chapters.adjacentChapter(list, "c105_5", 1).id, "c106");
    assert.equal(chapters.adjacentChapter(list, "c105_5", -1).id, "c105");
    assert.equal(chapters.adjacentChapter(list, "c106", -1).id, "c105_5");
});

test("adjacentChapter sorts chapters without a number as 0, matching DetailView", () => {
    const list = [
        { id: "c2", chapter: "2" },
        { id: "c1", chapter: "1" },
        { id: "prologue", chapter: "Prólogo" },
    ];
    assert.equal(chapters.adjacentChapter(list, "prologue", -1), null);
    assert.equal(chapters.adjacentChapter(list, "prologue", 1).id, "c1");
    assert.equal(chapters.adjacentChapter(list, "c1", -1).id, "prologue");
});

test("adjacentChapter returns null when list is empty or currentId is missing", () => {
    const list = [{ id: "c1", chapter: "1" }];
    assert.equal(chapters.adjacentChapter([], "c1", 1), null);
    assert.equal(chapters.adjacentChapter(null, "c1", 1), null);
    assert.equal(chapters.adjacentChapter(list, "", 1), null);
    assert.equal(chapters.adjacentChapter(list, "missing", 1), null);
});
