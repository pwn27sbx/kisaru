"use strict";

// Guard against QML singleton/type name collisions between Kisaru's
// `services/*.qml` and Omarchy's shared shell modules (`Commons` and `Ui`).
//
// Omarchy 4.5.0-3 added `singleton I18n` to `/usr/share/omarchy/shell/Commons/qmldir`,
// which shadowed Kisaru's `services/I18n.qml` wherever `import qs.Commons`
// followed `import qs.services`. Keeping Kisaru's service names disjoint from
// Omarchy's exports prevents silent shadowing across future Omarchy updates.
//
// Skips cleanly when `/usr/share/omarchy/shell` is absent (e.g. GitHub CI).
// Run with: node --test tests/singleton_collisions.test.js

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const OMARCHY_SHELL = "/usr/share/omarchy/shell";
const OMARCHY_QMDIRS = [
    path.join(OMARCHY_SHELL, "Commons", "qmldir"),
    path.join(OMARCHY_SHELL, "Ui", "qmldir"),
];

function parseQmldirTypes(text) {
    const names = new Set();
    for (const raw of text.split("\n")) {
        const line = raw.trim();
        if (!line || line.startsWith("#") || line.startsWith("module ")) continue;
        const parts = line.split(/\s+/);
        if (parts[0] === "singleton" && parts[1]) {
            names.add(parts[1]);
        } else if (parts[0] && parts[2] && parts[2].endsWith(".qml")) {
            names.add(parts[0]);
        }
    }
    return names;
}

test("no services/*.qml name collides with Omarchy Commons or Ui exports", (t) => {
    const existing = OMARCHY_QMDIRS.filter((p) => fs.existsSync(p));
    if (existing.length === 0) {
        t.skip("Omarchy shell qmldir not installed on this host");
        return;
    }

    const omarchyTypes = new Map();
    for (const qmldir of existing) {
        const label = path.basename(path.dirname(qmldir));
        for (const name of parseQmldirTypes(fs.readFileSync(qmldir, "utf8"))) {
            omarchyTypes.set(name, label);
        }
    }

    const servicesDir = path.join(ROOT, "services");
    const collisions = [];
    for (const entry of fs.readdirSync(servicesDir, { withFileTypes: true })) {
        if (!entry.isFile() || !entry.name.endsWith(".qml")) continue;
        const typeName = entry.name.slice(0, -4);
        if (omarchyTypes.has(typeName)) {
            collisions.push(`services/${entry.name} collides with qs.${omarchyTypes.get(typeName)}.${typeName}`);
        }
    }

    assert.deepEqual(collisions, []);
});
