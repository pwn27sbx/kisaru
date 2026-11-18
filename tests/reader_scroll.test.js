"use strict";

// Headless regression test for the manga long-strip reader.
//
// Runs tests/reader_scroll_harness (the real wheel_scroll.js and
// reader_scroll.js inside a ListView like ReaderView's, fed by a delayed image
// server) under `qs` with the offscreen platform. It skips where Quickshell is
// not installed, as in CI.
//
//   scroll  the 2026-11-17 bug: scrolling down jumped up (9/13 -> 4/13) and
//           could end on a blank 13/13. Before the fix it gave
//           `RESULT FAIL badUpMoves=27 blankFrames=1 endPage=10`.
//   retry   a page whose first fetch answers 502 loads on the automatic retry
//           (with `&kr=1`), a page that fails twice loads on the click, and an
//           offline file is never retried by itself.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");

const { runHarness, hasQs } = require("./reader_scroll_harness/run.js");

test("scrolling down a slow chapter never jumps up and ends on the last page", async (t) => {
    if (!hasQs()) return t.skip("qs not installed");
    const r = await runHarness({ scenario: "scroll" });
    assert.ok(r.result, `no RESULT line (qs exit ${r.code}):\n${r.log.slice(-20).join("\n")}`);
    assert.equal(r.result, "RESULT PASS badUpMoves=0 blankFrames=0 endPage=13");
});

test("a failed page is retried once by itself, then on click", async (t) => {
    if (!hasQs()) return t.skip("qs not installed");
    const r = await runHarness({ scenario: "retry" });
    assert.ok(r.result, `no RESULT line (qs exit ${r.code}):\n${r.log.slice(-20).join("\n")}`);
    assert.ok(r.pass, r.result);
    const forPage = (p) => r.requests.filter((q) => new RegExp(`[?&]url=${p}(&|$)`).test(q));
    assert.deepEqual(forPage("p0"), ["/image?url=p0"]);
    assert.deepEqual(forPage("p1"), ["/image?url=p1", "/image?url=p1&kr=1"]);
    assert.deepEqual(forPage("p2"), ["/image?url=p2", "/image?url=p2&kr=1", "/image?url=p2&kr=2"]);
});
