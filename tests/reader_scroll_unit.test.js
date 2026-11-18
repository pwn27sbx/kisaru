"use strict";

// Tests for components/reader_scroll.js — the manga long-strip decisions that
// used to live inline in modules/manga/components/ReaderView.qml.
//
// What they pin (root cause proved on 2026-11-17, see the Kisaru vault plan
// 2026-11-17-reader-scroll-and-slow-pages):
//   - the scroll range is [originY, originY + contentHeight - height], not
//     [0, contentHeight - height]: Qt moves originY when a page above the
//     viewport changes height, and the old clamp parked the reader above its
//     real end (9/13 jumped to 4/13);
//   - the placeholder ratio is learned once per chapter, not on every load;
//   - a failed page is retried once by itself with a cache-buster the proxy
//     ignores, and never automatically when it is an offline file.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const wheel = require("../components/wheel_scroll.js");
const reader = require("../components/reader_scroll.js");

const ROOT = path.resolve(__dirname, "..");
const READER_QML = path.join(ROOT, "modules/manga/components/ReaderView.qml");
const HARNESS_QML = path.join(ROOT, "tests/reader_scroll_harness/Harness.qml");

function view(fields) {
    return Object.assign({ contentY: 0, contentHeight: 20000, height: 1000, originY: 0, count: 13 }, fields);
}

// ── wheelPlan ────────────────────────────────────────────────────────────────

test("a wheel notch moves inside [originY, originY + range]", () => {
    const plan = reader.wheelPlan(wheel, view({ contentY: -4000, originY: -6000 }), -120, 0, 2, 4);
    assert.deepEqual(plan, { kind: "move", y: -3760, settling: false });
});

test("the end of the strip is originY + range, not contentHeight - height", () => {
    // contentHeight 20000, height 1000, originY -6000: the real end is 13000.
    // The old clamp stopped at 19000 - 0 = 19000 only when originY was 0, and
    // with a negative originY it parked 6000 px above the end.
    const plan = reader.wheelPlan(wheel, view({ contentY: 12900, originY: -6000 }), -120, 0, 2, 12);
    assert.deepEqual(plan, { kind: "move", y: 13000, settling: false });
});

test("scrolling up stops at originY, which may be negative", () => {
    const plan = reader.wheelPlan(wheel, view({ contentY: -5900, originY: -6000 }), 120, 0, 2, 0);
    assert.deepEqual(plan, { kind: "move", y: -6000, settling: false });
});

test("at the estimated end with pages left, it steps to the next page", () => {
    const plan = reader.wheelPlan(wheel, view({ contentY: 12950, originY: -6000 }), -120, 0, 2, 8);
    assert.deepEqual(plan, { kind: "page", index: 9 });
});

test("on the last page the end clamp holds instead of stepping", () => {
    const plan = reader.wheelPlan(wheel, view({ contentY: 12950, originY: -6000 }), -120, 0, 2, 12);
    assert.deepEqual(plan, { kind: "move", y: 13000, settling: false });
});

test("scrolling up at the end never steps forward", () => {
    const plan = reader.wheelPlan(wheel, view({ contentY: 13000, originY: -6000 }), 120, 0, 2, 8);
    assert.deepEqual(plan, { kind: "move", y: 12760, settling: false });
});

test("while laying out it moves without the upper clamp, floored at originY", () => {
    const v = view({ contentY: -500, originY: -600, contentHeight: 800, height: 1000 });
    assert.deepEqual(reader.wheelPlan(wheel, v, -120, 0, 2, 0), { kind: "move", y: -260, settling: true });
    assert.deepEqual(reader.wheelPlan(wheel, v, 120, 0, 2, 0), { kind: "move", y: -600, settling: true });
});

test("an empty list ignores the wheel", () => {
    const v = view({ count: 0, contentHeight: 0 });
    assert.deepEqual(reader.wheelPlan(wheel, v, -120, 0, 2, 0), { kind: "ignore" });
});

test("a touchpad swipe uses the pixel delta with the same sign", () => {
    const plan = reader.wheelPlan(wheel, view({ contentY: 1000 }), 0, -25, 2, 1);
    assert.deepEqual(plan, { kind: "move", y: 1050, settling: false });
});

// ── pageAt ───────────────────────────────────────────────────────────────────

test("pageAt keeps the laid-out answer, else the last page clamped to the chapter", () => {
    assert.equal(reader.pageAt(4, 9, 13), 4);
    assert.equal(reader.pageAt(-1, 9, 13), 9);
    assert.equal(reader.pageAt(-1, 20, 13), 12);
    assert.equal(reader.pageAt(-1, 3, 0), 0);
});

// ── shouldLearnRatio ─────────────────────────────────────────────────────────

