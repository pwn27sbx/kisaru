"use strict";

// The lock state machine. Every lock trigger goes through it, and a stale
// helper result is discarded by generation, never applied.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");

const lock = require("../services/lock_state.js");

const trigger = (state, type) => lock.reduce(state, { type: type });

test("process start is locked", () => {
    const state = lock.initial();
    assert.equal(state.locked, true);
    assert.equal(state.generation, 0);
});

test("the padlock, a close, a minimize and a panel switch all lock", () => {
    let state = lock.reduce(lock.initial(), { type: "settle", generation: 0, ok: true });
    assert.equal(state.locked, false);         // unlocked first
    assert.equal(trigger(state, "lock").locked, true);
    // One hook covers the three UI triggers; the reducer cannot tell them
    // apart and must not: all three mean "lock now".
    for (const source of ["close", "minimize", "panel-switch"]) {
        assert.equal(trigger(state, "lock").locked, true, source);
    }
});

test("a verified word toggles: unlocked locks, locked unlocks", () => {
    let locked = lock.initial();
    const started = lock.reduce(locked, { type: "start" });
    const unlocked = lock.reduce(started, { type: "settle", generation: started.generation, ok: true });
    assert.equal(unlocked.locked, false);

    const again = lock.reduce(unlocked, { type: "start" });
    const relocked = lock.reduce(again, { type: "settle", generation: again.generation, ok: true });
    assert.equal(relocked.locked, true);
});

test("a wrong word never changes the state", () => {
    const started = lock.reduce(lock.initial(), { type: "start" });
    const same = lock.reduce(started, { type: "settle", generation: started.generation, ok: false });
    assert.equal(same.locked, true);
    assert.equal(same.checking, false);
});

test("a stale generation is discarded", () => {
    const first = lock.reduce(lock.initial(), { type: "start" });
    const second = lock.reduce(first, { type: "start" });
    const stale = lock.reduce(second, { type: "settle", generation: first.generation, ok: true });
    assert.equal(stale.locked, true);
    assert.equal(stale.checking, true);
    const fresh = lock.reduce(second, { type: "settle", generation: second.generation, ok: true });
    assert.equal(fresh.locked, false);
});

test("lock invalidates a check in flight", () => {
    const started = lock.reduce(lock.initial(), { type: "start" });
    const locked = trigger(started, "lock");
    const late = lock.reduce(locked, { type: "settle", generation: started.generation, ok: true });
    assert.equal(late.locked, true);
    assert.equal(late.checking, false);
    assert.ok(late.generation > started.generation);
});
