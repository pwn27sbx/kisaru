"use strict";

// Contrast of the secondary text that lives inside a card's info band.
//
// The theme's muted role is ~1.3:1 on surface_container_high; the old views
// dimmed it again with opacity. The shared token mixes most of the way to the
// title's tone, so the status stays readable (>= 4.5:1) while the title stays
// the strongest line.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");

const contrast = require("../services/contrast.js");
const fs = require("node:fs");
const path = require("node:path");

// The owner's measured Omarchy theme (2026-11-05).
const BACKGROUND = "#2d353b";
const FOREGROUND = "#d3c6aa";
const MUTED = "#475258";

const HIGH = contrast.mix(BACKGROUND, FOREGROUND, 0.08);      // #3a4144
const CONTAINER = contrast.mix(BACKGROUND, FOREGROUND, 0.05); // #353c41

test("the shared secondary token clears 4.5:1 on both card bands", () => {
    const token = contrast.cardSecondary(MUTED, FOREGROUND);
    assert.ok(contrast.ratio(token, HIGH) >= 4.5,
        `status on the high band is ${contrast.ratio(token, HIGH).toFixed(2)}:1`);
    assert.ok(contrast.ratio(token, CONTAINER) >= 4.5,
        `status on the container band is ${contrast.ratio(token, CONTAINER).toFixed(2)}:1`);
});

test("the title stays stronger than the status", () => {
    const token = contrast.cardSecondary(MUTED, FOREGROUND);
    assert.ok(contrast.ratio(FOREGROUND, HIGH) > contrast.ratio(token, HIGH) + 0.5,
        "the title and the status read at the same strength");
});

test("the old muted-plus-opacity treatment is the measured failure", () => {
    // Muted at 45% over the band reproduces the owner's ~1.5:1.
    const old = contrast.mix(HIGH, MUTED, 0.45);
    assert.ok(contrast.ratio(old, HIGH) < 2,
        `the old status was ${contrast.ratio(old, HIGH).toFixed(2)}:1`);
});
const ROOT = path.resolve(__dirname, "..");
const read = (rel) => fs.readFileSync(path.join(ROOT, rel), "utf8");

test("every card secondary line reads the shared token", () => {
    const colors = read("app/Colors.qml");
    assert.match(colors,
        /card_secondary: mix\(Commons\.Color\.muted, Commons\.Color\.foreground, 0\.9\)/);

    const bar = read("components/CoverProgressBar.qml");
    assert.match(bar, /color: root\.started \? Colors\.on_surface : Colors\.card_secondary/);
    assert.match(bar, /opacity: root\.started \? 0\.85 : 1/,
        "the unstarted label is dimmed a second time");

    const row = read("components/ListRow.qml");
    assert.match(row, /datumColor: Colors\.card_secondary/);
    assert.match(row, /color: root\.progressActive \? Colors\.primary : Colors\.card_secondary/);
    assert.match(row, /opacity: root\.progressActive \? 0\.9 : 1/,
        "the list progress is dimmed a second time");

    assert.match(read("components/FolderCard.qml"), /color: Colors\.card_secondary/);
    assert.match(read("components/FolderListRow.qml"), /color: Colors\.card_secondary/);
    assert.match(read("components/CoverCard.qml"), /color: Colors\.card_secondary/);
});

test("muted UI outside the card bands is not raised", () => {
    const colors = read("app/Colors.qml");
    // The role itself stays the theme's muted colour; only the card token
    // mixes toward the title.
    assert.match(colors, /on_surface_variant: Commons\.Color\.muted/);
    assert.match(colors, /muted: Commons\.Color\.muted/);
    // Inactive tabs and other chrome keep on_surface_variant/muted.
    const header = read("components/PanelHeader.qml");
    assert.match(header, /Colors\.muted/);
    assert.ok(!header.includes("card_secondary"),
        "the header was raised with the card token");
});
test("the folder toolbar labels are readable, not hover-only", () => {
    const action = read("components/FolderAction.qml");
    assert.match(action, /text: root\.label/, "the action has no visible label");
    assert.match(action, /color: Colors\.on_surface/, "the label does not use the title tone");
    assert.match(action, /implicitWidth: row\.implicitWidth/,
        "the label is not part of the control's width");
    // The label is the title tone on the card surface: 6.63:1.
    assert.ok(contrast.ratio(FOREGROUND, CONTAINER) >= 4.5);
});