test("the ratio is learned once per chapter", () => {
    assert.equal(reader.shouldLearnRatio(false, 8.3), true);
    assert.equal(reader.shouldLearnRatio(true, 8.3), false);
});

test("an impossible ratio is never learned", () => {
    assert.equal(reader.shouldLearnRatio(false, 0.05), false);
    assert.equal(reader.shouldLearnRatio(false, 60), false);
    assert.equal(reader.shouldLearnRatio(false, NaN), false);
});

// ── retry of a failed page ───────────────────────────────────────────────────

const PROXY = "http://127.0.0.1:5150/image?url=https%3A%2F%2Fcdn.example%2Fp8.webp&chapter=c&page=8";

test("pageSource adds the &kr=<n> cache-buster to a proxied page from the first retry", () => {
    assert.equal(reader.pageSource(PROXY, 0), PROXY);
    assert.equal(reader.pageSource(PROXY, 1), PROXY + "&kr=1");
    assert.equal(reader.pageSource(PROXY, 3), PROXY + "&kr=3");
});

test("pageSource never decorates an offline file or an empty url", () => {
    assert.equal(reader.pageSource("file:///home/u/ch/001.jpg", 2), "file:///home/u/ch/001.jpg");
    assert.equal(reader.pageSource("", 1), "");
    assert.equal(reader.pageSource(undefined, 1), "");
});

test("a proxied page is retried by itself only once", () => {
    assert.equal(reader.canAutoRetry(PROXY, 0), true);
    assert.equal(reader.canAutoRetry(PROXY, 1), false);
    assert.equal(reader.canAutoRetry(PROXY, 2), false);
});

test("an offline file is never retried by itself", () => {
    assert.equal(reader.canAutoRetry("file:///home/u/ch/001.jpg", 0), false);
    assert.equal(reader.canAutoRetry("", 0), false);
});

test("bumpAttempt returns a new map and counts per page", () => {
    const first = {};
    const second = reader.bumpAttempt(first, 8);
    assert.notEqual(second, first);
    assert.deepEqual(first, {});
    assert.deepEqual(second, { 8: 1 });
    assert.deepEqual(reader.bumpAttempt(second, 8), { 8: 2 });
    assert.equal(reader.attemptOf(second, 8), 1);
    assert.equal(reader.attemptOf(second, 3), 0);
    assert.equal(reader.attemptOf(null, 3), 0);
});

test("the automatic retry waits about three seconds", () => {
    assert.equal(reader.AUTO_RETRY_DELAY_MS, 3000);
});

// ── the harness mirrors the real delegate, and the old compensation is gone ──

function delegateHeightBinding(text) {
    const start = text.indexOf("delegate: Item {");
    assert.ok(start >= 0, "no `delegate: Item {` found");
    const after = text.slice(start);
    const m = /\n(\s*)height:([\s\S]*?)\n(?=\s*\n|\s*\/\/|\s*[A-Za-z_.]+\s*[:{])/.exec(after);
    assert.ok(m, "no delegate height binding found");
    return m[2].replace(/\s+/g, " ").trim();
}

test("the harness delegate height binding matches ReaderView.qml", () => {
    const real = delegateHeightBinding(fs.readFileSync(READER_QML, "utf8"));
    const copy = delegateHeightBinding(fs.readFileSync(HARNESS_QML, "utf8"));
    assert.match(real, /pageImg\.status === Image\.Ready/);
    assert.equal(copy, real);
});

test("ReaderView no longer compensates height changes by hand", () => {
    const text = fs.readFileSync(READER_QML, "utf8");
    assert.doesNotMatch(text, /_lastHeight/);
    const delegate = text.slice(text.indexOf("delegate: Item {"));
    assert.doesNotMatch(delegate, /onHeightChanged/);
});

test("ReaderView takes its wheel, page and ratio decisions from reader_scroll.js", () => {
    const text = fs.readFileSync(READER_QML, "utf8");
    assert.match(text, /import "\.\.\/\.\.\/\.\.\/components\/reader_scroll\.js" as ReaderScroll/);
    assert.match(text, /ReaderScroll\.wheelPlan\(/);
    assert.match(text, /ReaderScroll\.pageAt\(/);
    assert.match(text, /ReaderScroll\.shouldLearnRatio\(/);
    assert.match(text, /ReaderScroll\.pageSource\(/);
    assert.match(text, /ReaderScroll\.canAutoRetry\(/);
});

test("the harness imports the real scroll modules by relative path", () => {
    const text = fs.readFileSync(HARNESS_QML, "utf8");
    assert.match(text, /import "\.\.\/\.\.\/components\/wheel_scroll\.js" as WheelScroll/);
    assert.match(text, /import "\.\.\/\.\.\/components\/reader_scroll\.js" as ReaderScroll/);
});
