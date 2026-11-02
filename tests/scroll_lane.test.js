"use strict";

// The scrollbar's lane and the "reduce motion" rule, checked where they are
// used (owner §30).
//
// The bar used to ride on top of the last column's title. Reserving the lane is
// a per-view decision — every grid, list and the reader needs the same gutter —
// so these probes keep a view from quietly forgetting it: a file that attaches
// the shared bar must also import the metrics and reserve the space.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const read = (rel) => fs.readFileSync(path.join(ROOT, rel), "utf8");

const metrics = require(path.join(ROOT, "services/scroll_metrics.js"));
const motion = require(path.join(ROOT, "services/motion_prefs.js"));

const SCROLLING_VIEWS = [
    "modules/anime/components/BrowseView.qml",
    "modules/anime/components/LibraryView.qml",
    "modules/anime/components/DetailView.qml",
    "modules/manga/components/BrowseView.qml",
    "modules/manga/components/LibraryView.qml",
    "modules/manga/components/DetailView.qml",
    "modules/manga/components/ReaderView.qml",
    "modules/novel/components/BrowseView.qml",
    "modules/novel/components/LibraryView.qml",
];

test("the lane is wider than the handle, so the handle never sits on content", () => {
    assert.ok(metrics.LANE > metrics.THICKNESS,
        `lane ${metrics.LANE} must be wider than the bar ${metrics.THICKNESS}`);
    assert.ok(metrics.THICKNESS > 0, "the bar must be visible");
});

test("the bar waits about a second before hiding", () => {
    assert.equal(metrics.IDLE_MS, 1000);
    assert.ok(metrics.FADE_MS > 0 && metrics.FADE_MS <= 300, "a short fade");
});

test("every scrolling view attaches the shared bar", () => {
    for (const file of SCROLLING_VIEWS) {
        const source = read(file);
        assert.ok(source.includes("ScrollBar.vertical: StyledScrollBar"),
            `${file} must use the shared StyledScrollBar`);
        assert.ok(!/ScrollBar\.vertical:\s*ScrollBar\s*\{/.test(source),
            `${file} still builds its own scrollbar, which cannot follow the lane`);
    }
});

test("every scrolling view reserves the lane for the bar", () => {
    // Since §32 the lane is part of the panel gutter (services/Gutter.qml), so a
    // view reserves it by taking the gutter on both sides — one constant, not a
    // number per file.
    for (const file of SCROLLING_VIEWS) {
        const source = read(file);
        assert.ok(source.includes("Gutter."), `${file} must take the panel gutter`);
    }
    const gutter = read("services/Gutter.qml");
    assert.match(gutter, /right:\s*Style\.spacing\.lg\s*\+\s*Style\.space\(Metrics\.LANE\)/,
        "the right gutter must include the scrollbar lane");
});

test("the toggle has no frame and takes its height from the chips", () => {
    const toggle = read("components/ViewModeToggle.qml");
    // A frame is a background fill and a border; the owner removed both.
    assert.ok(!/surface_container|border\.width|border\.color/.test(toggle),
        "the toggle must not draw a box around its cells");
    const chip = read("components/ViewModeChip.qml");
    // The chip's height is the body line plus the control padding, exactly like
    // components/Chip.qml; that is what makes the row line up.
    // Owner §32: the tool bar gives every control one height, so the cell takes
    // it when it is given and falls back to the chip formula when it is not.
    assert.match(chip, /cellHeight\s*>\s*0/, "the cell must accept the tool bar's height");
    assert.ok(read("components/ToolBar.qml").includes("cellHeight: root.controlHeight"),
        "the tool bar must hand its one height to the toggle");
});

test("reduced motion comes from the override or GTK's switch", () => {
    assert.equal(motion.reduced("1", "gtk-enable-animations=false"), true);
    assert.equal(motion.reduced("", "gtk-enable-animations=false"), true);
    assert.equal(motion.reduced("", "[Settings]\ngtk-enable-animations = FALSE\n"), true);
    assert.equal(motion.reduced("", "[Settings]\ngtk-enable-animations=true"), false);
    assert.equal(motion.reduced("", ""), false);
    assert.equal(motion.reducedFromGtk("gtk-theme-name=Adwaita"), false);
});

test("the bar honours that preference instead of always fading", () => {
    const bar = read("components/StyledScrollBar.qml");
    assert.ok(bar.includes("MotionPrefs.reduced"),
        "the fade must be disabled when the desktop asks for reduced motion");
    assert.ok(bar.includes("Metrics.LANE"), "the hover target must cover the lane");
});
