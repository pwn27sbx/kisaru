"use strict";

// The visible library rule: folders, hidden folders and the lock state.
//
// This is the module every LibraryView, count, status line and empty state
// reads, so it fails closed: while locked, or before organizer.json loads, a
// title whose folder cannot be resolved is hidden.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");

const view = require("../services/library_view.js");

const FOLDERS = [
    { id: "f1", name: "Universidad", hidden: false },
    { id: "f2", name: "Privado", hidden: true }
];

const ENTRIES = [
    { id: "a", title: "Uno", lastReadChapterNum: "3" },
    { id: "b", title: "Dos", folder: "f1" },
    { id: "c", title: "Tres", folder: "f2", lastReadChapterNum: "7" },
    { id: "d", title: "Cuatro", folder: "gone" }
];

const ids = (list) => list.map((e) => e.id);

test("old entries without a folder stay valid", () => {
    assert.deepEqual(ids(view.visibleEntries(ENTRIES, [], { loaded: false, locked: true })),
        ["a"]);
    assert.deepEqual(ids(view.visibleEntries(
        [{ id: "old", title: "Viejo" }], [], { loaded: true, locked: true })), ["old"]);
});

test("a known folder is visible while unlocked and hidden only when marked hidden", () => {
    assert.deepEqual(ids(view.visibleEntries(ENTRIES, FOLDERS, { loaded: true, locked: false })),
        ["a", "b", "c"]);
});

test("while locked a hidden folder and its titles are gone", () => {
    assert.deepEqual(ids(view.visibleEntries(ENTRIES, FOLDERS, { loaded: true, locked: true })),
        ["a", "b"]);
});

test("fail closed: an unknown folder is hidden in both lock states", () => {
    assert.ok(!ids(view.visibleEntries(ENTRIES, FOLDERS, { loaded: true, locked: true })).includes("d"));
    assert.ok(!ids(view.visibleEntries(ENTRIES, FOLDERS, { loaded: true, locked: false })).includes("d"));
});

test("fail closed: before organizer data loads a pushed entry is hidden", () => {
    const list = view.visibleEntries(ENTRIES, [], { loaded: false, locked: false });
    assert.deepEqual(ids(list), ["a"]);
});

test("the active folder filters the visible list, Todas does not", () => {
    assert.deepEqual(ids(view.visibleEntries(ENTRIES, FOLDERS,
        { loaded: true, locked: false, folder: "f1" })), ["b"]);
    assert.deepEqual(ids(view.visibleEntries(ENTRIES, FOLDERS,
        { loaded: true, locked: false, folder: "" })), ["a", "b", "c"]);
    assert.deepEqual(ids(view.visibleEntries(ENTRIES, FOLDERS,
        { loaded: true, locked: false, folder: "f2" })), ["c"]);
});

test("a hidden active folder shows nothing while locked", () => {
    assert.deepEqual(view.visibleEntries(ENTRIES, FOLDERS,
        { loaded: true, locked: true, folder: "f2" }), []);
});

test("the count is every visible title, whatever the active folder", () => {
    assert.equal(view.visibleCount(ENTRIES, FOLDERS, { loaded: true, locked: false }), 3);
    assert.equal(view.visibleCount(ENTRIES, FOLDERS, { loaded: true, locked: true }), 2);
    assert.equal(view.visibleCount(ENTRIES, [], { loaded: false, locked: true }), 1);
});

test("visible folders hide the hidden ones only while locked", () => {
    assert.deepEqual(view.visibleFolders(FOLDERS, true).map((f) => f.id), ["f1"]);
    assert.deepEqual(view.visibleFolders(FOLDERS, false).map((f) => f.id), ["f1", "f2"]);
});

