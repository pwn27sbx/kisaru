"use strict";

// Folder cards: the collage, the root order and the library-wide search.
//
// The views compose this with services/library_view.js, so a hidden folder is
// already gone before its collage is built and a hidden title can never be one
// of the covers. These probes pin the selection itself, the order the root
// shows (folders first, then titles without a folder) and the search that must
// cross every folder.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");

const cards = require("../services/folder_cards.js");
const view = require("../services/library_view.js");
const filter = require("../services/library_filter.js");

const coverOf = (entry) => entry.cover || "";
const titleOf = (entry) => entry.title || "";

const FOLDERS = [
    { id: "f1", name: "Universidad", hidden: false },
    { id: "f2", name: "Privado", hidden: true },
    { id: "f3", name: "Viajes", hidden: false }
];

const ENTRIES = [
    { id: "a", title: "Suelta", cover: "a.jpg" },
    { id: "b", title: "Muñeca", folder: "f1", cover: "b.jpg" },
    { id: "c", title: "Sin portada", folder: "f1", cover: "" },
    { id: "d", title: "Cuatro", folder: "f1", cover: "d.jpg" },
    { id: "e", title: "Cinco", folder: "f1", cover: "e.jpg" },
    { id: "f", title: "Seis", folder: "f1", cover: "f.jpg" },
    { id: "g", title: "Oculta", folder: "f2", cover: "g.jpg" }
];

const options = (over) => Object.assign({ loaded: true, locked: false, folder: "" }, over || {});

test("a collage shows one cover, then two, three, four, and never more", () => {
    const one = [{ cover: "1.jpg" }, { cover: "" }];
    assert.deepEqual(cards.coverList(one, coverOf), ["1.jpg"]);

    const two = [{ cover: "1.jpg" }, { cover: "2.jpg" }];
    assert.deepEqual(cards.coverList(two, coverOf), ["1.jpg", "2.jpg"]);

    const three = two.concat([{ cover: "3.jpg" }]);
    assert.deepEqual(cards.coverList(three, coverOf), ["1.jpg", "2.jpg", "3.jpg"]);

    const four = three.concat([{ cover: "4.jpg" }]);
    const five = four.concat([{ cover: "5.jpg" }, { cover: "6.jpg" }]);
    assert.deepEqual(cards.coverList(five, coverOf),
        ["1.jpg", "2.jpg", "3.jpg", "4.jpg"]);
});

test("an empty folder has no covers, and empty cover URLs are skipped", () => {
    assert.deepEqual(cards.coverList([], coverOf), []);
    assert.deepEqual(cards.coverList([{ cover: "" }, { cover: null }], coverOf), []);
    assert.deepEqual(cards.coverList([{ cover: "a.jpg" }, { cover: "" }], coverOf),
        ["a.jpg"]);
});

test("the root lists folders first, then titles without a folder", () => {
    const visible = view.visibleEntries(ENTRIES, FOLDERS, options());
    const split = cards.partition(visible, view.folderIdOf);
    const items = cards.rootItems(view.visibleFolders(FOLDERS, false),
        split.folderless, split.byFolder, coverOf);

    assert.deepEqual(items.map((item) => item.kind),
        ["folder", "folder", "folder", "title"]);
    assert.deepEqual(items.map((item) => item.kind === "folder" ? item.id : item.entry.id),
        ["f1", "f2", "f3", "a"]);

    const first = items[0];
    assert.equal(first.name, "Universidad");
    assert.equal(first.count, 5);
    // The title with no cover is counted but never used in the mosaic.
    assert.deepEqual(first.covers, ["b.jpg", "d.jpg", "e.jpg", "f.jpg"]);
    assert.equal(items[1].hidden, true);
    assert.equal(items[1].count, 1);
    assert.deepEqual(items[1].covers, ["g.jpg"]);
});

test("while locked a hidden folder and its collage do not exist", () => {
    const visible = view.visibleEntries(ENTRIES, FOLDERS, options({ locked: true }));
    const split = cards.partition(visible, view.folderIdOf);
    const items = cards.rootItems(view.visibleFolders(FOLDERS, true),
        split.folderless, split.byFolder, coverOf);

    assert.deepEqual(items.map((item) => item.kind === "folder" ? item.id : item.entry.id),
        ["f1", "f3", "a"]);
    // f2 is not in the map at all, so no path can build its collage.
    assert.equal(split.byFolder.f2, undefined);
    assert.deepEqual(cards.coverList(split.byFolder.f2 || [], coverOf), []);
    assert.ok(!items.some((item) => item.kind === "folder"
        && item.covers.indexOf("g.jpg") >= 0), "a hidden cover leaked into the root");
});

