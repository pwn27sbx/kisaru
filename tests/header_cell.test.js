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

test("the selected cell is a solid accent with the on-accent label", () => {
    // Owner, round 6: the tint-plus-ring reading is gone.
    assert.deepEqual(style({ current: true }), { fill: "solid", label: "on", showRing: false });
});

test("an unselected cell is plain", () => {
    assert.deepEqual(style({}), { fill: "none", label: "muted", showRing: false });
});

test("hover tints the unselected cells and never overrides the solid selected one", () => {
    assert.equal(style({ hovered: true }).fill, cell.FILL.HOVER);
    assert.equal(style({ hovered: true }).label, cell.LABEL.MUTED);
    // A selected cell stays selected while the pointer is on it.
    assert.equal(style({ current: true, hovered: true }).fill, cell.FILL.SOLID);
    assert.equal(style({ current: true, hovered: true }).label, cell.LABEL.ON);
});

test("pressed is its own fill in both cases", () => {
    assert.equal(style({ current: true, pressed: true }).fill, cell.FILL.PRESSED);
    assert.equal(style({ pressed: true }).fill, cell.FILL.PRESSED);
    assert.equal(style({ pressed: true }).label, cell.LABEL.MUTED);
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
