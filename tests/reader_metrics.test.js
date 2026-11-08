"use strict";

// The novel reader's measure and the panel animation.
//
// The panel animates its implicitWidth between 550 (compact) and the screen
// width (fullscreen). The chapter used to take its measure from the animated
// width, so the last part of the animation (below ~768 px) reflowed the whole
// chapter on every frame — the owner's "lag al final". The measure now comes
// from the panel's target width: one reflow per toggle, never per frame.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const metrics = require("../services/reader_metrics.js");

const ROOT = path.resolve(__dirname, "..");
const read = (rel) => fs.readFileSync(path.join(ROOT, rel), "utf8");

test("the measure is capped at 720 and keeps a 24 px gutter on each side", () => {
    assert.equal(metrics.MAX_MEASURE, 720);
    assert.equal(metrics.SIDE_GUTTER, 48);
});

test("a wide panel keeps the 720 measure", () => {
    for (const width of [2880, 1920, 1400, 1000, 800, 769, 768])
        assert.equal(metrics.columnWidth(width), 720, "at " + width + " px");
});

test("a narrow panel takes what is left after the gutters", () => {
    assert.equal(metrics.columnWidth(767), 719);
    assert.equal(metrics.columnWidth(550), 502);
    assert.equal(metrics.columnWidth(100), 52);
    assert.equal(metrics.columnWidth(48), 0);
});

test("a width that leaves no room never goes negative", () => {
    for (const width of [47, 10, 0, -10, NaN, undefined, null])
        assert.equal(metrics.columnWidth(width), 0, "at " + width);
});

// The animation runs 2880 -> 550 px. Above 768 every frame yields the same
// measure, so the chapter relayouts only when the panel crosses that line —
// and the reader is never handed the intermediate widths.
test("the animation crosses the measure exactly once", () => {
    const frames = [2880, 2400, 2000, 1600, 1200, 1000, 900, 800, 769, 768];
    const measures = frames.map(metrics.columnWidth);
    assert.equal(new Set(measures).size, 1, "the measure changed before the line");
    assert.equal(metrics.columnWidth(550), 502);
});

test("narrowing applies at once, even while the panel is still wide", () => {
    // Fullscreen -> compact: the target is 502, the live panel is anywhere.
    assert.equal(metrics.shownMeasure(720, 502, 2880), 502);
    assert.equal(metrics.shownMeasure(720, 502, 900), 502);
    assert.equal(metrics.shownMeasure(720, 502, 550), 502);
});

test("widening waits until the panel can hold the text", () => {
    // Compact -> fullscreen: 502 -> 720 needs a live panel of 768.
    assert.equal(metrics.shownMeasure(502, 720, 550), 502, "clipped at 550");
    assert.equal(metrics.shownMeasure(502, 720, 767), 502, "clipped at 767");
    assert.equal(metrics.shownMeasure(502, 720, 768), 720, "fits exactly");
    assert.equal(metrics.shownMeasure(502, 720, 2880), 720);
});

// Review R3-ConstrainedPanelZeroMeasure: the first measure must not wait for
// room the live panel will never have, or a small screen gets a zero-width
// column and no chapter at all.
test("a constrained panel gets the largest measure that fits", () => {
    // A 550 px target on a 400 px panel: the initial 0 becomes 400 - 48.
    assert.equal(metrics.shownMeasure(0, 502, 400), 352);
    assert.equal(metrics.shownMeasure(0, 720, 400), 352);
    // The panel shrinks under the shown measure: take what still fits.
    assert.equal(metrics.shownMeasure(352, 502, 300), 252);
    // And it never asks for more than the panel holds.
    for (const live of [300, 400, 550, 700]) {
        const shown = metrics.shownMeasure(352, 720, live);
        assert.ok(shown <= metrics.columnWidth(live),
            `a ${live} px panel would show ${shown}`);
    }
});

test("an unchanged measure is never reapplied", () => {
    assert.equal(metrics.shownMeasure(720, 720, 2880), 720);
    assert.equal(metrics.shownMeasure(502, 502, 550), 502);
});

// Review R3-MeasureBindingBypassesGate: while _measure was a binding on
// contentWidth it took the wider value the moment the mode toggled, skipping
// shownMeasure() and clipping the chapter inside the still-narrow panel.
test("the shown measure is not a live binding on the content width", () => {
    const reader = read("modules/novel/components/ReaderView.qml");
    assert.ok(!/property real _measure: ReaderMetrics\.columnWidth/.test(reader),
        "_measure is bound to contentWidth again, bypassing the widening gate");
    assert.match(reader, /property real _measure: 0/);
    assert.match(reader, /_measure = next/, "applyMeasure is the only writer");
});

test("the reader reads the target width, not the animated width", () => {
    const reader = read("modules/novel/components/ReaderView.qml");
    assert.match(reader, /property real contentWidth: width/,
        "the reader lost its independent content width");
    assert.match(reader, /_targetMeasure: ReaderMetrics\.columnWidth\(contentWidth\)/,
        "the target measure is not derived from the content width");
    assert.match(reader, /ReaderMetrics\.shownMeasure\(_measure, _targetMeasure, width\)/,
        "the shown measure does not go through the rule");
    assert.match(reader, /width: readerView\._measure/,
        "the column still follows the animated width");
});

test("the panel hands the reader its target width", () => {
    const panel = read("modules/novel/NovelReader.qml");
    assert.match(panel, /readonly property real targetWidth: fullscreen/,
        "the panel has no stable target width");
    assert.match(panel, /: 550/, "the compact target width is gone");
    assert.match(panel, /implicitWidth: targetWidth/);
    assert.ok((panel.match(/contentWidth: root\.targetWidth/g) || []).length >= 2,
        "a reader instance does not receive the target width");
});

test("a width change re-anchors the reading position", () => {
    const reader = read("modules/novel/components/ReaderView.qml");
    assert.match(reader, /onContentWidthChanged: readerView\.applyMeasure\(\)/,
        "the width change does not capture the anchor");
    assert.match(reader, /onWidthChanged: readerView\.applyMeasure\(\)/);
    assert.match(reader, /function captureAnchor\(/);
    assert.match(reader, /function restoreAnchor\(/);
    assert.match(reader, /onImplicitHeightChanged: readerView\.restoreAnchor\(\)/,
        "the restore is not tied to the layout pass");
});
