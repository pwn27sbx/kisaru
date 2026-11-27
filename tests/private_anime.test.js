"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const privateAnime = require("../services/private_anime.js");
const prefs = require("../services/prefs.js");
const ROOT = path.resolve(__dirname, "..");
const read = (name) => fs.readFileSync(path.join(ROOT, name), "utf8");

test("private ids are recognized only by the dedicated prefix", () => {
    assert.equal(privateAnime.isPrivateId("hentaila:item-one"), true);
    assert.equal(privateAnime.isPrivateId("jkanime:item-one"), false);
    assert.equal(privateAnime.isPrivateId(""), false);
});

test("locked library views fail closed for every private-prefix record", () => {
    const entries = [
        { id: "normal", title: "Visible" },
        { id: "hentaila:item-one", title: "Private", hidden: false },
    ];
    assert.deepEqual(privateAnime.visibleLibrary(entries, true), [entries[0]]);
    assert.deepEqual(privateAnime.visibleLibrary(entries, false), entries);
});

test("private covers use the existing manga image proxy", () => {
    const raw = "https://cdn.hentaila.com/covers/item-one.jpg";
    const proxied = privateAnime.coverUrl(raw, "http://127.0.0.1:5150");
    assert.equal(proxied, "http://127.0.0.1:5150/image?url=" + encodeURIComponent(raw));
    assert.equal(privateAnime.coverUrl("", "http://127.0.0.1:5150"), "");
});

test("private source defaults on and explicit off values win", () => {
    assert.equal(prefs.DEFAULT_PRIVATE_ANIME_ENABLED, true);
    assert.equal(prefs.normalizePrivateAnimeEnabled(undefined), true);
    assert.equal(prefs.normalizePrivateAnimeEnabled(false), false);
    assert.equal(prefs.normalizePrivateAnimeEnabled("false"), true);
    assert.equal(privateAnime.sourceEnabled(true, ""), true);
    assert.equal(privateAnime.sourceEnabled(true, "off"), false);
    assert.equal(privateAnime.sourceEnabled(false, ""), false);
});

test("BrowseView has a locked-safe private entry and private model", () => {
    const qml = read("modules/anime/components/BrowseView.qml");
    assert.match(qml, /property bool privateMode/);
    assert.match(qml, /visible:\s*!browseView\.privateMode\s*&&\s*!Privacy\.locked\s*&&\s*Anime\.privateSourceEnabled/);
    assert.match(qml, /values:\s*browseView\.items/);
    assert.match(qml, /privateRequested/);
});

test("AnimePanel leaves private mode on lock and hides global filters there", () => {
    const qml = read("modules/anime/AnimePanel.qml");
    assert.match(qml, /property bool privateMode/);
    assert.match(qml, /filters:\s*root\.tabIndex === 0\s*&&\s*!root\.settingsMode\s*&&\s*!root\.privateMode/);
    assert.match(qml, /root\.privateMode = false/);
    assert.match(qml, /Anime\.searchPrivateAnime/);
});

test("DetailView passes private playback and stops it on lock", () => {
    const qml = read("modules/anime/components/DetailView.qml");
    assert.match(qml, /privateSource:\s*Anime\.isPrivateId\(showId \|\| ""\)/);
    assert.match(qml, /target:\s*Privacy/);
    assert.match(qml, /_playingShowId/);
});

test("PanelSettings exposes an optional default-on private source switch", () => {
    const qml = read("components/PanelSettings.qml");
    assert.match(qml, /property bool privateSourceEnabled/);
    assert.match(qml, /signal privateSourceToggled/);
    assert.match(qml, /settings\.privateSource/);
});
