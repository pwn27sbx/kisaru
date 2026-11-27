"use strict";

// Regression guard for the list row alignment (owner, 2026-11-27).
//
// Before this, the three Detail lists drew two edges that disagreed: the
// hover/selected fill spanned the whole row while the separator started under
// the title (72 px in, 64 in the anime list), and each chapter/episode pill was
// as wide as its own text, so "Ch. 262.2" pushed its title to a different x
// than "Ch. 262".
//
// The rule now: the badge column is as wide as the widest badge of the list, so
// every title starts on one x, and the separator runs from the badge column's
// left edge to the content's right edge. This test measures that in a real
// offscreen render (tests/row_align_harness): real DetailView, real singletons,
// scratch data — never the owner's library or a window of their session.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const { runHarness, hasQs } = require("./row_align_harness/run.js");
const ListBadge = require("../services/list_badge.js");

const ROOT = path.resolve(__dirname, "..");
const read = (file) => fs.readFileSync(path.join(ROOT, file), "utf8");

function fields(result) {
    const out = {};
    for (const part of result.split(/\s+/).slice(2)) {
        const [k, v] = part.split("=");
        if (k) out[k] = v;
    }
    return out;
}

// ── The shared width rule ────────────────────────────────────────────────────

test("the badge column is the widest badge plus its padding", () => {
    assert.equal(ListBadge.columnWidth([]), 0, "an empty list has no column");
    assert.equal(ListBadge.columnWidth(undefined), 0, "a missing model has no column");
    // "Ch. 262.2" is the widest: the column is that text plus the pill padding,
    // rounded up so a fractional advance cannot leave the label clipped.
    assert.equal(
        ListBadge.columnWidth([24.46875, 48.40625, 36.34375]),
        Math.ceil(48.40625 + ListBadge.PADDING_X));
    assert.equal(ListBadge.columnWidth([20], 8), 28, "padding is a parameter");
    assert.equal(ListBadge.columnWidth([10, NaN, -4, "12.5"]), Math.ceil(12.5 + ListBadge.PADDING_X),
        "junk entries are ignored, numeric strings count");
});

// ── The rendered lists ───────────────────────────────────────────────────────

const ALIGNED = [
    ["manga", "Ch. 262.2 against Ch. 262 and Ch. 271"],
    ["anime", "Ep. 100 against Ep. 10 and Ep. 1"],
    ["novel", "Ch. 12.2 against Ch. 12 and Ch. 1"]
];

for (const [scenario, shape] of ALIGNED) {
    test(`${scenario} rows: one title x, one badge column, one separator edge (${shape})`, async (t) => {
        if (!hasQs()) return t.skip("qs not installed");
        const r = await runHarness({ scenario });
        assert.ok(r.result, `no RESULT line (qs exit ${r.code}):\n${r.log.slice(-25).join("\n")}`);
        const f = fields(r.result);

        assert.equal(f.scenario, scenario);
        assert.equal(f.rows, "3", `the fixture did not render three rows: ${r.result}`);
        // The rule under test: every title on the same x, from one fixed column.
        assert.equal(Number(f.titleSpread), 0,
            `titles do not start on the same x (spread ${f.titleSpread}): ${r.result}`);
        assert.equal(Number(f.widthSpread), 0,
            `the badge column is not one width (spread ${f.widthSpread}): ${r.result}`);
        assert.equal(Number(f.badgeSpread), 0,
            `the badge column does not start on one x (spread ${f.badgeSpread}): ${r.result}`);
        // The separator starts on the badge column and ends on the content's
        // right edge: the fill's content, not an arbitrary inset.
        assert.equal(Number(f.sepLeft), Number(f.badgeX),
            `the separator does not start on the badge column: ${r.result}`);
        assert.equal(Number(f.sepLeft), Number(f.rowLeft) + Number(f.inset),
            `the separator does not start on the content's left edge: ${r.result}`);
        assert.equal(Number(f.sepRight), Number(f.rowRight) - Number(f.inset),
            `the separator does not end on the content's right edge: ${r.result}`);
        // The title starts after the column, never inside it.
        assert.ok(Number(f.titleX) >= Number(f.badgeX) + Number(f.badgeW),
            `a title starts inside the badge column: ${r.result}`);
        assert.equal(r.pass, true, r.result);
    });
}

// ── The version chip and picker (owner additions, 2026-11-27) ────────────────

test("the version chip is a button in the same box as the Folder button", () => {
    const detail = read("modules/manga/components/DetailView.qml");
    const start = detail.indexOf("id: versionsChip");
    assert.ok(start >= 0, "the versions chip has no id: versionsChip");
    const end = detail.indexOf("// Download button", start);
    const chip = detail.slice(start, end > start ? end : start + 2200);

    // "2 versions ▾": the localized count plus the chevron that says it opens
    // something.
    assert.match(chip, /KisaruI18n\.tn\("versions\.count",[^)]*\)\s*\+\s*" ▾"/,
        "the chip label must be the localized count followed by the chevron");
    // Hover fill animated from an off colour: Colors.clear, never a colour that
    // makes the fade pass through black (tests/animated_color.test.js).
    assert.match(chip, /Colors\.clear\(Colors\.surface_container\)/,
        "the chip's off fill must be Colors.clear(...)");
    assert.match(chip, /hovered\s*\n?\s*\? Colors\.surface_container_high/,
        "the chip must fill on hover");
    assert.match(chip, /cursorShape:\s*Qt\.PointingHandCursor/,
        "the chip must show the hand cursor");
    // Same height/radius/border as the meta bar's Folder button.
    assert.match(chip, /height:\s*Style\.space\(24\)/, "the chip must be Style.space(24) tall");
    assert.match(chip, /radius:\s*Style\.cornerRadius/, "the chip must use Style.cornerRadius");
    assert.match(chip, /border\.color:\s*Colors\.outline_variant/, "the chip must keep the Folder border colour");
    assert.match(chip, /border\.width:\s*Style\.spacing\.hairline/, "the chip must keep the Folder hairline");
    // Behaviour unchanged: it opens the same picker.
    assert.match(chip, /onClicked:\s*detailView\.openVersions\(chapterRowAreaRect\._group\)/,
        "the chip must keep opening the version picker for its row");
});

