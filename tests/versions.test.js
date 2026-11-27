"use strict";

// Tests for the chapter-version grouping in services/chapters.js.
//
// A source can list the same chapter twice: "1" and "1.1", where the second
// row is a later re-upload of the same content, not a new chapter. Grouping
// them is only safe when the decimals form a *generation* — a later, clustered
// upload of many chapters — because genuine decimals live in the same series:
// a "12.5" extra, a "55.1" with no chapter 55, a split numbering "12.1"/"12.2".
//
// The corpus below is synthetic but shaped like the live series measured on
// 2026-11-27 (71 integers dated 09/04/2026, 66 ".1" rows dated 21/04/2026).
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");

const chapters = require("../services/chapters.js");

const ORIGINAL_DAY = "09/04/2026";
const REUPLOAD_DAY = "21/04/2026";

// One chapter row, the shape mapChapter() produces.
function chapter(number, id, day, extra) {
    const row = { id: id, chapter: String(number), title: "Capítulo " + number, pages: 0, group: "", publishAt: day || "" };
    return Object.assign(row, extra || {});
}

// n integers + their ".1" re-uploads, two clearly separate generations.
function generation(n) {
    const rows = [];
    for (let i = 1; i <= n; i++) rows.push(chapter(i, "old-" + i, ORIGINAL_DAY));
    for (let i = 1; i <= n; i++) rows.push(chapter(i + ".1", "new-" + i, REUPLOAD_DAY));
    return rows;
}

function numbers(groups) {
    return groups.map(group => group.chapter);
}

// ── Tier A: the same chapter string twice ────────────────────────────────────

test("two groups on the same chapter number are versions of one chapter", () => {
    const list = [
        chapter("12", "mangadex:a", "2026-04-09T00:00:00Z", { group: "Grupo A" }),
        chapter("12", "mangadex:b", "2026-04-21T00:00:00Z", { group: "Grupo B" })
    ];
    const groups = chapters.groupChapters(list);
    assert.equal(groups.length, 1);
    assert.equal(groups[0].chapter, "12");
    assert.deepEqual(groups[0].versions.map(v => v.id), ["mangadex:a", "mangadex:b"]);
    assert.equal(groups[0].versions[1].group, "Grupo B");
});

test("a duplicated chapter id in one source stays one chapter, not two", () => {
    const list = [
        chapter("3", "zonatmo_org:1", ORIGINAL_DAY),
        chapter("3", "zonatmo_org:2", REUPLOAD_DAY)
    ];
    const groups = chapters.groupChapters(list);
    assert.equal(groups.length, 1);
    assert.equal(groups[0].versions.length, 2);
});

// ── Tier B: a re-upload generation ───────────────────────────────────────────

test("a later .1 generation merges into one row per chapter", () => {
    const groups = chapters.groupChapters(generation(6));
    assert.equal(groups.length, 6);
    assert.deepEqual(numbers(groups), ["1", "2", "3", "4", "5", "6"]);
    for (const group of groups) {
        assert.equal(group.versions.length, 2);
        assert.equal(group.versions[0].id.slice(0, 4), "old-");
        assert.equal(group.versions[1].id.slice(0, 4), "new-");
    }
});

test("a rejected generation leaves the list exactly as it was", () => {
    const list = [
        chapter("9", "old-9", ORIGINAL_DAY),
        chapter("9.5", "extra-9", REUPLOAD_DAY),
        chapter("10", "old-10", ORIGINAL_DAY),
        chapter("10.1", "new-10", REUPLOAD_DAY)
    ];
    const groups = chapters.groupChapters(list);
    assert.deepEqual(numbers(groups), ["9", "9.5", "10", "10.1"]);
    assert.equal(groups[1].versions.length, 1);
});

test("a single .1 stray never merges", () => {
    const list = [chapter("23", "old-23", "15/10/2026"), chapter("23.1", "new-23", "03/11/2026")];
    const groups = chapters.groupChapters(list);
    assert.deepEqual(numbers(groups), ["23", "23.1"]);
});

