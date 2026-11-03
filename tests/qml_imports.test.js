"use strict";

// Every QML file must import the module that owns the singleton it uses.
//
// This exists because one real bug shipped: components/ViewModeToggle.qml wrote
// `UiPrefs.setViewMode(...)` without `import qs.services`, so the click threw a
// ReferenceError and the grid/list toggle silently did nothing. qmllint said
// nothing, the panel loaded, and the captures were produced by editing
// settings.json instead of by clicking.
//
// Comments are stripped before looking, because prose may name a symbol it does
// not use ("callers pass I18n.t(...)").

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const DIRS = ["components", "modules"];

// singleton -> the import that provides it
const OWNERS = {
    UiPrefs: "import qs.services",
    I18n: "import qs.services",
    Colors: "import qs.app",
    Style: "import qs.Commons",
};

function qmlFiles(dir) {
    const out = [];
    for (const entry of fs.readdirSync(path.join(ROOT, dir), { withFileTypes: true })) {
        const rel = `${dir}/${entry.name}`;
        if (entry.isDirectory()) out.push(...qmlFiles(rel));
        else if (entry.name.endsWith(".qml")) out.push(rel);
    }
    return out;
}

function stripComments(text) {
    return text
        .replace(/\/\*[\s\S]*?\*\//g, "")
        .split("\n")
        .map((line) => line.replace(/\/\/.*$/, ""))
        .join("\n");
}

test("a QML file imports whoever owns the singleton it uses", () => {
    const problems = [];
    for (const file of DIRS.flatMap(qmlFiles)) {
        const source = stripComments(fs.readFileSync(path.join(ROOT, file), "utf8"));
        for (const [symbol, needed] of Object.entries(OWNERS)) {
            // `Symbol.` in code, not the word in prose.
            const uses = new RegExp(`\\b${symbol}\\s*\\.`).test(source);
            if (uses && !source.includes(needed))
                problems.push(`${file}: uses ${symbol} without "${needed}"`);
        }
    }
    assert.deepEqual(problems, []);
});

test("the settings page can reach the preference the layout row writes", () => {
    // The switch moved from the header to the settings page (§33); the lesson of
    // the original bug stays: the component that writes the preference imports
    // the service that owns it.
    const settings = stripComments(
        fs.readFileSync(path.join(ROOT, "components/PanelSettings.qml"), "utf8"));
    assert.match(settings, /import qs\.services/);
    assert.match(settings, /signal layoutSelected/);
});