test("the picker sizes itself from its rows and acts per row, not by a tick", () => {
    const picker = read("components/VersionPicker.qml");

    // The card is as wide as its longest row, never wider than the panel; a
    // fixed width cut the date of the highlighted upload ("21/04/20…").
    assert.match(picker, /width:\s*root\._cardWidth/, "the card width must come from the measured rows");
    assert.match(picker, /root\._labelWidth/, "the card width must be measured from the labels");
    assert.match(picker, /parent\.width\s*-\s*2 \* Gutter\.left/, "the card must stay inside the panel");

    // Option B (owner, 2026-11-27): the row is the action. Clicking it reads
    // that upload; the trailing icons carry the whole-series generation and the
    // download. No chip inside a row, and no "Read" chip duplicating the row.
    assert.match(picker, /onClicked:\s*root\._read\(row\.modelData\.id, false\)/,
        "the row itself must read that upload for this chapter");
    assert.match(picker, /onClicked:\s*root\._read\(row\.modelData\.id, true\)/,
        "the whole-series icon must settle that upload for the series");
    assert.match(picker, /versions\.wholeSeriesTooltip/,
        "the whole-series icon needs its explanatory tooltip");
    assert.doesNotMatch(picker, /versions\.read/,
        "the Read chip is gone: the row is the action");
    assert.doesNotMatch(picker, /versions\.wholeSeries\)/,
        "the whole-series chip label is gone: the icon replaces it");
    assert.doesNotMatch(picker, /Chip\s*\{/, "no chips inside the picker rows");
    assert.match(picker, /text:\s*"✓"/, "a ✓ must mark the version being read");
    assert.match(picker, /property string seriesGeneration/, "the card needs the generation applied to the series");
    assert.match(picker, /modelData\.generation === root\.seriesGeneration/,
        "the whole-series icon must light up on the applied generation");
    assert.match(picker, /text:\s*"󰂻"/, "the whole-series icon is the books glyph");

    // The card is told which generation the series already uses.
    assert.match(read("modules/manga/components/DetailView.qml"),
        /versionPicker\.seriesGeneration = Manga\.seriesGeneration/,
        "the Detail must pass the series generation into the picker");
    assert.match(read("services/Manga.qml"),
        /readonly property string seriesGeneration/,
        "Manga must expose the series generation for the picker");
    assert.match(read("modules/manga/components/DetailView.qml"),
        /if \(versionPicker\.wholeSeries\) Manga\.setSeriesVersion/,
        "the Detail must still route a whole-series pick to Manga.setSeriesVersion");

    // The tick-first checkbox is gone: it asked for a scope before the version.
    assert.doesNotMatch(picker, /wholeSeries = !root\.wholeSeries/,
        "the tick-first checkbox flow must be gone");

    // Keyboard navigation is kept and now walks the rows.
    assert.match(picker, /Keys\.onEscapePressed/, "Escape must still close the picker");
    assert.match(picker, /Keys\.onUpPressed/, "Up must move the highlighted row");
    assert.match(picker, /Keys\.onDownPressed/, "Down must move the highlighted row");
    assert.match(picker, /Keys\.onReturnPressed/, "Enter must read the highlighted row");
});

test("render: the chip's box, the picker's width and its per-row icons", async (t) => {
    if (!hasQs()) return t.skip("qs not installed");
    const r = await runHarness({ scenario: "picker" });
    assert.ok(r.result, `no RESULT line (qs exit ${r.code}):\n${r.log.slice(-25).join("\n")}`);
    const f = fields(r.result);

    assert.equal(Number(f.truncated), 0,
        `a date is still cut in the picker: ${r.result}`);
    assert.ok(Number(f.labelNeeds) <= Number(f.labelW) + 0.5,
        `the label is narrower than its own text: ${r.result}`);
    assert.ok(Number(f.cardW) <= Number(f.panelW) - 2 * Number(f.gutter) + 0.5,
        `the card overflows the panel: ${r.result}`);
    assert.equal(f.checks, "1", `exactly one version must carry the ✓: ${r.result}`);
    assert.equal(f.series, "2", `every version row needs its whole-series icon: ${r.result}`);
    assert.equal(f.seriesActive, "1",
        `the icon must light up only on the generation applied to the series: ${r.result}`);
    assert.equal(f.downloads, "2", `every version row needs its download control: ${r.result}`);
    assert.equal(f.readChips, "0", `the Read chip must be gone: ${r.result}`);

    // The chip renders as the Folder button's box: same height, radius, border.
    assert.equal(f.chipLabel, "1", `the chip label is not "2 versions ▾": ${r.result}`);
    assert.equal(f.chipHand, "1", `the chip does not use the hand cursor: ${r.result}`);
    assert.equal(f.chipH, f.chipHWant, `the chip is not Style.space(24): ${r.result}`);
    assert.equal(f.chipRadius, f.chipRadiusWant, `the chip is not Style.cornerRadius: ${r.result}`);
    assert.equal(f.chipBorder, f.chipBorderWant, `the chip is not Style.spacing.hairline: ${r.result}`);
    assert.equal(r.pass, true, r.result);
});
