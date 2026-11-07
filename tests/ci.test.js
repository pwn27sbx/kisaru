"use strict";

// The CI workflow is the only check that runs on a clean machine: the local
// suites run against an installed Omarchy. There was no CI at all (audit
// 2026-11-06, finding 8), so these tests pin the contract the workflow must
// keep: run on every change to main, stay read-only, pin every action to a
// commit (a tag can move), and run the same three suites a contributor runs.
//
// They read the YAML as text: no parser is installed and the file is small.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const WORKFLOW = ".github/workflows/ci.yml";
const read = () => fs.readFileSync(path.join(ROOT, WORKFLOW), "utf8");

test("the workflow exists and runs on push and pull requests to main", () => {
    const text = read();
    assert.match(text, /^on:/m);
    assert.match(text, /^\s+push:/m);
    assert.match(text, /^\s+pull_request:/m);
    // A branch filter per trigger, so a branch push cannot skip CI.
    assert.equal((text.match(/^\s+- main$/gm) || []).length, 2);
});

test("the workflow token is read-only", () => {
    const text = read();
    assert.match(text, /^permissions:\s*\n\s+contents:\s*read\s*$/m);
    assert.ok(!/write/.test(text), "the workflow asks for a write permission");
});

test("every action is pinned to a commit SHA with a version comment", () => {
    const text = read();
    const uses = text.split("\n").filter((line) => /^\s*-\s*uses:/.test(line));
    assert.ok(uses.length > 0, "the workflow uses no action");
    for (const line of uses) {
        assert.match(line, /^\s*-\s*uses:\s+[^\s@]+@[0-9a-f]{40}\s+#\s+v\d+\.\d+\.\d+\s*$/,
            `unpinned action: ${line.trim()}`);
    }
});

test("the test job runs the node, lint and python suites", () => {
    const text = read();
    assert.match(text, /^\s{2}test:\s*$/m);
    assert.match(text, /node --test/);
    assert.match(text, /node tools\/lint-style\.js/);
    assert.match(text, /node tools\/lint-i18n\.js/);
    assert.match(text, /pip install -r requirements-dev\.txt/);
    assert.match(text, /python -m unittest discover -s tests -p "test_\*\.py"/);
});

test("the runner toolchain matches the project", () => {
    const text = read();
    assert.match(text, /node-version:\s*["']?22["']?/);
    assert.match(text, /python-version:\s*["']?3\.14["']?/);
});

test("the workflow uses no secrets", () => {
    assert.ok(!/secrets\./.test(read()));
});
