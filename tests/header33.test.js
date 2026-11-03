"use strict";

// §33: the header absorbs the tool row.
//
// Owner's design, in one sentence: the search becomes an icon next to the gear
// and grows a field leftwards over the brand; the grid/list switch becomes a
// setting; the second row disappears; the scrollbar goes and the two outer
// margins become equal. A source test cannot see pixels (that is the capture's
// job), but it can refuse the shapes that would undo the design.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const read = (rel) => fs.readFileSync(path.join(ROOT, rel), "utf8");
const filter = require(path.join(ROOT, "services/library_filter.js"));

const PANELS = [
    "modules/manga/MangaReader.qml",
    "modules/anime/AnimePanel.qml",
    "modules/novel/NovelReader.qml",
];

test("the header holds the whole row: filter, search icon, gear, minimize", () => {
    const header = read("components/PanelHeader.qml");
    const order = ["MenuSelect", "id: searchButton", "iconText: \"󰒓\"", "iconText: \"─\""];
    let last = -1;
    for (const needle of order) {
        const at = header.indexOf(needle, last + 1);
        assert.ok(at > last, `${needle} is missing or out of order in the header`);
        last = at;
    }
    // The search icon is the same kind of control as the other two.
    assert.match(header, /PanelActionButton\s*\{\s*id: searchButton[\s\S]*?size: root\.implicitHeight/);
});

test("the search field grows from its icon towards the brand", () => {
    const header = read("components/PanelHeader.qml");
    // Its right edge is the icon and its left edge is fixed, so x follows the
    // width: the box grows out of the icon towards the brand.
    // Reactive on purpose: mapToItem() froze the width at creation (diagnosis,
    // 2026-11-02), so the width must come from real properties only.
    assert.match(header, /fullWidth:[\s\S]*?searchButton\.x \+ actionsRow\.x/);
    assert.ok(!/fullWidth:[\s\S]{0,200}?mapToItem/.test(header),
        "fullWidth must not depend on mapToItem, which never re-evaluates");
    assert.match(header, /clip: true/, "the field must clip its own text");
    // Owner, 2026-11-02: at full width it starts at the panel's left corner, so
    // this is the one place the card-edge rule is overridden on purpose.
    assert.match(header, /x:\s*fullWidth - width/);
    assert.match(header, /width:\s*root\.searchOpen \? fullWidth : 0[\s\S]*?Behavior on width/);
    assert.match(header, /property bool searchOpen/);
    // The brand keeps the cards' ink line; the open field does not (it is chrome).
    assert.match(header, /Gutter\.left \+ Gutter\.ink/);
    assert.ok(!/fullWidth:[\s\S]{0,200}?Gutter\.left/.test(header),
        "the open field must reach the panel corner, not the brand's ink line");
    // Owner, 2026-11-02: it must be drawn ABOVE the brand, the tabs and the
    // filter, and take the whole header block — one flat band, not a pill.
    assert.match(header, /id: searchField[\s\S]{0,300}?z:\s*10/, "the field must paint above the header items");
    assert.match(header, /height:\s*root\.implicitHeight/, "the field must be as tall as the header cells");
    assert.match(header, /radius:\s*Style\.space\(0\)/, "the open field must be square, not a pill");
});

test("no panel keeps a second row, a tool bar or a scrollbar", () => {
    for (const file of PANELS) {
        const source = read(file);
        assert.ok(!/ToolBar\s*\{/.test(source), `${file} still places a tool bar`);
        assert.ok(!/ScrollBar/.test(source), `${file} still shows a scrollbar`);
    }
    for (const dir of ["manga", "anime", "novel"]) {
        for (const view of ["BrowseView", "LibraryView", "DetailView"]) {
            const file = `modules/${dir}/components/${view}.qml`;
            if (!fs.existsSync(path.join(ROOT, file))) continue;
            assert.ok(!/ScrollBar/.test(read(file)), `${file} still shows a scrollbar`);
        }
    }
});

test("the layout switch lives in the settings page, per panel", () => {
    const settings = read("components/PanelSettings.qml");
    assert.match(settings, /property var layouts/);
    assert.match(settings, /signal layoutSelected/);
    assert.match(settings, /settings\.layout/);
    for (const [file, panel] of PANELS.map((f, i) => [f, ["manga", "anime", "novel"][i]])) {
        assert.match(read(file), new RegExp(`onLayoutSelected: function\\(id\\) \\{ UiPrefs\\.setViewMode\\("${panel}"`),
            `${file} does not save its own layout`);
    }
});

test("the outer margins are one number", () => {
    const gutter = read("services/Gutter.qml");
    assert.match(gutter, /left:\s*Style\.spacing\.lg/);
    assert.match(gutter, /right:\s*Style\.spacing\.lg/);
    assert.ok(!/right:\s*Style\.spacing\.lg\s*\+/.test(gutter), "the right margin must not be wider");
});

test("the library filter: case and accents do not matter, empty shows everything", () => {
    const shelf = [
        { title: "Solo Leveling" },
        { title: "Esa muñeca de porcelana" },
        { title: "La Eminecia en las Sombras" },
    ];
    assert.equal(filter.filter(shelf, "").length, 3, "an empty query must show the whole shelf");
    assert.equal(filter.filter(shelf, "   ").length, 3);
    assert.equal(filter.filter(shelf, "solo")[0].title, "Solo Leveling");
    assert.equal(filter.filter(shelf, "SOLO").length, 1);
    assert.equal(filter.filter(shelf, "muneca")[0].title, "Esa muñeca de porcelana", "accents are folded");
    assert.equal(filter.filter(shelf, "MUÑECA").length, 1);
    assert.equal(filter.filter(shelf, "zzz").length, 0);
    assert.equal(filter.filter(null, "x").length, 0, "a missing shelf is empty, not a crash");
    assert.equal(filter.matches({ title: null }, "x"), false);
});

test("each panel feeds the library view the live query", () => {
    for (const file of PANELS) {
        assert.match(read(file), /query:\s*root\.searchOpen[^\n]*header\.searchText/,
            `${file} does not give the shelf the query`);
    }
});

test("the open field has no \"/\" hint badge (owner, 2026-11-02)", () => {
    const field = read("components/SearchField.qml");
    assert.ok(!/text:\s*"\/"/.test(field), "the / badge is still drawn inside the field");
    // The clear cell still exists for when there is text.
    assert.match(field, /userClear\(\)/, "the clear cell was removed with the badge");
});
