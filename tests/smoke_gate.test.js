"use strict";

// The adoption smoke probe is a debug tool, not start-up work.
//
// `OmarchySmoke` instantiated a Button and logged on every launch, including
// production (audit 2026-11-06, finding 27). It must now be opt-in.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const shell = fs.readFileSync(path.join(ROOT, "shell.qml"), "utf8");

test("the smoke probe needs an explicit debug switch", () => {
    assert.match(shell, /KISARU_SMOKE/);
    assert.match(shell, /active:\s*\(Quickshell\.env\("KISARU_SMOKE"\)/);
});

test("the smoke probe is created only by the gated loader", () => {
    const creations = [...shell.matchAll(/OmarchySmoke\s*\{/g)];
    assert.equal(creations.length, 1, "only the gated Component creates it");
    const loader = shell.slice(shell.indexOf("KISARU_SMOKE") - 200, shell.indexOf("KISARU_SMOKE") + 400);
    assert.match(loader, /sourceComponent/);
});
