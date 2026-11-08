"use strict";

// Guard for the Fase R1 UI tokenization: no view may hard-code a radius,
// spacing, motion duration or font size instead of asking `qs.Commons.Style`,
// and no view may hard-code a colour instead of reading the Omarchy theme
// (`qs.app.Colors`).
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");

const lint = require("../tools/lint-style.js");

test("no raw style tokens in the UI", () => {
    const { violations } = lint.check();
    assert.deepEqual(violations, [],
        "raw tokens found:\n" + JSON.stringify(violations, null, 2));
});

test("no colour literals in the UI", () => {
    const { violations } = lint.check();
    const colors = violations.filter((v) => v.prop === "color");
    assert.deepEqual(colors, [],
        "colour literals found:\n" + JSON.stringify(colors, null, 2));
});

test("a hex colour literal is flagged", () => {
    const found = lint.scanText('Rectangle { color: "#1a1714" }', "modules/x.qml");
    assert.equal(found.length, 1, JSON.stringify(found));
    assert.equal(found[0].prop, "color");
    assert.match(found[0].value, /#1a1714/);
});

test("short, long and alpha hex colours are all flagged", () => {
    for (const literal of ["#fff", "#08080a", "#ff1a1714"])
        assert.equal(
            lint.scanText(`Rectangle { color: "${literal}" }`, "modules/x.qml").length, 1,
            literal + " was not flagged");
});

test("a Qt.rgba() literal is flagged", () => {
    const found = lint.scanText("Rectangle { color: Qt.rgba(1, 1, 1, 0.07) }", "modules/x.qml");
    assert.equal(found.length, 1, JSON.stringify(found));
});

test("theme roles and transparent pass", () => {
    assert.deepEqual(
        lint.scanText('Rectangle { color: Colors.background }', "modules/x.qml"), []);
    assert.deepEqual(
        lint.scanText('Rectangle { color: Util.alpha(Colors.text, 0.07) }', "modules/x.qml"), []);
    assert.deepEqual(
        lint.scanText('Rectangle { color: "transparent" }', "modules/x.qml"), []);
});

test("a colour inside a comment is not a violation", () => {
    assert.deepEqual(
        lint.scanText('// warm ground: #1a1714', "modules/x.qml"), []);
});

test("style-ignore exempts a documented colour", () => {
    assert.deepEqual(
        lint.scanText('Rectangle { color: "#1a1714" } // style-ignore — sample',
            "modules/x.qml"), []);
});
