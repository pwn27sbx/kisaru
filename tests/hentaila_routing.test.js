"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const source = fs.readFileSync(
    path.join(__dirname, "..", "services", "Anime.qml"), "utf8"
);

function grab(name, next) {
    const start = source.indexOf(`    function ${name}(`);
    const end = source.indexOf(`\n    function ${next}(`, start);
    assert.ok(start >= 0 && end > start, `missing ${name}`);
    return source.slice(start, end);
}

const bodies = [
    grab("fetchAnimeDetail", "_parseAnimeDetail"),
    grab("clearDetail", "fetchStreamLinks"),
    grab("fetchStreamLinks", "_parseStreamLinks"),
    grab("clearStreamLinks", "clearAnimeList")
].join("\n");

function harness() {
    const pending = [];
    const state = {
        isFetchingDetail: false,
        isFetchingLinks: false,
        currentAnime: null,
        detailError: "",
        streamLinks: [],
        selectedLink: null,
        linksError: "",
        currentEpisode: "",
        currentSubtitleLabel: "",
        apiUrl: "http://127.0.0.1:5050",
        currentMode: "sub",
        _parseAnimeDetail(show, json) {
            const data = JSON.parse(json);
            state.currentAnime = { ...show, episodes: data.episodes || [] };
            state.isFetchingDetail = false;
        },
        _parseStreamLinks(json) {
            const data = JSON.parse(json);
            state.streamLinks = data.all_links || [];
            state.isFetchingLinks = false;
        }
    };
    const privacy = { locked: false };
    const root = state;
    const Http = { get(url, callback) { pending.push({ url, callback }); } };
    const KisaruI18n = { t(key) { return key; } };

    const api = new Function(
        "root", "Http", "Privacy", "KisaruI18n", "state",
        `with (state) { ${bodies} }
         return { fetchAnimeDetail, clearDetail,
                  fetchStreamLinks, clearStreamLinks };`
    )(root, Http, privacy, KisaruI18n, state);

    Object.assign(state, api);
    return { state, privacy, pending, api };
}

test("HentaiLA detail uses the normal episodes route even while locked", () => {
    const h = harness();
    h.privacy.locked = true;
    h.api.fetchAnimeDetail({ id: "hentaila:item-one" });
    assert.equal(
        h.pending[0].url,
        "http://127.0.0.1:5050/episodes?id=hentaila%3Aitem-one&mode=sub"
    );
    h.pending.shift().callback(null, JSON.stringify({ episodes: ["1"], count: 1 }));
    assert.equal(h.state.currentAnime.episodes.length, 1);
    assert.equal(h.state.isFetchingDetail, false);
});

test("HentaiLA links use the normal links route even while locked", () => {
    const h = harness();
    h.privacy.locked = true;
    h.api.fetchStreamLinks("hentaila:item-one", "1");
    assert.equal(
        h.pending[0].url,
        "http://127.0.0.1:5050/links?id=hentaila%3Aitem-one&ep=1&mode=sub&quality=best"
    );
    h.pending.shift().callback(null, JSON.stringify({
        all_links: [{ quality: "best", url: "https://cdn.example/stream.m3u8" }]
    }));
    assert.equal(h.state.streamLinks.length, 1);
    assert.equal(h.state.isFetchingLinks, false);
});

test("clearing a detail request releases its fetch guard", () => {
    const h = harness();
    h.api.fetchAnimeDetail({ id: "hentaila:item-one" });
    assert.equal(h.state.isFetchingDetail, true);
    h.api.clearDetail();
    h.pending.shift().callback(null, JSON.stringify({ episodes: ["1"], count: 1 }));
    assert.equal(h.state.isFetchingDetail, false);
});

test("clearing a links request releases its fetch guard", () => {
    const h = harness();
    h.api.fetchStreamLinks("hentaila:item-one", "1");
    assert.equal(h.state.isFetchingLinks, true);
    h.api.clearStreamLinks();
    h.pending.shift().callback(null, JSON.stringify({ all_links: [] }));
    assert.equal(h.state.isFetchingLinks, false);
});
