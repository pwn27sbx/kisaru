"use strict";

// The header cell's paint contract (owner, round 5), pinned per state.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const cell = require("../services/header_cell.js");

const style = (over) => cell.cellStyle(
    Object.assign({ current: false, hovered: false, pressed: false, fullHeight: true }, over));

test("selected cell wears the chip; anything else is plain", () => {
    assert.deepEqual(style({ current: true }), { fill: "selected", label: "selected", ring: true, hoverRing: false });
    assert.deepEqual(style({}), { fill: "none", label: "muted", ring: false, hoverRing: false });
    assert.deepEqual(style({ fullHeight: false }), { fill: "none", label: "muted", ring: false, hoverRing: false });
});

test("hover tints, beats the selected fill, and rings only where it always did", () => {
    assert.equal(style({ current: true, hovered: true }).fill, cell.FILL.HOVER);
    assert.equal(style({ current: true, hovered: true }).ring, true);
    assert.equal(style({ hovered: true }).hoverRing, false);
    assert.equal(style({ hovered: true, fullHeight: false }).hoverRing, true);
});

test("pressed beats everything, and keeps the ring", () => {
    const s = style({ current: true, hovered: true, pressed: true });
    assert.equal(s.fill, cell.FILL.PRESSED);
    assert.equal(s.ring, true);
});

test("the other headers keep their plain label and no selected ring", () => {
    assert.equal(style({ current: true, fullHeight: false }).label, cell.LABEL.TEXT);
    assert.equal(style({ current: true, fullHeight: false }).ring, false);
});

test("the delegate reads this module instead of re-deriving the states", () => {
    const qml = fs.readFileSync(path.resolve(__dirname, "../components/PanelHeader.qml"), "utf8");
    assert.match(qml, /HeaderCell\.cellStyle\(/);
    assert.match(qml, /import "\.\.\/services\/header_cell\.js" as HeaderCell/);
});
