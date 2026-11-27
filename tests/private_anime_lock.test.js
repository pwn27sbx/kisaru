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
        privateSourceEnabled: true,
        isPrivateId(id) {
            return String(id || "").indexOf("hentaila:") === 0;
        }
    };
    const privacy = { locked: false };
    const root = state;
    const Http = { get(_url, callback) { pending.push(callback); } };
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

test("a private detail callback arriving after lock releases the fetch guard", () => {
    const h = harness();
    h.api.fetchAnimeDetail({ id: "hentaila:item-one" });
    assert.equal(h.state.isFetchingDetail, true);

    h.privacy.locked = true;
    h.api.clearDetail();
    h.pending.shift()(null, JSON.stringify({ episodes: ["1"], count: 1 }));
    assert.equal(h.state.isFetchingDetail, false);

    h.privacy.locked = false;
    h.api.fetchAnimeDetail({ id: "hentaila:item-one" });
    assert.equal(h.pending.length, 1);
});

test("a private link callback arriving after lock releases the fetch guard", () => {
    const h = harness();
    h.api.fetchStreamLinks("hentaila:item-one", "1");
    assert.equal(h.state.isFetchingLinks, true);

    h.privacy.locked = true;
    h.api.clearStreamLinks();
    h.pending.shift()(null, JSON.stringify({ all_links: [] }));
    assert.equal(h.state.isFetchingLinks, false);

    h.privacy.locked = false;
    h.api.fetchStreamLinks("hentaila:item-one", "1");
    assert.equal(h.pending.length, 1);
});
