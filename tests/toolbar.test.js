"use strict";

// The top zone's one toolbar (owner, §32) and the menu logic behind it.
//
// The rule the owner made mandatory is "one left edge and one right edge": the
// filter menu's left edge is the first card's left edge, the toggle's right edge
// is the last card's right edge, and every control in row 2 shares one height.
// A source test cannot measure pixels; it can refuse the shapes that break the
// rule — a per-control margin, a second menu implementation, a view that quietly
// brings back its own chips row — which is what this file does. The pixel proof
// lives in the report.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const read = (rel) => fs.readFileSync(path.join(ROOT, rel), "utf8");
const menu = require(path.join(ROOT, "services/filter_menu.js"));

const PANELS = [
    "modules/manga/MangaReader.qml",
    "modules/anime/AnimePanel.qml",
    "modules/novel/NovelReader.qml",
];

const VIEWS = [
    "modules/manga/components/BrowseView.qml",
    "modules/manga/components/LibraryView.qml",
    "modules/anime/components/BrowseView.qml",
    "modules/anime/components/LibraryView.qml",
    "modules/novel/components/BrowseView.qml",
    "modules/novel/components/LibraryView.qml",
];

test("every panel has exactly one tool bar, and it is the shared one", () => {
    for (const file of PANELS) {
        const source = read(file);
        const uses = (source.match(/ToolBar\s*\{/g) || []).length;
        assert.equal(uses, 1, `${file} must place one ToolBar`);
        assert.ok(!/SearchField\s*\{/.test(source), `${file} still places its own search field`);
    }
    const names = { "modules/manga/MangaReader.qml": "manga",
                    "modules/anime/AnimePanel.qml": "anime",
                    "modules/novel/NovelReader.qml": "novel" };
    for (const [file, panel] of Object.entries(names)) {
        assert.match(read(file), new RegExp(`ToolBar\\s*\\{[^}]*panel: "${panel}"`, "s"),
            `${file} must hand its own panel to the tool bar`);
    }
    assert.match(read("components/ToolBar.qml"), /MenuSelect\s*\{/, "the tool bar has no filter menu");
    assert.match(read("components/ToolBar.qml"), /SearchField\s*\{/, "the tool bar has no search field");
    assert.match(read("components/ToolBar.qml"), /ViewModeToggle\s*\{/, "the tool bar has no layout toggle");
});

test("the tool bar takes the panel gutter, and no control carries a margin", () => {
    const toolbar = read("components/ToolBar.qml");
    assert.match(toolbar, /Layout\.leftMargin:\s*Gutter\.left/);
    assert.match(toolbar, /Layout\.rightMargin:\s*Gutter\.right/);
    // The rule is measured on INK (owner, 2026-11-02): the row takes the gutter
    // and the two controls that own an edge take the card's ink inset, so their
    // visible pixels — the label and the selected fill — sit on the cards' line.
    assert.match(toolbar, /MenuSelect\s*\{[\s\S]*?Layout\.leftMargin:\s*Gutter\.ink/,
        "the filter menu must start on the cards' ink line");
    assert.match(toolbar, /ViewModeToggle\s*\{[\s\S]*?Layout\.rightMargin:\s*Gutter\.ink/,
        "the toggle must end on the cards' ink line");
    assert.ok(!/SearchField\s*\{[^}]*Layout\.(left|right)Margin/s.test(toolbar),
        "the search field is interior: it must not add a margin of its own");
    // One height for the row, handed to the controls that measure themselves.
    assert.match(toolbar, /readonly property int controlHeight/);
    assert.match(toolbar, /cellHeight:\s*root\.controlHeight/);
});

test("the views no longer own the chips row or the toggle", () => {
    for (const file of VIEWS) {
        const source = read(file);
        assert.ok(!/FilterBar\s*\{/.test(source), `${file} still places the chips`);
        assert.ok(!/ViewModeToggle\s*\{/.test(source), `${file} still places the layout toggle`);
    }
    assert.ok(!fs.existsSync(path.join(ROOT, "components/FilterBar.qml")),
        "components/FilterBar.qml has no user left");
});

test("the grids, the lists and the tool bar read one gutter", () => {
    for (const file of VIEWS) {
        const source = read(file);
        assert.ok(source.includes("Gutter.left"), `${file} does not take the left gutter`);
        assert.ok(source.includes("Gutter.right"), `${file} does not take the right gutter`);
    }
    const gutter = read("services/Gutter.qml");
    // Owner, 2026-11-02: one margin for both sides, and the bar inside it.
    assert.match(gutter, /left:\s*Style\.spacing\.lg/);
    assert.match(gutter, /right:\s*Style\.spacing\.lg\n/);
    assert.ok(!/right:\s*Style\.spacing\.lg\s*\+/.test(gutter),
        "the right gutter must not be wider than the left one");
});

test("there is one dropdown implementation, and both users take it", () => {
    const novel = read("modules/novel/NovelReader.qml");
    assert.match(novel, /extraCell:\s*MenuSelect\s*\{/, "the provider picker is not the shared menu");
    assert.ok(!/providerPopup/.test(novel), "the old inline popup is still there");
    assert.match(read("components/ToolBar.qml"), /MenuSelect\s*\{/);
});

test("the menu's current row is solid accent, with the keyboard wired", () => {
    const select = read("components/MenuSelect.qml");
    assert.match(select, /current \? Colors\.primary/, "the current row is not the accent fill");
    for (const key of ["Key_Return", "Key_Escape", "Key_Down", "Key_Up", "Key_Space"]) {
        assert.ok(select.includes(key), `the menu does not handle ${key}`);
    }
    // Square: the shell's rule since §30, and a radius must say it is ignored.
    assert.ok(!/radius:/.test(select) || /style-ignore/.test(select));
});

test("labelFor always names something the menu can show", () => {
    const options = [{ value: "hot", label: "Hot" }, { value: "latest", label: "Latest" }];
    assert.equal(menu.labelFor(options, "latest"), "Latest");
    assert.equal(menu.labelFor(options, "search"), "Hot", "unknown value falls back to the first option");
    assert.equal(menu.labelFor(options, "search", "Latest"), "Latest", "a fallback wins over the first option");
    assert.equal(menu.labelFor([], "x"), "");
});

test("the highlight stops at the ends instead of wrapping", () => {
    assert.equal(menu.next(-1, 5, 1), 0, "opening with ↓ starts at the first row");
    assert.equal(menu.next(-1, 5, -1), 4, "opening with ↑ starts at the last row");
    assert.equal(menu.next(4, 5, 1), 4, "↓ stops at the last row");
    assert.equal(menu.next(0, 5, -1), 0, "↑ stops at the first row");
    assert.equal(menu.next(2, 5, 1), 3);
    assert.equal(menu.next(0, 0, 1), -1, "an empty menu has nothing to highlight");
});

test("opening starts on the current row", () => {
    const options = [{ value: "hot" }, { value: "latest" }, { value: "JP" }];
    assert.equal(menu.openingIndex(options, "JP"), 2);
    assert.equal(menu.openingIndex(options, "search"), 0);
    assert.equal(menu.indexOf(options, "nope"), -1);
});