test("two .1 rows on different days are not a generation", () => {
    const list = [
        chapter("9", "a", "11/07/2026"),
        chapter("9.1", "b", "10/07/2026"),
        chapter("23", "c", "15/10/2026"),
        chapter("23.1", "d", "03/11/2026")
    ];
    assert.deepEqual(numbers(chapters.groupChapters(list)), ["9", "9.1", "23", "23.1"]);
});

test("an orphan decimal with no base chapter never merges", () => {
    const list = [
        chapter("54", "old-54", ORIGINAL_DAY),
        chapter("55.1", "orphan", REUPLOAD_DAY),
        chapter("56", "old-56", ORIGINAL_DAY),
        chapter("56.1", "new-56", REUPLOAD_DAY),
        chapter("57", "old-57", ORIGINAL_DAY),
        chapter("57.1", "new-57", REUPLOAD_DAY),
        chapter("58", "old-58", ORIGINAL_DAY),
        chapter("58.1", "new-58", REUPLOAD_DAY)
    ];
    const groups = chapters.groupChapters(list);
    assert.equal(groups.length, 5);
    assert.ok(numbers(groups).includes("55.1"));
});

test("the mass threshold needs at least 3 pairs and a quarter of the integers", () => {
    // 12 integers, 2 re-uploads: below the quarter.
    let list = [];
    for (let i = 1; i <= 12; i++) list.push(chapter(i, "old-" + i, ORIGINAL_DAY));
    list.push(chapter("1.1", "new-1", REUPLOAD_DAY));
    list.push(chapter("2.1", "new-2", REUPLOAD_DAY));
    assert.equal(chapters.groupChapters(list).length, 14);

    // 3 of 12 is exactly the quarter: accepted.
    list.push(chapter("3.1", "new-3", REUPLOAD_DAY));
    const groups = chapters.groupChapters(list);
    assert.equal(groups.length, 12);
    assert.equal(groups[0].versions.length, 2);
    assert.equal(groups[3].versions.length, 1);
});

test("candidate ids interleaved with the originals are not a later generation", () => {
    const list = [
        chapter("1", "100", ORIGINAL_DAY),
        chapter("2", "101", ORIGINAL_DAY),
        chapter("3", "102", ORIGINAL_DAY),
        chapter("1.1", "103", REUPLOAD_DAY),
        chapter("2.1", "99", REUPLOAD_DAY),
        chapter("3.1", "104", REUPLOAD_DAY)
    ];
    assert.equal(chapters.groupChapters(list).length, 6);
});

test("a candidate published before its base is not a re-upload", () => {
    const list = [
        chapter("1", "old-1", "20/04/2026"),
        chapter("1.1", "new-1", "19/04/2026"),
        chapter("2", "old-2", "20/04/2026"),
        chapter("2.1", "new-2", REUPLOAD_DAY),
        chapter("3", "old-3", "20/04/2026"),
        chapter("3.1", "new-3", REUPLOAD_DAY),
        chapter("4", "old-4", "20/04/2026"),
        chapter("4.1", "new-4", REUPLOAD_DAY)
    ];
    const groups = chapters.groupChapters(list);
    assert.ok(numbers(groups).includes("1.1"));
    assert.equal(groups.find(g => g.chapter === "2").versions.length, 2);
});

// ── The guards that keep genuine decimals real ───────────────────────────────

test("a .5 extra is never merged, even inside a real generation", () => {
    const list = generation(4);
    list.push(chapter("2.5", "extra-2", REUPLOAD_DAY));
    const groups = chapters.groupChapters(list);
    assert.equal(groups.length, 5);
    assert.ok(numbers(groups).includes("2.5"));
});

