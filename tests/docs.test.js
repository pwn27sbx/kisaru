"use strict";

// Documentation that points at files that exist.
//
// The README and the migration tool's help cited a plan file that is not in
// the repository, and the README did not say how to run the migration (audit
// 2026-11-06, finding 31).
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const read = (rel) => fs.readFileSync(path.join(ROOT, rel), "utf8");

const MISSING_PLAN = "2026-11-01-kisaru-rename-migration-plan.md";

test("the README does not cite a plan file that is not in the repo", () => {
    assert.ok(!read("README.md").includes(MISSING_PLAN));
});

test("the migration tool's help does not cite it either", () => {
    assert.ok(!read("tools/migrate_to_kisaru.py").includes(MISSING_PLAN));
});

test("the README shows how to run the migration", () => {
    const text = read("README.md");
    assert.match(text, /tools\/migrate_to_kisaru\.py/);
    assert.match(text, /--apply/);
    assert.match(text, /no escribe nada|muestra el plan/);
});

test("the README does not promise chapter downloads", () => {
    const text = read("README.md");
    assert.ok(!/descargar capítulos y leerlos/.test(text));
    assert.match(text, /todavía no está disponible/);
    assert.match(text, /https:\/\/github\.com\/pwn27sbx\/kisaru\/issues\/1/);
});
