"use strict";

// Regression guard for the dark flash on hover (owner, 2026-11-27).
//
// In QML `"transparent"` is BLACK at alpha 0, so a `ColorAnimation` between a
// colour and `"transparent"` walks RGB through black: the row turns darker than
// the background before reaching its hover colour. The off colour must be the
// hover colour itself with alpha 0 (`Colors.clear(...)`), so the animation only
// fades the same hue in.
//
// The static half rejects `"transparent"` in a conditional colour binding; the
// render half animates both patterns offscreen, composites each sample over the
// row background and checks that no frame of the fixed one is darker than both
// endpoints while the old one does dip (the negative control).
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const { runHarness, hasQs } = require("./meta_row_harness/run.js");

const ROOT = path.resolve(__dirname, "..");

// `Commons/` and `Ui/` are symlinks into /usr/share/omarchy: Omarchy's own
// code, which follows its own conventions.
const DIRS = ["app", "components", "modules", "services"];
const FILES = ["shell.qml"];

function qmlFiles() {
    const out = FILES.map((f) => path.join(ROOT, f)).filter((f) => fs.existsSync(f));
    function walk(dir) {
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
            const full = path.join(dir, entry.name);
            if (entry.isDirectory()) walk(full);
            else if (entry.name.endsWith(".qml")) out.push(full);
        }
    }
    for (const dir of DIRS) {
        const full = path.join(ROOT, dir);
        if (fs.existsSync(full)) walk(full);
    }
    return out;
}

// Walks back to the `color:` that owns the value so a multi-line ternary is
// read as one binding, then flags it only when the colour is conditional.
function scanText(text, rel) {
    const found = [];
    const lines = text.split("\n");
    lines.forEach((line, i) => {
        if (!line.includes('"transparent"')) return;
        if (line.includes("// color-ignore")) return;
        let statement = line;
        for (let back = 1; back <= 6 && !/\bcolor\s*:/.test(statement); back++) {
            if (i - back < 0) break;
            statement = lines[i - back] + " " + statement;
        }
        const at = statement.search(/\bcolor\s*:/);
        if (at < 0) return;                       // not a colour value
        const binding = statement.slice(at);
        if (!binding.includes("?")) return;       // a static colour: harmless
        found.push(`${rel}:${i + 1}: ${line.trim()}`);
    });
    return found;
}

function violations() {
    const found = [];
    for (const file of qmlFiles()) {
        const rel = path.relative(ROOT, file);
        found.push(...scanText(fs.readFileSync(file, "utf8"), rel));
    }
    return found;
}

test("a conditional colour never falls back to \"transparent\"", () => {
    assert.deepEqual(violations(), [],
        "\"transparent\" is black at alpha 0: animating a colour to it flashes dark. "
        + "Use Colors.clear(<the hover colour>) instead:\n" + violations().join("\n"));
});

test("Colors.clear() is the alpha-0 form of the given colour", () => {
    const qml = fs.readFileSync(path.join(ROOT, "app/Colors.qml"), "utf8");
    assert.match(qml, /function\s+clear\s*\(/,
        "app/Colors.qml must expose clear(base) as the \"off\" colour");
    const body = qml.slice(qml.indexOf("function clear"));
    assert.match(body.slice(0, 400), /Util\.alpha\s*\(\s*base\s*,\s*0\s*\)/,
        "Colors.clear(base) must be Util.alpha(base, 0), not a black transparent");
});

test("the scanner flags a conditional colour and leaves a static one alone", () => {
    assert.equal(scanText('Rectangle { color: hovered ? Colors.x : "transparent" }', "x.qml").length, 1);
    assert.equal(scanText('        color: "transparent"\n        border.width: 1', "x.qml").length, 0);
    assert.equal(scanText('        color: pressed\n            ? Colors.a\n            : "transparent"', "x.qml").length, 1);
});

function fields(result) {
    const out = {};
    for (const part of result.split(/\s+/).slice(2)) {
        const [k, v] = part.split("=");
        if (k) out[k] = v;
    }
    return out;
}

test("no animated hover frame is darker than both endpoints", async (t) => {
    if (!hasQs()) return t.skip("qs not installed");
    const r = await runHarness({ scenario: "flash" });
    assert.ok(r.result, `no RESULT line (qs exit ${r.code}):\n${r.log.slice(-25).join("\n")}`);
    const f = fields(r.result);
    const floor = Math.min(Number(f.bgLum), Number(f.targetLum));
    assert.ok(Number(f.newMin) >= floor - 0.004,
        `the fixed fade dips below both endpoints: ${r.result}`);
    assert.ok(Number(f.span) > 0.005,
        `the fade never ran: ${r.result}`);
    assert.ok(Number(f.oldMin) < floor - 0.01,
        `the "transparent" control did not flash, so this theme cannot judge it: ${r.result}`);
    assert.equal(r.pass, true, r.result);
});
