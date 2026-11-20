// Pure helpers for manga chapter downloads, kept QML-free so Node can test them.
//
// Private mode (Amendment A2): `visibleSeries` fails closed while locked until
// both the library and organizer files have loaded, matching library_view.js.
// Hidden titles never appear in the downloads list, chapter map or total bytes.

// A QML `list<var>` reaches JS as an array-like sequence, not an Array:
// copy any sequence with a numeric length into a real Array, or null.
function toArray(value) {
    if (Array.isArray(value)) return value;
    if (value && typeof value === "object" && typeof value.length === "number")
        return Array.prototype.slice.call(value);
    return null;
}

function visibleSeries(downloads, isHiddenFn, options) {
    var opts = options || {};
    var locked = opts.locked !== false;
    var loaded = opts.loaded === true;
    if (locked && !loaded) return [];
    downloads = toArray(downloads);
    if (!downloads) return [];

    var checkHidden = typeof isHiddenFn === "function" ? isHiddenFn : function() { return false; };
    var out = [];
    for (var i = 0; i < downloads.length; i++) {
        var series = downloads[i];
        if (!series || !series.id) continue;
        if (locked && checkHidden(series.id)) continue;
        out.push(series);
    }
    return out;
}

function downloadedChapterMap(downloads, isHiddenFn, options) {
    var visible = visibleSeries(downloads, isHiddenFn, options);
    var map = {};
    for (var i = 0; i < visible.length; i++) {
        var chapters = visible[i].chapters || [];
        for (var j = 0; j < chapters.length; j++) {
            var ch = chapters[j];
            if (ch && ch.chapterId) map[ch.chapterId] = ch;
        }
    }
    return map;
}

function summary(visibleDownloads) {
    visibleDownloads = toArray(visibleDownloads);
    if (!visibleDownloads) {
        return { seriesCount: 0, chapterCount: 0, totalBytes: 0 };
    }
    var chapterCount = 0;
    var totalBytes = 0;
    for (var i = 0; i < visibleDownloads.length; i++) {
        var series = visibleDownloads[i];
        if (!series) continue;
        var chapters = Array.isArray(series.chapters) ? series.chapters : [];
        chapterCount += chapters.length;
        var bytes = Number(series.sizeBytes);
        if (isFinite(bytes) && bytes > 0) totalBytes += bytes;
    }
    return {
        seriesCount: visibleDownloads.length,
        chapterCount: chapterCount,
        totalBytes: totalBytes
    };
}

function formatBytes(bytes) {
    var n = Number(bytes);
    if (!isFinite(n) || n <= 0) return "0 B";
    if (n < 1024) return Math.round(n) + " B";
    if (n < 1024 * 1024) return (n / 1024).toFixed(1) + " KB";
    if (n < 1024 * 1024 * 1024) return (n / (1024 * 1024)).toFixed(1) + " MB";
    return (n / (1024 * 1024 * 1024)).toFixed(2) + " GB";
}

function isBusy(jobs) {
    if (!jobs || typeof jobs !== "object") return false;
    for (var key in jobs) {
        var job = jobs[key];
        if (job && (job.status === "pending" || job.status === "downloading")) {
            return true;
        }
    }
    return false;
}

function chapterState(chapterId, downloadedMap, jobs) {
    if (downloadedMap && downloadedMap[chapterId]) {
        return { kind: "downloaded", done: 0, total: 0, error: "" };
    }
    var job = jobs && jobs[chapterId];
    if (job && (job.status === "pending" || job.status === "downloading")) {
        return {
            kind: "downloading",
            done: Number(job.done) || 0,
            total: Number(job.total) || 0,
            error: ""
        };
    }
    if (job && job.status === "error") {
        return {
            kind: "error",
            done: 0,
            total: 0,
            error: String(job.error || "")
        };
    }
    return { kind: "idle", done: 0, total: 0, error: "" };
}

function scrubHiddenJobs(jobs, isHiddenFn) {
    var out = {};
    if (!jobs || typeof jobs !== "object") return out;
    var checkHidden = typeof isHiddenFn === "function" ? isHiddenFn : function() { return false; };
    for (var key in jobs) {
        var job = jobs[key];
        if (!job) continue;
        if (checkHidden(job.mangaId || "")) continue;
        out[key] = job;
    }
    return out;
}

// Map a downloaded series object to the shape ReaderView and adjacentChapter()
// expect, so offline reading works without calling GET /info (Amendment A9).
function offlineMangaObject(series) {
    if (!series) return null;
    var id = series.id || "";
    var rawChapters = Array.isArray(series.chapters) ? series.chapters : [];
    var chapters = [];
    for (var i = 0; i < rawChapters.length; i++) {
        var ch = rawChapters[i];
        if (!ch) continue;
        chapters.push({
            id: ch.chapterId || "",
            chapter: ch.chapterNum || "",
            title: ch.title || "",
            pages: Number(ch.pages) || 0,
            group: "",
            publishAt: ch.downloadedAt || ""
        });
    }
    return {
        id: id,
        originId: id,
        title: series.title || "",
        description: "",
        status: "",
        year: 0,
        coverUrl: series.image || "",
        authors: [],
        tags: [],
        language: "",
        chapters: chapters
    };
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        visibleSeries: visibleSeries,
        downloadedChapterMap: downloadedChapterMap,
        summary: summary,
        formatBytes: formatBytes,
        isBusy: isBusy,
        chapterState: chapterState,
        scrubHiddenJobs: scrubHiddenJobs,
        offlineMangaObject: offlineMangaObject
    };
}