test("other fractions (.25, .75) are never merged", () => {
    const list = generation(4);
    list.push(chapter("3.25", "quarter", REUPLOAD_DAY));
    list.push(chapter("3.75", "three-quarters", REUPLOAD_DAY));
    const groups = chapters.groupChapters(list);
    assert.ok(numbers(groups).includes("3.25"));
    assert.ok(numbers(groups).includes("3.75"));
});

test("split numbering N.1/N.2 keeps the halves as their own chapters", () => {
    const list = [
        chapter("1", "old-1", ORIGINAL_DAY),
        chapter("2", "old-2", ORIGINAL_DAY),
        chapter("3", "old-3", ORIGINAL_DAY),
        chapter("4", "old-4", ORIGINAL_DAY),
        chapter("1.1", "new-1", REUPLOAD_DAY),
        chapter("2.1", "new-2", REUPLOAD_DAY),
        chapter("2.2", "half-2", REUPLOAD_DAY),
        chapter("3.1", "new-3", REUPLOAD_DAY),
        chapter("4.1", "new-4", REUPLOAD_DAY)
    ];
    const groups = chapters.groupChapters(list);
    assert.ok(numbers(groups).includes("2.1"));
    assert.ok(numbers(groups).includes("2.2"));
    assert.equal(groups.find(g => g.chapter === "1").versions.length, 2);
    assert.equal(groups.find(g => g.chapter === "2").versions.length, 1);
});

test("12.10 and 12.1 are different chapters", () => {
    const list = [
        chapter("12", "old-12", ORIGINAL_DAY),
        chapter("12.1", "one", REUPLOAD_DAY),
        chapter("12.10", "ten", REUPLOAD_DAY)
    ];
    const groups = chapters.groupChapters(list);
    assert.deepEqual(numbers(groups), ["12", "12.1", "12.10"]);
});

test("a list without dates never merges structurally", () => {
    const list = [
        chapter("1", "old-1"),
        chapter("2", "old-2"),
        chapter("3", "old-3"),
        chapter("4", "old-4"),
        chapter("1.1", "new-1"),
        chapter("2.1", "new-2"),
        chapter("3.1", "new-3"),
        chapter("4.1", "new-4")
    ];
    assert.equal(chapters.groupChapters(list).length, 8);
});

test("non-numeric labels stay where they are", () => {
    const list = generation(4);
    list.unshift(chapter("Prólogo", "prologue", ""));
    const groups = chapters.groupChapters(list);
    assert.equal(groups[0].chapter, "Prólogo");
    assert.equal(groups[0].versions.length, 1);
});

// ── Default version ─────────────────────────────────────────────────────────

test("the default version prefers the last-read id, then the chosen one", () => {
    const list = generation(4);
    const read = chapters.groupChapters(list, { lastReadId: "new-2" });
    assert.equal(read[1].primary.id, "new-2");

    const chosen = chapters.groupChapters(list, { lastReadId: "", choices: { "2": "old-2" } });
    assert.equal(chosen[1].primary.id, "old-2");
});

test("without a preference the newest upload wins, source order breaks the tie", () => {
    const list = generation(3);
    const groups = chapters.groupChapters(list);
    assert.equal(groups[0].primary.id, "new-1");

    const sameDay = [
        chapter("1", "a", ORIGINAL_DAY),
        chapter("1", "b", ORIGINAL_DAY)
    ];
    assert.equal(chapters.groupChapters(sameDay)[0].primary.id, "b");
});

// ── Canonical number, navigation ────────────────────────────────────────────

test("canonicalNumber folds a stored version number onto its chapter", () => {
    const groups = chapters.groupChapters(generation(4));
    assert.equal(chapters.canonicalNumber(groups, "2.1"), "2");
    assert.equal(chapters.canonicalNumber(groups, "2"), "2");
    assert.equal(chapters.canonicalNumber(groups, "9.9"), "9.9");
    assert.equal(chapters.canonicalNumber(null, "3"), "3");
});

