"use strict";

// The health poll and the respawn timer must back off and stop.
//
// HealthPoller asked every 150 ms forever, and the restart timer re-armed
// every 3 s with no cap, so a broken venv produced ~20 requests per second
// and an endless respawn loop (audit 2026-11-06, findings 15 and 16). The
// backoff math lives in plain JS so it is testable without a Wayland session.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const backoff = require("../services/health_backoff.js");

const ROOT = path.resolve(__dirname, "..");
const read = (rel) => fs.readFileSync(path.join(ROOT, rel), "utf8");

test("the first health attempt uses the initial delay", () => {
    assert.equal(backoff.nextDelay(0, 150, 5000), 150);
});

test("each attempt doubles the delay up to the ceiling", () => {
    assert.equal(backoff.nextDelay(1, 150, 5000), 300);
    assert.equal(backoff.nextDelay(2, 150, 5000), 600);
    assert.equal(backoff.nextDelay(5, 150, 5000), 4800);
    assert.equal(backoff.nextDelay(6, 150, 5000), 5000);
    assert.equal(backoff.nextDelay(40, 150, 5000), 5000);
});

test("attempts are exhausted only at the cap", () => {
    assert.equal(backoff.exhausted(0, 40), false);
    assert.equal(backoff.exhausted(39, 40), false);
    assert.equal(backoff.exhausted(40, 40), true);
});

test("the respawn backoff starts at 3 s and stops at 60 s", () => {
    assert.equal(backoff.nextDelay(0, 3000, 60000), 3000);
    assert.equal(backoff.nextDelay(2, 3000, 60000), 12000);
    assert.equal(backoff.nextDelay(10, 3000, 60000), 60000);
});

test("HealthPoller is a Timer, not a singleton", () => {
    const qml = read("services/HealthPoller.qml");
    // The Timer contract is what the services instantiate; a Singleton root
    // with `interval`/`running`/`onTriggered` cannot load at all.
    assert.match(qml, /^Timer \{/m);
    assert.doesNotMatch(qml, /^Singleton \{/m);
    assert.doesNotMatch(qml, /^pragma Singleton/m);
});

test("HealthPoller backs off, has a cap and a timeout", () => {
    const qml = read("services/HealthPoller.qml");
    assert.match(qml, /maxAttempts/);
    assert.match(qml, /HealthBackoff\.nextDelay/);
    assert.match(qml, /xhr\.timeout/);
    assert.match(qml, /ontimeout/);
    assert.match(qml, /signal failed/);
});

test("Http sets a timeout and reports it", () => {
    const qml = read("services/Http.qml");
    assert.match(qml, /xhr\.timeout/);
    assert.match(qml, /ontimeout/);
    assert.match(qml, /"timeout"/);
});

test("every backend caps its respawns", () => {
    for (const service of ["services/Anime.qml", "services/Manga.qml", "services/Novel.qml"]) {
        const qml = read(service);
        assert.match(qml, /restartCount/, service);
        assert.match(qml, /maxRestarts/, service);
        assert.match(qml, /HealthBackoff\.nextDelay/, service);
    }
});
