"use strict";

// Pure unit tests for services/downloads.js (chapter download state,
// byte formatting, private-mode fail-closed filtering and offline schema).
// Run with:  node --test tests/downloads.test.js

const test = require("node:test");
const assert = require("node:assert/strict");

const Downloads = require("../services/downloads.js");

const SAMPLE = [
    {
        id: "mangadex:visible-1",
        title: "Visible Manga",
        image: "file:///tmp/dl/v1/cover.jpg",
        sizeBytes: 3000,
        chapters: [
            { chapterId: "mangadex:v1-c2", chapterNum: "2", title: "Ch 2", pages: 12, sizeBytes: 1800, downloadedAt: "2026-11-20T01:00:00Z" },
            { chapterId: "mangadex:v1-c1", chapterNum: "1", title: "Ch 1", pages: 10, sizeBytes: 1000, downloadedAt: "2026-11-19T01:00:00Z" },
        ],
    },
    {
        id: "manhwaweb:secret-1",
        title: "Secret Title",
        image: "file:///tmp/dl/s1/cover.jpg",
        sizeBytes: 9000,
        chapters: [
            { chapterId: "manhwaweb:secret-1-1_01", chapterNum: "1", title: "Cap 1", pages: 20, sizeBytes: 8500, downloadedAt: "2026-11-20T02:00:00Z" },
        ],
    },
];

const isHidden = (id) => id === "manhwaweb:secret-1";

test("visibleSeries fails closed while locked and not yet loaded (A2)", () => {
    assert.deepEqual(Downloads.visibleSeries(SAMPLE, isHidden, { locked: true, loaded: false }), []);
    assert.deepEqual(Downloads.visibleSeries(SAMPLE, isHidden, {}), []);
    assert.deepEqual(Downloads.visibleSeries(SAMPLE, isHidden), []);
});

test("visibleSeries filters hidden titles when locked and loaded, shows all when unlocked", () => {
    const locked = Downloads.visibleSeries(SAMPLE, isHidden, { locked: true, loaded: true });
    assert.equal(locked.length, 1);
    assert.equal(locked[0].id, "mangadex:visible-1");

    const unlocked = Downloads.visibleSeries(SAMPLE, isHidden, { locked: false, loaded: true });
    assert.equal(unlocked.length, 2);
});

test("downloadedChapterMap and summary exclude hidden series while locked", () => {
    const mapLocked = Downloads.downloadedChapterMap(SAMPLE, isHidden, { locked: true, loaded: true });
    assert.ok(mapLocked["mangadex:v1-c1"]);
    assert.ok(mapLocked["mangadex:v1-c2"]);
    assert.equal(mapLocked["manhwaweb:secret-1-1_01"], undefined);

    const visible = Downloads.visibleSeries(SAMPLE, isHidden, { locked: true, loaded: true });
    assert.deepEqual(Downloads.summary(visible), {
        seriesCount: 1,
        chapterCount: 2,
        totalBytes: 3000,
    });

    const unlocked = Downloads.visibleSeries(SAMPLE, isHidden, { locked: false, loaded: true });
    assert.deepEqual(Downloads.summary(unlocked), {
        seriesCount: 2,
        chapterCount: 3,
        totalBytes: 12000,
    });
});

test("formatBytes formats B, KB, MB, GB and edge values", () => {
    assert.equal(Downloads.formatBytes(0), "0 B");
    assert.equal(Downloads.formatBytes(-5), "0 B");
    assert.equal(Downloads.formatBytes(NaN), "0 B");
    assert.equal(Downloads.formatBytes(512), "512 B");
    assert.equal(Downloads.formatBytes(1024), "1.0 KB");
    assert.equal(Downloads.formatBytes(1536), "1.5 KB");
    assert.equal(Downloads.formatBytes(1024 * 1024 * 3.5), "3.5 MB");
    assert.equal(Downloads.formatBytes(1024 * 1024 * 1024 * 1.25), "1.25 GB");
});

