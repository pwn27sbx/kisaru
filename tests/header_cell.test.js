"use strict";

// The header cell's paint contract (owner, rounds 5-6), pinned per state.
// Round 6 removed the full-height switch: every header cell is full height in
// all three panels, so the state machine is only current/hovered/pressed.
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const cell = require("../services/header_cell.js");

const style = (over) => cell.cellStyle(
    Object.assign({ current: false, hovered: false, pressed: false }, over));

test("the selected cell wears the chip: selected fill, selected colour, ring", () => {
    assert.deepEqual(style({ current: true }), { fill: "selected", label: "selected", showRing: true });
});

test("an unselected cell is plain", () => {
    assert.deepEqual(style({}), { fill: "none", label: "muted", showRing: false });
});

test("hover tints and beats the selected fill, and keeps the ring", () => {
    assert.equal(style({ current: true, hovered: true }).fill, cell.FILL.HOVER);
    assert.equal(style({ current: true, hovered: true }).showRing, true);
    assert.equal(style({ hovered: true }).showRing, false);
});

test("pressed beats everything, and keeps the ring", () => {
    const s = style({ current: true, hovered: true, pressed: true });
    assert.equal(s.fill, cell.FILL.PRESSED);
    assert.equal(s.showRing, true);
});

test("an empty state is a plain cell, never a crash", () => {
    const s = cell.cellStyle();
    assert.equal(s.fill, cell.FILL.NONE);
    assert.equal(s.label, cell.LABEL.MUTED);
    assert.equal(s.showRing, false);
});

test("the header and the filter chips share one cell contract", () => {
    // The active filter chip is the reference look; if the header stops using
    // this module, the two drift apart silently.
    const qml = fs.readFileSync(path.resolve(__dirname, "../components/PanelHeader.qml"), "utf8");
    assert.match(qml, /HeaderCell\.cellStyle\(/);
    assert.match(qml, /import "\.\.\/services\/header_cell\.js" as HeaderCell/);
    // The round-5/6 options are gone: one header for all three panels.
    assert.doesNotMatch(qml, /fullHeightCells/);
    assert.doesNotMatch(qml, /showHoverRing|hoverRing/);
});