test("folder CRUD keeps the rest of the list and never loses titles", () => {
    const created = view.newFolder(FOLDERS, "  Viajes  ", "f3");
    assert.deepEqual(created.map((f) => f.id), ["f1", "f2", "f3"]);
    assert.equal(created[2].name, "Viajes");
    assert.equal(created[2].hidden, false);

    const renamed = view.renamedFolder(created, "f3", "  Playa ");
    assert.equal(renamed[2].name, "Playa");

    // An empty name is not a rename, and an unknown id is not an insertion.
    assert.deepEqual(view.renamedFolder(created, "f3", "   "), created);
    assert.deepEqual(view.renamedFolder(created, "nope", "X"), created);

    const hidden = view.hiddenFolder(created, "f3", true);
    assert.equal(hidden[2].hidden, true);
    assert.deepEqual(view.removedFolder(created, "f3").map((f) => f.id), ["f1", "f2"]);
});

test("deleting a folder moves its titles to no folder and keeps the titles", () => {
    const kept = view.entriesWithoutFolder(ENTRIES, "f1");
    assert.equal(kept.length, ENTRIES.length);
    assert.equal(view.findEntry(kept, "b").folder, "");
    assert.equal(view.findEntry(kept, "b").title, "Dos");
    assert.equal(view.findEntry(kept, "c").folder, "f2");
});

test("an existing entry is returned whole, progress included", () => {
    // The save path must never rebuild an entry: that is what keeps progress
    // and folder when a title is re-added from Browse.
    const entry = view.findEntry(ENTRIES, "c");
    assert.equal(entry.lastReadChapterNum, "7");
    assert.equal(entry.folder, "f2");
    assert.equal(view.findEntry(ENTRIES, "nope"), null);
});
test("a visible folder opens while locked, whether or not a secret exists", () => {
    // Locked is the default state and the no-secret state: an ordinary folder
    // must still open. The secret only matters for hidden folders.
    assert.equal(view.lockedOut("f1", FOLDERS, { loaded: true, locked: true }), false);
});

test("a hidden folder is closed while locked and open while unlocked", () => {
    assert.equal(view.lockedOut("f2", FOLDERS, { loaded: true, locked: true }), true);
    assert.equal(view.lockedOut("f2", FOLDERS, { loaded: true, locked: false }), false);
});

test("an unresolved folder counts as hidden while locked", () => {
    // Fail closed: a folder id that is not in the organizer must not open.
    assert.equal(view.lockedOut("gone", FOLDERS, { loaded: true, locked: true }), true);
    assert.equal(view.lockedOut("gone", FOLDERS, { loaded: true, locked: false }), false);
    // Before the organizer file loads, no folder can be resolved.
    assert.equal(view.lockedOut("f1", [], { loaded: false, locked: true }), true);
});

test("no folder and the unlocked state are never locked out", () => {
    assert.equal(view.lockedOut("", FOLDERS, { loaded: true, locked: true }), false);
    assert.equal(view.lockedOut("f2", FOLDERS, { loaded: true, locked: false }), false);
});
test("a hidden title disappears alone while locked", () => {
    const entries = [
        { id: "v", title: "Visible" },
        { id: "h", title: "Oculto", hidden: true },
        { id: "f", title: "En carpeta", folder: "f1" },
        { id: "fh", title: "En carpeta oculto", folder: "f1", hidden: true }
    ];
    assert.deepEqual(ids(view.visibleEntries(entries, FOLDERS,
        { loaded: true, locked: true })), ["v", "f"]);
    assert.deepEqual(ids(view.visibleEntries(entries, FOLDERS,
        { loaded: true, locked: false })), ["v", "h", "f", "fh"]);
});

test("a hidden title hides without taking its visible folder with it", () => {
    const entries = [
        { id: "a", title: "Dentro", folder: "f1" },
        { id: "b", title: "Dentro oculto", folder: "f1", hidden: true }
    ];
    assert.deepEqual(ids(view.visibleEntries(entries, FOLDERS,
        { loaded: true, locked: true, folder: "f1" })), ["a"]);
    assert.equal(view.visibleCount(entries, FOLDERS,
        { loaded: true, locked: true }), 1);
    assert.ok(view.visibleFolders(FOLDERS, true).some((folder) => folder.id === "f1"));
});
