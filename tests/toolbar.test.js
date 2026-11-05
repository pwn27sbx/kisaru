"use strict";

// The folder toolbar's rules: the switch says the state, and the three-dot
// menu owns rename and delete. The QML reads these keys, so the labels and the
// action order live in one place instead of being copied into three views.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const toolbar = require("../services/toolbar.js");

const ROOT = path.resolve(__dirname, "..");
const read = (rel) => fs.readFileSync(path.join(ROOT, rel), "utf8");

test("the switch says the state: Oculta when hidden, Ocultar when not", () => {
    assert.equal(toolbar.hideKey(true), "folder.hiddenMark");
    assert.equal(toolbar.hideKey(false), "folder.hide");
});

test("the three-dot menu holds rename then delete, delete in danger", () => {
    const actions = toolbar.menuActions();
    assert.deepEqual(actions.map((action) => action.value), ["rename", "delete"]);
    assert.equal(actions[0].key, "folder.renameShort");
    assert.equal(actions[1].key, "folder.deleteShort");
    assert.equal(actions[0].danger, false);
    assert.equal(actions[1].danger, true);
});

test("one shared switch: borderless, state-labelled, same in Detail and folders", () => {
    const switcher = read("components/HideSwitch.qml");
    assert.match(switcher, /Toolbar\.hideKey\(root\.checked\)/);
    assert.ok(!/border\.(color|width)/.test(switcher), "the switch still draws a box");
    assert.ok(!/color:\s*Colors\.surface/.test(switcher), "the switch still has a filled box");
    for (const file of [
        "modules/manga/components/DetailView.qml",
        "modules/novel/components/DetailView.qml",
        "modules/anime/components/DetailView.qml",
    ]) {
        const qml = read(file);
        assert.match(qml, /HideSwitch\s*\{/, `${file}: no Detail switch`);
        assert.ok(!/HideSwitch\s*\{[^}]*label:/.test(qml),
            `${file}: the Detail passes a label instead of the shared state`);
    }
});

test("the folder header uses the three-dot menu, not loose action boxes", () => {
    for (const file of [
        "modules/manga/components/LibraryView.qml",
        "modules/novel/components/LibraryView.qml",
        "modules/anime/components/LibraryView.qml",
    ]) {
        const qml = read(file);
        assert.match(qml, /OverflowMenu\s*\{/, `${file}: no three-dot menu`);
        assert.match(qml, /Toolbar\.menuActions\(\)/, `${file}: the menu actions are copied`);
        assert.ok(!qml.includes("FolderAction"), `${file}: the loose action boxes are back`);
        assert.ok(!qml.includes("folder.hiddenMark"), `${file}: the separate hidden tag is back`);
    }
});
