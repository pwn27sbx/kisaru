"use strict";

// The idle fade's wiring, checked where the shell really uses it.
//
// The fade broke once for a whole round and nobody noticed until the owner
// did: no commit had touched it, the shell had simply been started while a
// temporary `IDLE_OPACITY = 1.0` edit was in the tree, and an imported JS
// module is never re-evaluated after the file is restored. These probes make
// that class of loss visible from the test run instead of from the screen:
//
//   - the slot opacity must come from Panels.opacityForSlot (the real path),
//     not from a hand-assembled state in shell.qml;
//   - each panel must keep publishing `pointerInside` from a HoverHandler,
//     or the fade silently pins itself to "pointer is inside";
//   - IDLE_OPACITY must be the owner's 0.15 and must be declared in exactly
//     one place, so a leftover override cannot survive in another file.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const read = (rel) => fs.readFileSync(path.join(ROOT, rel), "utf8");

const PANELS = [
    "modules/manga/MangaReader.qml",
    "modules/anime/AnimePanel.qml",
    "modules/novel/NovelReader.qml",
];

test("shell.qml takes every slot's opacity from the tested function", () => {
    const shell = read("shell.qml");
    for (const slot of ["mangaSlot", "novelSlot", "animeSlot"]) {
        assert.match(
            shell,
            new RegExp(`opacity:\\s*Panels\\.opacityForSlot\\(\\s*${slot}\\s*\\)`),
            `${slot} must bind its opacity to Panels.opacityForSlot`
        );
    }
    // The inline assembly is what made the real path untestable; it must not
    // come back.
    assert.doesNotMatch(shell, /Panels\.opacityFor\s*\(/);
});

test("every panel keeps publishing pointerInside from a HoverHandler", () => {
    for (const file of PANELS) {
        const qml = read(file);
        assert.match(qml, /HoverHandler\s*\{\s*id:\s*pointer\s*\}/, `${file}: no HoverHandler`);
        assert.match(
            qml,
            /readonly property bool pointerInside:\s*pointer\.hovered/,
            `${file}: pointerInside no longer follows the pointer`
        );
    }
});

test("IDLE_OPACITY is the owner's value, declared in exactly one place", () => {
    const panels = read("services/panels.js");
    assert.match(panels, /var IDLE_OPACITY = 0\.15;/, "the idle opacity is not 0.15");

    const offenders = [];
    const walk = (dir) => {
        for (const entry of fs.readdirSync(path.join(ROOT, dir), { withFileTypes: true })) {
            if (entry.name === ".git" || entry.name === "node_modules") continue;
            const rel = dir ? `${dir}/${entry.name}` : entry.name;
            if (entry.isDirectory()) {
                walk(rel);
                continue;
            }
            if (!/\.(js|qml)$/.test(entry.name)) continue;
            // The runtime files only: a test asserting the constant is not an
            // override, and probe scripts do not reach the shell.
            if (rel === "services/panels.js" || rel.startsWith("tests/")) continue;
            if (/IDLE_OPACITY\s*=/.test(read(rel))) offenders.push(rel);
        }
    };
    walk("");
    assert.deepEqual(offenders, [], "IDLE_OPACITY is being assigned outside services/panels.js");
});

test("the fade is animated with a Motion token", () => {
    const shell = read("shell.qml");
    const fade = /Behavior on opacity\s*\{\s*NumberAnimation\s*\{\s*duration:\s*Motion\.\w+\s*\}\s*\}/;
    assert.match(shell, fade);
});
