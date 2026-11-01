"use strict";

// The header cell's paint contract (owner, rounds 5-7), pinned per state.
// Round 6 removed the full-height switch: every header cell is full height in
// all three panels, so the state machine is only current/hovered/pressed.
// Round 7 (A-8) added the weight role (selected is bold) and the badge rule.
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const cell = require("../services/header_cell.js");

const style = (over) => cell.cellStyle(
    Object.assign({ current: false, hovered: false, pressed: false }, over));

test("the selected cell is a solid accent with the dark bold label", () => {
    // Owner, round 6 for the fill; A-8 for the weight: the selected label is
    // bold everywhere, so the active state is not fill-only.
    assert.deepEqual(style({ current: true }), { fill: "solid", label: "on", strong: true });
});

test("an unselected cell is plain and never bold", () => {
    assert.deepEqual(style({}), { fill: "none", label: "muted", strong: false });
});

test("hover tints the unselected cells and never overrides the solid selected one", () => {
    assert.equal(style({ hovered: true }).fill, cell.FILL.HOVER);
    assert.equal(style({ hovered: true }).label, cell.LABEL.MUTED);
    assert.equal(style({ hovered: true }).strong, false);
    // A selected cell stays selected while the pointer is on it.
    assert.equal(style({ current: true, hovered: true }).fill, cell.FILL.SOLID);
    assert.equal(style({ current: true, hovered: true }).label, cell.LABEL.ON);
});

test("pressed is its own fill in both cases", () => {
    assert.equal(style({ current: true, pressed: true }).fill, cell.FILL.PRESSED);
    assert.equal(style({ pressed: true }).fill, cell.FILL.PRESSED);
    assert.equal(style({ pressed: true }).label, cell.LABEL.MUTED);
    // Pressing the current cell keeps its label reading: it is still the one
    // that is selected, even under the pointer.
    assert.equal(style({ current: true, pressed: true }).strong, true);
});

test("a badge only exists when there is something to count", () => {
    // Owner, A-8: "Library" alone beats "Library 0".
    assert.equal(cell.showBadge(0), false);
    assert.equal(cell.showBadge(-1), false);   // "this tab carries no badge"
    assert.equal(cell.showBadge(undefined), false);
    assert.equal(cell.showBadge(1), true);
    assert.equal(cell.showBadge(132), true);
});

test("an empty state is a plain cell, never a crash", () => {
    const s = cell.cellStyle();
    assert.equal(s.fill, cell.FILL.NONE);
    assert.equal(s.label, cell.LABEL.MUTED);
});

test("the header and the filter chips share one cell contract", () => {
    // The active filter chip is the reference look; if the header stops using
    // this module, the two drift apart silently.
    const qml = fs.readFileSync(path.resolve(__dirname, "../components/PanelHeader.qml"), "utf8");
    assert.match(qml, /HeaderCell\.cellStyle\(/);
    assert.match(qml, /import "\.\.\/services\/header_cell\.js" as HeaderCell/);
    // Every selected state reads the same recipe: the header cell, the shared
    // chip (filter chips and SUB/DUB) and the layout cell.
    for (const [file, symbol] of [
        ["components/Chip.qml", "chip"],
        ["components/ViewModeChip.qml", "chip"],
    ]) {
        const text = fs.readFileSync(path.resolve(__dirname, "../", file), "utf8");
        assert.match(text, /HeaderCell\.cellStyle\(/, `${file}: the selected state has no shared recipe`);
        assert.match(text, /HeaderCell\.LABEL\.ON \? Colors\.on_primary/, `${file}: the selected label is not the on-accent colour`);
        assert.match(text, /font\.bold: [a-z_]+\._style\.strong/, `${file}: the selected label is not bold`);
        assert.ok(!text.includes("selected: true"), `${file}: still leans on Button's theme-coloured selected label`);
    }
    // The round-5/6 options are gone: one header for all three panels.
    assert.doesNotMatch(qml, /fullHeightCells/);
    assert.doesNotMatch(qml, /showHoverRing|hoverRing/);
});