test("titles inside a folder do not appear at the root", () => {
    const visible = view.visibleEntries(ENTRIES, FOLDERS, options());
    const split = cards.partition(visible, view.folderIdOf);
    const items = cards.rootItems(view.visibleFolders(FOLDERS, false),
        split.folderless, split.byFolder, coverOf);
    const titles = items.filter((item) => item.kind === "title").map((item) => item.entry.id);
    assert.deepEqual(titles, ["a"]);
});

test("search crosses every visible folder and folds accents", () => {
    const visible = view.visibleEntries(ENTRIES, FOLDERS, options());
    assert.deepEqual(cards.searchTitles(visible, "muneca", filter.fold, titleOf)
        .map((entry) => entry.id), ["b"]);
    assert.deepEqual(cards.searchTitles(visible, "MUÑECA", filter.fold, titleOf)
        .map((entry) => entry.id), ["b"]);
    assert.deepEqual(cards.searchTitles(visible, "oculta", filter.fold, titleOf)
        .map((entry) => entry.id), ["g"]);
    // A query with no match is empty, not the whole shelf.
    assert.deepEqual(cards.searchTitles(visible, "nada", filter.fold, titleOf), []);
    // An empty query means everything visible, still across folders.
    assert.deepEqual(cards.searchTitles(visible, "", filter.fold, titleOf)
        .map((entry) => entry.id), ["a", "b", "c", "d", "e", "f", "g"]);
});

test("search never returns a title from a hidden folder while locked", () => {
    const visible = view.visibleEntries(ENTRIES, FOLDERS, options({ locked: true }));
    assert.deepEqual(cards.searchTitles(visible, "oculta", filter.fold, titleOf), []);
    assert.deepEqual(cards.searchTitles(visible, "", filter.fold, titleOf)
        .map((entry) => entry.id), ["a", "b", "c", "d", "e", "f"]);
});

test("partition keeps the library order inside each bucket", () => {
    const visible = view.visibleEntries(ENTRIES, FOLDERS, options());
    const split = cards.partition(visible, view.folderIdOf);
    assert.deepEqual(split.byFolder.f1.map((entry) => entry.id), ["b", "c", "d", "e", "f"]);
    assert.deepEqual(split.folderless.map((entry) => entry.id), ["a"]);
});
const WITH_HIDDEN = [ENTRIES[0],
    { id: "h0", title: "Primera oculta", folder: "f1", cover: "h0.jpg", hidden: true },
    ...ENTRIES.slice(1),
    { id: "h", title: "Título oculto", folder: "f1", cover: "h.jpg", hidden: true },
    { id: "h2", title: "Suelta oculta", cover: "h2.jpg", hidden: true }];

test("hidden titles leave the collage, count and root while locked", () => {
    const visible = view.visibleEntries(WITH_HIDDEN, FOLDERS, options({ locked: true }));
    const split = cards.partition(visible, view.folderIdOf);
    const items = cards.rootItems(view.visibleFolders(FOLDERS, true),
        split.folderless, split.byFolder, coverOf);
    const first = items.find((item) => item.kind === "folder" && item.id === "f1");
    assert.equal(first.count, 5);
    assert.deepEqual(first.covers, ["b.jpg", "d.jpg", "e.jpg", "f.jpg"]);
    assert.ok(!items.some((item) => item.kind === "title" && item.entry.id === "h2"));
});

test("hidden titles return to the collage, count and root while unlocked", () => {
    const visible = view.visibleEntries(WITH_HIDDEN, FOLDERS, options({ locked: false }));
    const split = cards.partition(visible, view.folderIdOf);
    const items = cards.rootItems(view.visibleFolders(FOLDERS, false),
        split.folderless, split.byFolder, coverOf);
    const first = items.find((item) => item.kind === "folder" && item.id === "f1");
    assert.equal(first.count, 7);
    // The hidden title now participates in the collage like any other.
    assert.deepEqual(first.covers, ["h0.jpg", "b.jpg", "d.jpg", "e.jpg"]);
    assert.ok(items.some((item) => item.kind === "title" && item.entry.id === "h2"));
});

test("search excludes a hidden title while locked and finds it unlocked", () => {
    const lockedVisible = view.visibleEntries(WITH_HIDDEN, FOLDERS, options({ locked: true }));
    assert.deepEqual(cards.searchTitles(lockedVisible, "oculto", filter.fold, titleOf), []);
    const openVisible = view.visibleEntries(WITH_HIDDEN, FOLDERS, options({ locked: false }));
    assert.deepEqual(cards.searchTitles(openVisible, "oculto", filter.fold, titleOf)
        .map((entry) => entry.id), ["h"]);
});
