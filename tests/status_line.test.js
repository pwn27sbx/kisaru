"use strict";

// The status bar's count segment (owner, round 4): "● Online · 32 loaded".
//
// The count moved out of the grid's heading row, so these probes pin the two
// things the move could break: which count the bar shows (Browse = loaded,
// Library = its size, settings = none) and the wording (Browse keeps the
// existing "N loaded" key, Library its bare number).
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const line = require("../services/status_line.js");
const i18n = require("../services/i18n.js");

const translate = (key, n) => i18n.tn("en", key, n);

test("Browse shows the loaded count", () => {
    const state = { tabIndex: 0, browseCount: 32, libraryCount: 1 };
    assert.equal(line.visibleCount(state), 32);
    assert.equal(line.format(line.visibleCount(state), 0, translate), "32 loaded");
});

test("Library names what the number is", () => {
    // Owner, round 6: a bare "0" next to the online dot said nothing.
    const state = { tabIndex: 1, browseCount: 32, libraryCount: 1 };
    assert.equal(line.visibleCount(state), 1);
    assert.equal(line.format(line.visibleCount(state), 1, translate), "1 in library");
    assert.equal(
        line.barText({ ...state, libraryCount: 0, translate }),
        "0 in library"
    );
    // Spanish singular/plural share the wording on purpose: "1 en la biblioteca".
    const es = (key, n) => i18n.tn("es", key, n);
    assert.equal(line.barText({ tabIndex: 1, libraryCount: 3, translate: es }), "3 en la biblioteca");
});

test("the settings page shows no count at all", () => {
    const state = { settingsMode: true, tabIndex: 0, browseCount: 32, libraryCount: 1 };
    assert.equal(line.visibleCount(state), line.NONE);
    assert.equal(line.format(line.NONE, 0, translate), "");
});

test("zero is a real count, not an empty one", () => {
    const state = { tabIndex: 0, browseCount: 0, libraryCount: 0 };
    assert.equal(line.visibleCount(state), 0);
    assert.equal(line.format(0, 0, translate), "0 loaded");
    assert.equal(line.format(0, 1, translate), "0 in library");
});

test("a count that has not arrived yet says nothing", () => {
    assert.equal(line.visibleCount({ tabIndex: 0 }), line.NONE);
    assert.equal(line.visibleCount({ tabIndex: 1, libraryCount: undefined }), line.NONE);
    assert.equal(line.visibleCount({ tabIndex: 0, browseCount: -1 }), line.NONE);
    assert.equal(line.visibleCount(), line.NONE);
});

test("the number is an integer, whatever the model hands over", () => {
    assert.equal(line.visibleCount({ tabIndex: 0, browseCount: 12.7 }), 12);
    assert.equal(line.visibleCount({ tabIndex: 0, browseCount: "8" }), 8);
});

test("barText() is the one expression the three panels call", () => {
    const state = { tabIndex: 0, browseCount: 32, libraryCount: 1, translate };
    assert.equal(line.barText(state), "32 loaded");
    assert.equal(line.barText({ ...state, tabIndex: 1 }), "1 in library");
    assert.equal(line.barText({ ...state, settingsMode: true }), "");
    // A panel passes its own numbers and the same translator; nothing else.
    assert.equal(line.barText({ tabIndex: 0, browseCount: 0, translate }), "0 loaded");
});

test("the Browse wording is the one the results row used", () => {
    // Same key and the same singular/plural pair, so the move cannot change
    // what the reader sees; es and en are both exercised.
    assert.equal(i18n.tn("en", "header.loaded", 1), "1 loaded");
    assert.equal(i18n.tn("en", "header.loaded", 7), "7 loaded");
    assert.equal(i18n.tn("es", "header.loaded", 1), "1 cargado");
    assert.equal(i18n.tn("es", "header.loaded", 7), "7 cargados");
});
