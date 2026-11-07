"use strict";

// Cover decoding and dead translation keys.
//
// Covers were decoded at full size and scaled down by Qt, so a panel holding
// dozens of posters paid for megabytes it never showed; and five keys stayed
// in both language tables with no reader (audit 2026-11-06, findings 26 and
// 30).
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const i18n = require("../services/i18n.js");

const ROOT = path.resolve(__dirname, "..");
const read = (rel) => fs.readFileSync(path.join(ROOT, rel), "utf8");

test("the poster card decodes at its display size", () => {
    const qml = read("components/CoverCard.qml");
    assert.match(qml, /sourceSize\.width/);
    assert.match(qml, /sourceSize\.height/);
});

test("the list row decodes at its display size", () => {
    const qml = read("components/ListRow.qml");
    assert.match(qml, /sourceSize\.width/);
    assert.match(qml, /sourceSize\.height/);
});

test("the dead translation keys are gone from both tables", () => {
    const dead = [
        "state.loading",
        "privacy.lock",
        "error.server",
        "anime.library.title",
        "empty.library"
    ];
    for (const lang of ["es", "en"]) {
        for (const key of dead) {
            assert.equal(i18n.tables[lang][key], undefined, `${lang}: ${key}`);
        }
    }
});

test("the two tables still have the same keys", () => {
    assert.deepEqual(
        Object.keys(i18n.tables.es).sort(),
        Object.keys(i18n.tables.en).sort());
});
