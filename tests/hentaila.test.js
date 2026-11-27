"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const hentaila = require("../services/hentaila.js");
const prefs = require("../services/prefs.js");
const libraryView = require("../services/library_view.js");
const ROOT = path.resolve(__dirname, "..");
const read = (name) => fs.readFileSync(path.join(ROOT, name), "utf8");

test("HentaiLA ids use the normal source prefix", () => {
    assert.equal(hentaila.isHentaiId("hentaila:item-one"), true);
    assert.equal(hentaila.isHentaiId("jkanime:item-one"), false);
    assert.equal(hentaila.isHentaiId(""), false);
});

test("the secret only toggles user-hidden entries for every source", () => {
    const entries = [
        { id: "normal", title: "Visible", hidden: false },
        { id: "hentaila:item-one", title: "Source item", hidden: false },
        { id: "hentaila:item-two", title: "Hidden source item", hidden: true },
    ];
    const options = { loaded: true, locked: true, folder: "" };
    assert.deepEqual(
        libraryView.visibleEntries(entries, [], options).map((entry) => entry.id),
        ["normal", "hentaila:item-one"]
    );
    assert.deepEqual(
        libraryView.visibleEntries(entries, [], { ...options, locked: false }).map((entry) => entry.id),
        ["normal", "hentaila:item-one", "hentaila:item-two"]
    );
});

test("the anime library does not add a source-specific lock filter", () => {
    const qml = read("services/Anime.qml");
    assert.doesNotMatch(qml, /privateAnimeList|clearPrivateList|isPrivateId/);
    assert.match(qml, /LibraryViewJs\.visibleEntries\(root\.libraryList/);
    assert.match(qml, /LibraryViewJs\.visibleCount\(root\.libraryList/);
});

test("HentaiLA covers use the existing manga image proxy", () => {
    const raw = "https://cdn.hentaila.com/covers/item-one.jpg";
    const proxied = hentaila.coverUrl(raw, "http://127.0.0.1:5150");
    assert.equal(proxied, "http://127.0.0.1:5150/image?url=" + encodeURIComponent(raw));
    assert.equal(hentaila.coverUrl("", "http://127.0.0.1:5150"), "");
});

test("turning the source off removes its loaded results without touching others", () => {
    const entries = [
        { id: "normal" },
        { id: "hentaila:item-one" },
        { id: "jkanime:item-two" },
    ];
    assert.deepEqual(
        hentaila.withoutSource(entries).map((entry) => entry.id),
        ["normal", "jkanime:item-two"]
    );
    assert.deepEqual(hentaila.withoutSource(undefined), []);
    const qml = read("services/Anime.qml");
    assert.match(qml, /onHentailaSourceEnabledChanged/);
    assert.match(qml, /HentaiLA\.withoutSource/);
});

test("HentaiLA defaults on and explicit off values win", () => {
    assert.equal(prefs.DEFAULT_HENTAILA_SOURCE_ENABLED, true);
    assert.equal(prefs.normalizeHentailaSourceEnabled(undefined), true);
    assert.equal(prefs.normalizeHentailaSourceEnabled(false), false);
    assert.equal(prefs.normalizeHentailaSourceEnabled("false"), true);
    assert.equal(hentaila.sourceEnabled(true, ""), true);
    assert.equal(hentaila.sourceEnabled(true, "off"), false);
    assert.equal(hentaila.sourceEnabled(false, ""), false);
});

test("BrowseView uses the normal anime model without a private entry", () => {
    const qml = read("modules/anime/components/BrowseView.qml");
    assert.doesNotMatch(qml, /privateMode|privateRequested|privateClosed|anime\.private/);
    assert.match(qml, /values:\s*Anime\.animeList/);
    assert.match(qml, /function resetList\(\)\s*\{\s*Anime\.fetchPopular\(true\)/);
});

test("AnimePanel searches normally and keeps the secret as a hidden-entry reveal", () => {
    const qml = read("modules/anime/AnimePanel.qml");
    assert.doesNotMatch(qml, /privateMode|searchPrivateAnime|fetchPrivateAnime|clearPrivateList/);
    assert.match(qml, /Privacy\.consider\(text/);
    assert.match(qml, /Anime\.searchAnime\(text, true\)/);
    assert.match(qml, /browseCount:\s*Anime\.animeList\.length/);
});

test("DetailView keeps normal playback and disables AniSkip for HentaiLA", () => {
    const qml = read("modules/anime/components/DetailView.qml");
    assert.doesNotMatch(qml, /privateSource:|Private|isPrivateId/);
    assert.match(qml, /showSkipDisabled:\s*UiPrefs\.isAnimeSkipDisabled\(showId \|\| ""\)\s*\|\|\s*Anime\.isHentaiId\(showId \|\| ""\)/);
    assert.match(qml, /!Anime\.isHentaiId\(Anime\.currentAnime\.id\)/);
});

test("PanelSettings exposes a default-on normal source switch", () => {
    const qml = read("components/PanelSettings.qml");
    assert.match(qml, /property bool hentailaSourceEnabled/);
    assert.match(qml, /signal hentailaSourceToggled/);
    assert.match(qml, /settings\.hentailaSource/);
});
