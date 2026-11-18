"use strict";

// Tests for components/wheel_scroll.js — the reader wheel arithmetic.
//
// The bug this pins: a touchpad sends only pixelDelta, and the first version
// negated it, so a two-finger scroll went backwards. Mouse (angleDelta) and
// touchpad (pixelDelta) must move the same way for the same gesture.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");

const wheel = require("../components/wheel_scroll.js");

test("stepOf() reads the mouse angle when present", () => {
    assert.equal(wheel.stepOf(120, 0), 120);
    assert.equal(wheel.stepOf(-120, 0), -120);
});

test("stepOf() falls back to the touchpad pixels", () => {
    assert.equal(wheel.stepOf(0, 25), 25);
    assert.equal(wheel.stepOf(0, -25), -25);
});

test("a wheel notch down moves the page forward, notch up moves it back", () => {
    assert.equal(wheel.nextContentY(1000, -120, 0, 2, 5000), 1240);
    assert.equal(wheel.nextContentY(1000, 120, 0, 2, 5000), 760);
});

test("a touchpad swipe follows the same direction as the wheel", () => {
    // Swipe up (content should move down) carries a negative pixelDelta.
    assert.equal(wheel.nextContentY(1000, 0, -25, 2, 5000), 1050);
    assert.equal(wheel.nextContentY(1000, 0, 25, 2, 5000), 950);
});

test("the factor multiplies, and 1 is the raw step", () => {
    assert.equal(wheel.nextContentY(500, -120, 0, 1, 5000), 620);
    assert.equal(wheel.nextContentY(500, -120, 0, 4, 5000), 980);
});

test("it stops at both ends instead of overshooting", () => {
    assert.equal(wheel.nextContentY(10, 120, 0, 2, 5000), 0);
    assert.equal(wheel.nextContentY(4990, -120, 0, 2, 5000), 5000);
});

test("a missing or impossible limit becomes zero, never negative", () => {
    assert.equal(wheel.nextContentY(300, -120, 0, 2, -5), 0);
    assert.equal(wheel.nextContentY(300, -120, 0, 2, undefined), 0);
});

// The manga long strip has a real scroll range of [originY, originY + range]:
// when a page above the viewport changes height, Qt moves originY and keeps
// contentY still. Clamping to [0, limit] parked the reader `originY` pixels
// above its real end (9/13 jumped to 4/13). `minY` is the lower bound.

test("a sixth argument moves the lower bound to minY", () => {
    assert.equal(wheel.nextContentY(-900, 120, 0, 2, 4000, -1000), -1000);
    assert.equal(wheel.nextContentY(-800, 120, 0, 2, 4000, -1000), -1000);
    assert.equal(wheel.nextContentY(-500, 120, 0, 2, 4000, -1000), -740);
});

test("a negative limit with a negative minY clamps inside both", () => {
    assert.equal(wheel.nextContentY(-3000, -120, 0, 2, -2500, -6000), -2760);
    assert.equal(wheel.nextContentY(-2600, -120, 0, 2, -2500, -6000), -2500);
    assert.equal(wheel.nextContentY(-5900, 120, 0, 2, -2500, -6000), -6000);
});

test("a limit below minY, or a missing one, collapses onto minY", () => {
    assert.equal(wheel.nextContentY(-3000, -120, 0, 2, -7000, -6000), -6000);
    assert.equal(wheel.nextContentY(-3000, -120, 0, 2, undefined, -6000), -6000);
});

test("five arguments keep the old [0, limit] clamp", () => {
    assert.equal(wheel.nextContentY(-300, 120, 0, 2, 5000), 0);
    assert.equal(wheel.nextContentY(4990, -120, 0, 2, 5000, undefined), 5000);
    assert.equal(wheel.nextContentY(300, -120, 0, 2, -5, undefined), 0);
});
