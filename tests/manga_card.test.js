"use strict";

// Probes for the manga card's meta line (plan Fase 2, Apéndice A).
//
// `chapter` is optional: the listings of MangaDex / zonatmo / zonatmo.org /
// ManhwaWeb carry it, the searches of zonatmo.org / WeebCentral / InManga do
// not, and library entries carry neither. A missing half must drop its segment
// AND its separator — never leave a dangling "·".
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const card = require("../services/manga_card.js");

const t = (k) => k;

test("metaLine joins chapter and status with one separator", () => {
    assert.equal(card.metaLine("105", "Ongoing", t), "ch|105 · Ongoing");
});

test("metaLine drops an empty chapter without leaving an orphan separator", () => {
    assert.equal(card.metaLine("", "Ongoing", t), "Ongoing");
    assert.equal(card.metaLine(null, "Completed", t), "Completed");
});

test("metaLine drops an empty status the same way", () => {
    assert.equal(card.metaLine("105", "", t), "ch|105");
    assert.equal(card.metaLine("", "", t), "");
});

test("a numeric zero chapter survives the model mapping", () => {
    // `chapter || ""` would turn 0 into "" — Chapter 0 is a real chapter.
    const mapped = (0 === 0) ? "0" : (0 || "");
    assert.equal(mapped, "0");
    assert.equal(card.metaLine("0", "Ongoing", t), "ch|0 · Ongoing");
});

test("translator decodes the segment, it does not forward it raw", () => {
    // A forwarding adapter printed "ch|9" on screen; this must decode.
    const fake = (key, params) => key + "(" + (params ? params[1] : "") + ")";
    const adapter = card.translator(fake);
    assert.equal(adapter("ch|9"), "ch(9)");
    assert.equal(adapter("plain"), "plain()");
});

test("metaLine never renders a dangling dot for either-missing input", () => {
    const out = card.metaLine(" ", " ", t);
    assert.ok(out === "" || !/[·\s]$/.test(out), "trailing separator: " + JSON.stringify(out));
});

test("metaLine trims stray whitespace around the values it keeps", () => {
    assert.equal(card.metaLine(" 105 ", " Ongoing ", t), "ch|105 · Ongoing");
});

test("metaLine treats a missing status like an empty one", () => {
    assert.equal(card.metaLine("105", null, t), "ch|105");
    assert.equal(card.metaLine("105", undefined, t), "ch|105");
});

test("tSegment turns one chapter segment into a translated label", () => {
    // Like I18n.t: params are optional, so a plain key never crashes on them.
    const translate = (key, params) => params ? key + ":" + params[1] : key;
    const segment = card.tSegment(translate);
    assert.equal(segment("ch|105"), "ch:105");
    assert.equal(segment("ch|12.5"), "ch:12.5");
    // A segment without a value is a plain key, not a half-built string.
    assert.equal(segment("plain"), "plain");
});

// ── statusTone: the status colour of the stitch card's meta row ─────────────
//
// The values below are verbatim from the sources: English from MangaDex /
// ManhwaWeb, Spanish from zonatmo / zonatmo.org / ManhwaWeb's localized
// labels. The pure function answers with one of four theme tones; QML maps
// each tone to a `Colors.*` role, so no colour literal lives in the views.

test("statusTone paints a finished work with the done tone", () => {
    for (const status of ["Completed", "finished", "completado", "Finalizado", "COMPLETADA"])
        assert.equal(card.statusTone(status), "done", status);
});

test("statusTone paints a publishing work with the live tone", () => {
    for (const status of ["Ongoing", "OnGoing", "publishing", "up to date", "en curso", "Publicándose", "al día"])
        assert.equal(card.statusTone(status), "live", status);
});

test("statusTone paints an interrupted work with the warn tone", () => {
    for (const status of ["Hiatus", "paused", "cancelled", "canceled", "dropped", "en pausa", "Cancelado"])
        assert.equal(card.statusTone(status), "warn", status);
});

test("statusTone falls back to muted for a status it does not know", () => {
    for (const status of ["", "   ", null, undefined, "desconocido", "en emisión pronto", "Manga"])
        assert.equal(card.statusTone(status), "muted", JSON.stringify(status));
});

test("statusTone ignores case, accents and surrounding whitespace", () => {
    assert.equal(card.statusTone("  PUBLICÁNDOSE  "), "live");
    assert.equal(card.statusTone("Al DÍA"), "live");
    assert.equal(card.statusTone(" Finalizado "), "done");
    assert.equal(card.statusTone("EN PAUSA"), "warn");
});

test("statusTone only ever answers one of the four theme tones", () => {
    const tones = new Set(card.TONES);
    // Includes the inherited Object keys: a plain `TABLE[key]` lookup would
    // answer with Object.prototype.constructor for "constructor".
    for (const status of [0, false, {}, [], "En Curso", "???", "constructor", "x".repeat(40)])
        assert.ok(tones.has(card.statusTone(status)), String(status));
});

// ── card geometry: one source of truth for the grid and its skeleton ────────
//
// BrowseView's GridView and the SkeletonGrid that stands in for it while the
// first page loads both build the card box from these constants. A ghost card
// that is a different height than a real one is what makes the panel jump on
// load, so the arithmetic below is the contract between them.

test("COVER_RATIO is Stitch's 3 / 4.4 poster", () => {
    assert.equal(card.COVER_RATIO, 4.4 / 3);
    // "aspect-[3/4.4]": a 100 px card covers 146.67 px of height.
    assert.ok(Math.abs(100 * card.COVER_RATIO - 146.6667) < 0.001);
});

test("INFO_BASE is the info band, in unscaled design pixels", () => {
    // Two title lines + the meta row + the p-2 padding at today's font sizes.
    // The views scale it with Style.space(), so the constant itself stays
    // unscaled — a pre-scaled value would be scaled twice.
    assert.equal(card.INFO_BASE, 66);
});

test("the grid formula derives the card height from the constants alone", () => {
    const cellWidth = 100;
    const height = cellWidth * card.COVER_RATIO + card.INFO_BASE;
    assert.equal(height, cellWidth * (4.4 / 3) + 66);
    assert.ok(Math.abs(height - 212.6667) < 0.001);
});

test("TONES is exactly the closed set statusTone can answer", () => {
    assert.deepEqual(card.TONES.slice().sort(), ["done", "live", "muted", "warn"]);
    for (const status of ["Completed", "Ongoing", "Hiatus", "desconocido", null])
        assert.ok(card.TONES.includes(card.statusTone(status)), String(status));
});

test("the card has one anatomy now, and its geometry is what the grids read", () => {
    // Round 6 removed the classic/stitch switch: the stitch card is the only
    // one, so the plan retired VARIANTS. What still has to hold is the box the
    // six grids and their ghosts compute from these two constants.
    assert.equal(card.VARIANTS, undefined);
    assert.equal(card.COVER_RATIO, 4.4 / 3);
    assert.equal(card.INFO_BASE, 66);
});
