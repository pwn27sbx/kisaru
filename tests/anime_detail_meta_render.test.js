"use strict";

// Regression guard for the anime Detail meta bar (owner, 2026-11-27).
//
// The bar must always show its action row under row 1: Skip intro, Folder and
// Hide. `metaActionsRow.visible` used to OR its own children's `visible`, and
// `Item.visible` reads the EFFECTIVE value, so a row that starts hidden reads
// false forever and the whole second row (folder + hide) never appeared for any
// source. This test renders the real DetailView offscreen with a library entry
// and measures the two rows; the static half guards the pattern that caused it.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const { runHarness, hasQs } = require("./meta_row_harness/run.js");

const ROOT = path.resolve(__dirname, "..");

function fields(result) {
    const out = {};
    for (const part of result.split(/\s+/).slice(2)) {
        const [k, v] = part.split("=");
        if (k) out[k] = v;
    }
    return out;
}

test("anime Detail renders the Skip/Folder/Hide row for a library entry", async (t) => {
    if (!hasQs()) return t.skip("qs not installed");
    const r = await runHarness({ scenario: "meta" });
    assert.ok(r.result, `no RESULT line (qs exit ${r.code}):\n${r.log.slice(-25).join("\n")}`);
    const f = fields(r.result);
    assert.equal(f.row2H !== "0", true, `row 2 did not render: ${r.result}`);
    assert.ok(Number(f.row2H) >= 18, `row 2 is too short: ${r.result}`);
    assert.ok(Number(f.metaBarH) >= Number(f.row1H) + Number(f.row2H),
        `meta bar does not contain both rows: ${r.result}`);
    assert.equal(f.skip, "1", `Skip intro chip is not visible: ${r.result}`);
    assert.equal(f.folder, "1", `Folder chip is not visible: ${r.result}`);
    assert.equal(f.hide, "1", `Hide switch is not visible: ${r.result}`);
    // Row 1 must keep what it already showed.
    assert.equal(f.count, "1", `episode count left row 1: ${r.result}`);
    assert.equal(f.last, "1", `last-watched badge left row 1: ${r.result}`);
});

// `visible: <id>.visible` where <id> lives in the same file reads the item's
// effective visibility: while the parent is hidden it is false, and a row that
// gates itself on its own children can then never come back (the 2026-11-27
// bug). A parent's/sibling widget's property is fine; a local id is not.
test("no QML item hides itself behind a local item's visible property", () => {
    const DIRS = ["app", "components", "modules", "services"];

    function walk(dir, out) {
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
            const full = path.join(dir, entry.name);
            if (entry.isDirectory()) walk(full, out);
            else if (entry.name.endsWith(".qml")) out.push(full);
        }
        return out;
    }

    const files = [path.join(ROOT, "shell.qml")];
    for (const dir of DIRS) {
        const full = path.join(ROOT, dir);
        if (fs.existsSync(full)) walk(full, files);
    }

    const violations = [];
    for (const file of files) {
        if (!fs.existsSync(file)) continue;
        const rel = path.relative(ROOT, file);
        const lines = fs.readFileSync(file, "utf8").split("\n");
        const ids = new Set();
        for (const line of lines) {
            const m = /^\s*(?:readonly\s+|default\s+|required\s+)*id\s*:\s*([A-Za-z_]\w*)/.exec(line);
            if (m) ids.add(m[1]);
        }
        lines.forEach((line, i) => {
            if (line.includes("// visible-ignore")) return;
            const code = line.replace(/\/\/.*$/, "");
            if (!/^\s*visible\s*:/.test(code)) return;
            for (const id of ids) {
                if (new RegExp(`(^|[^\\w.$])${id}\\.visible\\b`).test(code)) {
                    violations.push(`${rel}:${i + 1}: ${line.trim()}`);
                    break;
                }
            }
        });
    }

    assert.deepEqual(violations, [],
        "an item reads a local item's effective `visible` in its own visible binding; "
        + "ask the condition instead (2026-11-27 meta-row bug):\n" + violations.join("\n"));
});
