"use strict";

// Where the app keeps its config and its libraries (owner decision D6).
// The rule is "new path first, inherited path only while it is the only one",
// and it is pinned here because the QML around it is just filesystem probes.
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const paths = require("../services/app_paths.js");

const HOME = "/home/someone";

test("the project's own names are the new ones", () => {
    assert.equal(paths.CONFIG_DIR, "kisaru");
    assert.equal(paths.DATA_DIR, "kisaru");
});

test("the inherited names are kept only to be read, never to be written", () => {
    assert.equal(paths.LEGACY_CONFIG_DIR, "qs-novelmangareader");
    assert.equal(paths.LEGACY_LIBRARY_DIR, "quickshell");
});

test("the new path wins as soon as it exists", () => {
    assert.equal(paths.resolvePath("/new", "/old", true, true), "/new");
    assert.equal(paths.resolvePath("/new", "/old", true, false), "/new");
});

test("the inherited path is used while it is the only one that exists", () => {
    assert.equal(paths.resolvePath("/new", "/old", false, true), "/old");
});

test("neither existing means a fresh install writes to the new name", () => {
    assert.equal(paths.resolvePath("/new", "/old", false, false), "/new");
});

test("the three libraries have one name each, in both folders", () => {
    assert.equal(paths.libraryPath(HOME + "/.local/share", "manga", false),
        HOME + "/.local/share/kisaru/manga_library.json");
    assert.equal(paths.libraryPath(HOME + "/.local/share", "anime", false),
        HOME + "/.local/share/kisaru/anime_library.json");
    assert.equal(paths.libraryPath(HOME + "/.local/share", "novel", false),
        HOME + "/.local/share/kisaru/new_novel_library.json");
    // The inherited location is the neutral folder the whole rice shares.
    assert.equal(paths.libraryPath(HOME + "/.local/share", "manga", true),
        HOME + "/.local/share/quickshell/manga_library.json");
});

test("an unknown library is an error, not a silent empty path", () => {
    assert.throws(() => paths.libraryPath(HOME, "books", false), /unknown library/);
});
