"use strict";

// The Detail's hide switch, decided once for the three panels.
//
// Owner (2026-11-05): pressing Ocultar inside a title must NOT throw him out.
// It marks the title hidden and stays, so the folder list can show the hidden
// folders and he can file it right there. The lock lands when the Detail is
// left, which is when the title must be gone from the Library.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const hide = require("../services/detail_hide.js");
const libraryView = require("../services/library_view.js");

const ROOT = path.resolve(__dirname, "..");
const read = (rel) => fs.readFileSync(path.join(ROOT, rel), "utf8");

test("an unconfigured word leaves the switch inert", () => {
    assert.equal(hide.toggle({ configured: false, locked: false, hidden: false }),
        hide.ACTION.IGNORE);
    assert.equal(hide.toggle({ configured: false, locked: true, hidden: true }),
        hide.ACTION.IGNORE);
});

test("locked: the switch still hides and leaves, never stays", () => {
    assert.equal(hide.toggle({ configured: true, locked: true, hidden: false }),
        hide.ACTION.HIDE_LEAVE);
    // An already hidden title opened from Browse: the press only leaves.
    assert.equal(hide.toggle({ configured: true, locked: true, hidden: true }),
        hide.ACTION.LEAVE);
});

test("unlocked: the switch hides and stays, or unhides and stays", () => {
    assert.equal(hide.toggle({ configured: true, locked: false, hidden: false }),
        hide.ACTION.HIDE_STAY);
    assert.equal(hide.toggle({ configured: true, locked: false, hidden: true }),
        hide.ACTION.UNHIDE_STAY);
});

test("the picker lists hidden folders only for an already hidden title", () => {
    // Not hidden: the current rule. Locked hides them, unlocked shows them.
    assert.equal(hide.pickerShowsHidden({ locked: true, hidden: false }), false);
    assert.equal(hide.pickerShowsHidden({ locked: false, hidden: false }), true);
    // Already hidden: hidden folders are offered at once, lock or not.
    assert.equal(hide.pickerShowsHidden({ locked: true, hidden: true }), true);
    assert.equal(hide.pickerShowsHidden({ locked: false, hidden: true }), true);
});

test("a hidden title stays usable while unlocked and leaves the Library once locked", () => {
    const entry = { id: "t:a", hidden: true, folder: "" };
    const options = (locked) => ({ loaded: true, locked: locked, folder: "" });
    // Still in Detail, still unlocked: the title is there and usable.
    assert.equal(libraryView.isVisible(entry, [], options(false)), true);
    // Left the Detail: the lock applies and the title is gone.
    assert.equal(libraryView.isVisible(entry, [], options(true)), false);
});

test("each Detail defers the lock to the leave, and the picker reads the rule", () => {
    for (const [file, service] of [
        ["modules/manga/components/DetailView.qml", "Manga"],
        ["modules/novel/components/DetailView.qml", "Novel"],
        ["modules/anime/components/DetailView.qml", "Anime"],
    ]) {
        const qml = read(file);
        assert.match(qml, /DetailHide\.toggle\(/, `${file}: the switch does not use the shared rule`);
        assert.match(qml, /DetailHide\.pickerShowsHidden\(/,
            `${file}: the picker does not use the shared rule`);
        assert.match(qml, /_hiddenInDetail/, `${file}: the deferred hide has no state`);
        // The unlocked hide must not lock or navigate.
        assert.match(qml, /DetailHide\.ACTION\.HIDE_STAY[\s\S]{0,200}?_hiddenInDetail = true/,
            `${file}: HIDE_STAY does not arm the deferred hide`);
        assert.doesNotMatch(qml, /HIDE_STAY[\s\S]{0,120}?Privacy\.lock\(\)/,
            `${file}: HIDE_STAY still locks on the press`);
        assert.match(qml, /onVisibleChanged[\s\S]{0,200}?_settleHiddenInDetail\(\)/,
            `${file}: leaving the Detail does not settle the hide`);
        assert.match(qml, /function _settleHiddenInDetail\(\)[\s\S]{0,240}?Privacy\.lock\(\)/,
            `${file}: leaving the Detail does not lock`);
        // Assigning a folder is not gated behind the word.
        assert.match(qml, new RegExp(`${service}\\.setFolder\\(`),
            `${file}: the picker cannot assign a folder`);
        // Nothing in the hide path writes a log line: no title, no id.
        const from = qml.indexOf("function _settleHiddenInDetail");
        const toggleAt = qml.indexOf("function _toggleHiddenTitle");
        const toggleEnd = qml.indexOf("\n    }\n", toggleAt);
        assert.ok(from > -1 && toggleAt > from, `${file}: the hide path moved`);
        const hidePath = qml.slice(from, toggleEnd);
        assert.ok(!hidePath.includes("console."), `${file}: the hide path logs`);
    }
});

test("assigning a folder asks for no word, and progress stays protected", () => {
    for (const file of ["services/Manga.qml", "services/Novel.qml", "services/Anime.qml"]) {
        const qml = read(file);
        const start = qml.indexOf("function setFolder(");
        const body = qml.slice(start, qml.indexOf("\n    }", start));
        // Filing a title is a folder write, not a reveal: no lock in the way.
        assert.ok(!body.includes("Privacy"), `${file}: setFolder is gated behind the word`);
        // A hidden title must not write progress while the mode is locked.
        assert.match(qml, /Privacy\.locked && root\.isHiddenLibraryEntry\(/,
            `${file}: progress is no longer protected while locked`);
    }
});
