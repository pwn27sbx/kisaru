"use strict";

// Layout guard for modules/anime/components/DetailView.qml meta bar (Finding 2).
//
// Packing episode count, subtitle label, Skip chip, Folder chip, HideSwitch,
// and Last-watched badge into a single 34px RowLayout at 550px panel width
// crowded controls edge-to-edge. The meta strip must split into two clean rows:
//   Row 1 (metaInfoRow):    episode count + subtitle label (elided) + last-watched badge
//   Row 2 (metaActionsRow): skip chip + folder chip + spacer + HideSwitch
//
// Run with: node --test tests/anime_detail_meta.test.js

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");

test("anime DetailView splits meta info and action controls into two balanced rows", () => {
    const qml = fs.readFileSync(
        path.join(ROOT, "modules/anime/components/DetailView.qml"),
        "utf8"
    );

    const colIdx = qml.indexOf("id: metaColumn");
    const row1Idx = qml.indexOf("id: metaInfoRow");
    const row2Idx = qml.indexOf("id: metaActionsRow");
    assert.ok(colIdx >= 0, "expected metaColumn ColumnLayout for the meta bar");
    assert.ok(row1Idx > colIdx, "expected metaInfoRow inside metaColumn");
    assert.ok(row2Idx > row1Idx, "expected metaActionsRow below metaInfoRow");

    const row1Block = qml.slice(row1Idx, row2Idx);
    const row2End = qml.indexOf("id: epList", row2Idx);
    const row2Block = qml.slice(row2Idx, row2End);

    // Row 1 holds episode count, elided subtitle label, and last-watched badge.
    assert.match(row1Block, /count\.episode/, "episode count belongs in metaInfoRow");
    assert.match(row1Block, /anime\.subtitles/, "subtitle label belongs in metaInfoRow");
    assert.match(row1Block, /last\.ep/, "last-watched badge belongs in metaInfoRow");
    assert.ok(!row1Block.includes("skipToggleButton"), "skip chip must not crowd metaInfoRow");
    assert.ok(!row1Block.includes("folderButton"), "folder chip must not crowd metaInfoRow");

    // Row 2 holds action controls with explicit spacing and a flexible spacer.
    assert.match(row2Block, /id:\s*skipToggleButton/, "skip chip belongs in metaActionsRow");
    assert.match(row2Block, /id:\s*folderButton/, "folder chip belongs in metaActionsRow");
    assert.match(row2Block, /HideSwitch\s*\{/, "HideSwitch belongs in metaActionsRow");
    assert.match(row2Block, /spacing:\s*Style\.spacing\./, "metaActionsRow must use a Style.spacing token");

    // Qt 6 RowLayout computes row implicitHeight from children's implicit/Layout.preferred
    // sizes. Rectangle defaults to implicitWidth=0, implicitHeight=0, so chips inside
    // metaInfoRow/metaActionsRow must set implicitWidth & implicitHeight (not raw width/height),
    // ensuring Row 2 keeps its height even when HideSwitch is hidden.
    const lastWatchedBlock = row1Block.slice(row1Block.indexOf("// Last-watched badge"));
    const skipBlock = row2Block.slice(
        row2Block.indexOf("id: skipToggleButton"),
        row2Block.indexOf("id: folderButton")
    );
    const folderBlock = row2Block.slice(
        row2Block.indexOf("id: folderButton"),
        row2Block.indexOf("id: hideSwitch")
    );

    for (const [name, block] of [
        ["last-watched badge", lastWatchedBlock],
        ["skipToggleButton", skipBlock],
        ["folderButton", folderBlock],
    ]) {
        assert.match(block, /\bimplicitWidth\s*:/, `${name} must bind implicitWidth for RowLayout`);
        assert.match(block, /\bimplicitHeight\s*:/, `${name} must bind implicitHeight so Row 2 keeps height when HideSwitch is hidden`);
        assert.doesNotMatch(block, /^\s*(?:width|height)\s*:/m, `${name} must not set raw width/height inside RowLayout`);
    }
});