test("adjacentGroup steps between chapters, never into a sibling version", () => {
    const groups = chapters.groupChapters(generation(3));
    assert.equal(chapters.adjacentGroup(groups, "old-1", 1).chapter, "2");
    assert.equal(chapters.adjacentGroup(groups, "new-1", 1).chapter, "2");
    assert.equal(chapters.adjacentGroup(groups, "new-2", -1).chapter, "1");
    assert.equal(chapters.adjacentGroup(groups, "old-3", 1), null);
    assert.equal(chapters.adjacentGroup(groups, "new-1", -1), null);
    assert.equal(chapters.adjacentGroup(groups, "missing", 1), null);
});

test("adjacentGroup keeps the decimal chapters of a rejected generation", () => {
    const list = [
        chapter("105", "c105", "09/04/2026"),
        chapter("105.5", "c1055", "10/04/2026"),
        chapter("106", "c106", "11/04/2026")
    ];
    const groups = chapters.groupChapters(list);
    assert.equal(chapters.adjacentGroup(groups, "c105", 1).chapter, "105.5");
    assert.equal(chapters.adjacentGroup(groups, "c1055", 1).chapter, "106");
});

// ── Shared corpus (JS and Python) ───────────────────────────────────────────
//
// tests/fixtures/chapter_versions.json feeds this test and
// tests/test_chapter_versions.py: the backend counts favourites' new chapters
// with the same rule (scripts/chapter_versions.py), so a change in one side
// that the other does not follow fails here first.

test("the shared corpus pins the JS grouping", () => {
    const fs = require("node:fs");
    const path = require("node:path");
    const corpus = JSON.parse(
        fs.readFileSync(path.join(__dirname, "fixtures", "chapter_versions.json"), "utf8")
    );
    for (const item of corpus.cases) {
        assert.equal(chapters.groupChapters(item.chapters).length, item.groups, item.name);
    }
});

// ── Picker rows and the chosen version (behaviour, not source text) ─────────

test("versionRows names each upload with its own number, date and state", () => {
    const group = chapters.groupChapters(generation(4))[0];
    const rows = chapters.versionRows(group, function(id) {
        return id === "new-1"
            ? { kind: "downloading", done: 3, total: 8 }
            : { kind: "idle", done: 0, total: 0 };
    });
    assert.equal(rows.length, 2);
    assert.deepEqual(rows[0], {
        id: "old-1", number: "1", group: "", date: "09/04/2026",
        state: "idle", done: 0, total: 0, downloadsVisible: true
    });
    assert.equal(rows[1].number, "1.1");
    assert.equal(rows[1].date, "21/04/2026");
    assert.equal(rows[1].state, "downloading");
    assert.equal(rows[1].done, 3);
    assert.equal(rows[1].total, 8);
});

test("versionRows masks every download state while the entry is hidden", () => {
    const group = chapters.groupChapters(generation(4))[0];
    const rows = chapters.versionRows(group, function() {
        return { kind: "downloaded", done: 0, total: 0 };
    }, true);
    for (const row of rows) {
        assert.equal(row.state, "idle", "a locked hidden entry never shows on-disk state");
        assert.equal(row.downloadsVisible, false);
    }
});

test("pickVersion finds the upload the user chose, or nothing", () => {
    const group = chapters.groupChapters(generation(4))[0];
    assert.equal(chapters.pickVersion(group, "new-1").chapter, "1.1");
    assert.equal(chapters.pickVersion(group, "missing"), null);
    assert.equal(chapters.pickVersion(null, "new-1"), null);
});

test("grouping survives a chapter label that collides with Object.prototype", () => {
    const list = [
        chapter("constructor", "proto", ""),
        chapter("toString", "proto2", ""),
        chapter("hasOwnProperty", "proto3", "")
    ];
    const groups = chapters.groupChapters(list);
    assert.deepEqual(numbers(groups), ["constructor", "toString", "hasOwnProperty"]);
});