test("isBusy, chapterState and scrubHiddenJobs track active/error/downloaded states", () => {
    const downloaded = Downloads.downloadedChapterMap(SAMPLE, isHidden, { locked: true, loaded: true });
    const jobs = {
        "mangadex:v1-c3": { mangaId: "mangadex:visible-1", status: "downloading", done: 4, total: 10, error: "" },
        "manhwaweb:secret-1-2_01": { mangaId: "manhwaweb:secret-1", status: "pending", done: 0, total: 0, error: "" },
        "mangadex:v1-c4": { mangaId: "mangadex:visible-1", status: "error", done: 0, total: 0, error: "timeout" },
    };

    assert.equal(Downloads.isBusy(jobs), true);
    assert.equal(Downloads.isBusy({ "x": { status: "done" }, "y": { status: "error" } }), false);

    assert.equal(Downloads.chapterState("mangadex:v1-c1", downloaded, jobs).kind, "downloaded");
    assert.deepEqual(Downloads.chapterState("mangadex:v1-c3", downloaded, jobs), {
        kind: "downloading",
        done: 4,
        total: 10,
        error: "",
    });
    assert.deepEqual(Downloads.chapterState("mangadex:v1-c4", downloaded, jobs), {
        kind: "error",
        done: 0,
        total: 0,
        error: "timeout",
    });
    assert.equal(Downloads.chapterState("mangadex:unknown", downloaded, jobs).kind, "idle");

    const scrubbed = Downloads.scrubHiddenJobs(jobs, isHidden);
    assert.ok(scrubbed["mangadex:v1-c3"]);
    assert.ok(scrubbed["mangadex:v1-c4"]);
    assert.equal(scrubbed["manhwaweb:secret-1-2_01"], undefined);
});

test("offlineMangaObject maps downloaded series to ReaderView / chapter-nav schema (A9)", () => {
    assert.equal(Downloads.offlineMangaObject(null), null);
    const manga = Downloads.offlineMangaObject(SAMPLE[0]);
    assert.equal(manga.id, "mangadex:visible-1");
    assert.equal(manga.originId, "mangadex:visible-1");
    assert.equal(manga.title, "Visible Manga");
    assert.equal(manga.coverUrl, "file:///tmp/dl/v1/cover.jpg");
    assert.equal(manga.chapters.length, 2);
    assert.deepEqual(manga.chapters[0], {
        id: "mangadex:v1-c2",
        chapter: "2",
        title: "Ch 2",
        pages: 12,
        group: "",
        publishAt: "2026-11-20T01:00:00Z",
    });
});

// Live bug 2026-11-20: Manga.downloadsList was a QML `list<var>`, which reaches
// JS as a sequence that is NOT a JS Array. visibleSeries and
// downloadedChapterMap rejected it with Array.isArray, so the Downloads screen
// stayed empty and downloaded chapters kept their ↓ icon, while the backend
// listed both chapters. The helpers must accept any array-like sequence.
function qmlSequence(items) {
    const seq = { length: items.length };
    items.forEach((item, i) => { seq[i] = item; });
    return seq;
}

test("visibleSeries and downloadedChapterMap accept a QML list sequence, not only a JS Array", () => {
    const series = {
        id: "mangadex:opm",
        title: "El hombre de un solo golpe",
        sizeBytes: 4673263,
        chapters: [
            { chapterId: "mangadex:c252", chapterNum: "252", sizeBytes: 2079277 },
            { chapterId: "mangadex:c251", chapterNum: "251", sizeBytes: 2593986 },
        ],
    };
    const seq = qmlSequence([series]);
    assert.equal(Array.isArray(seq), false);
    const opts = { locked: true, loaded: true };
    const visible = Downloads.visibleSeries(seq, () => false, opts);
    assert.equal(visible.length, 1);
    assert.equal(visible[0].id, "mangadex:opm");
    const map = Downloads.downloadedChapterMap(seq, () => false, opts);
    assert.deepEqual(Object.keys(map).sort(), ["mangadex:c251", "mangadex:c252"]);
    assert.equal(Downloads.summary(visible).chapterCount, 2);
});

test("Manga.downloadsList is a plain JS array property, not a QML list<var>", () => {
    const fs = require("node:fs");
    const path = require("node:path");
    const manga = fs.readFileSync(path.join(__dirname, "..", "services", "Manga.qml"), "utf8");
    assert.match(manga, /property var downloadsList: \[\]/);
    assert.doesNotMatch(manga, /property list<var> downloadsList/);
});
