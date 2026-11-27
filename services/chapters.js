// Pure helpers for locating a chapter inside the detail list.
//
// The library stores `lastReadChapterNum` as the string the reader saved
// ("105"), while a source can list the same chapter differently: zonatmo.org
// answers "105.00", other sources answer "Capítulo 105". Compare the NUMBER,
// never the raw string — after the 2026-10-27 source switch the stored
// `lastReadChapterId` stopped matching any row (the ids changed with the
// source), so "where I left off" has to be found by chapter number.

var CHAPTER_NUMBER = /\d+(\.\d+)?/;

// "Capítulo 105.00" -> "105.00"; anything without digits is kept as it is so
// the caller can still show it.
function formatChapter(value) {
    if (value === null || value === undefined || value === "") return "?";
    var match = String(value).match(CHAPTER_NUMBER);
    return match ? match[0] : String(value);
}

// Numeric value of a chapter label, or null when it carries no number.
function chapterNumber(value) {
    var number = parseFloat(formatChapter(value));
    return isNaN(number) ? null : number;
}

// ── Dates ───────────────────────────────────────────────────────────────────
// Sources answer in their own format: zonatmo.org publishes "09/04/2026"
// (day first), MangaDex an ISO stamp. `new Date("09/04/2026")` reads month
// first and turns 9 April into 4 September, so the day was displayed wrong on
// the detail row and the default-version tie-breaker compared the wrong dates.

var DATE_DMY = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/;
var DATE_ISO = /^(\d{4})-(\d{2})-(\d{2})/;

// A local Date for a chapter date, or null when it cannot be read.
function parseChapterDate(value) {
    if (value === null || value === undefined || value === "") return null;
    var text = String(value).trim();
    var parts = text.match(DATE_DMY);
    if (!parts) {
        var iso = text.match(DATE_ISO);
        if (!iso) return null;
        parts = [iso[0], iso[3], iso[2], iso[1]];
    }
    var day = parseInt(parts[1], 10);
    var month = parseInt(parts[2], 10);
    var year = parseInt(parts[3], 10);
    var date = new Date(year, month - 1, day);
    if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) {
        return null;
    }
    return date;
}

// "09/04/2026" for every format we can read, "" otherwise. The raw day-first
// string is what the owner reads on the site, so the picker shows it as-is.
function chapterDateLabel(value) {
    var date = parseChapterDate(value);
    if (date === null) return "";
    var day = String(date.getDate());
    var month = String(date.getMonth() + 1);
    return (day.length < 2 ? "0" + day : day) + "/" +
           (month.length < 2 ? "0" + month : month) + "/" + date.getFullYear();
}

// One chapter row as the UI wants it. Every source fills what it has; `group`
// only exists for MangaDex and zonatmo.net, and the version picker labels a
// re-upload with it whenever it is there.
function mapChapter(raw) {
    var chapter = raw || {};
    return {
        id:        chapter.id || "",
        chapter:   chapter.chapter || "",
        title:     chapter.title || "",
        pages:     0,
        group:     chapter.group || "",
        publishAt: chapter.publishAt || ""
    };
}

function sameChapter(left, right) {
    var a = chapterNumber(left);
    var b = chapterNumber(right);
    return a !== null && b !== null && a === b;
}

// Index of the first entry whose chapter number matches `number`, or -1.
// `list` may be null while the detail is still loading.
function chapterIndex(list, number) {
    if (!list || !list.length) return -1;
    for (var i = 0; i < list.length; i++) {
        if (list[i] && sameChapter(list[i].chapter, number)) return i;
    }
    return -1;
}

// Adjacent chapter one step away (-1 = previous, +1 = next) in ascending
// chapter-number order on the full list, regardless of source order.
// Chapters without a number sort as 0 (matching DetailView). Among entries
// with the same number, the first in source order wins, and a duplicate number
// never steps to itself. Returns null at either end or if currentId is absent.
function adjacentChapter(chapters, currentId, step) {
    if (!chapters || !chapters.length || !currentId) return null;
    if (step !== -1 && step !== 1) return null;

    var entries = [];
    var currentNum = null;
    for (var i = 0; i < chapters.length; i++) {
        var ch = chapters[i];
        if (!ch) continue;
        var n = chapterNumber(ch.chapter);
        var num = n === null ? 0 : n;
        entries.push({ item: ch, num: num, idx: i });
        if (currentNum === null && ch.id === currentId) {
            currentNum = num;
        }
    }
    if (currentNum === null) return null;

    entries.sort(function(a, b) {
        return a.num !== b.num ? a.num - b.num : a.idx - b.idx;
    });

    if (step > 0) {
        for (var j = 0; j < entries.length; j++) {
            if (entries[j].num > currentNum) return entries[j].item;
        }
        return null;
    }

    var prevNum = null;
    var prevItem = null;
    for (var k = 0; k < entries.length; k++) {
        if (entries[k].num < currentNum) {
            if (prevNum === null || entries[k].num > prevNum) {
                prevNum = entries[k].num;
                prevItem = entries[k].item;
            }
        } else {
            break;
        }
    }
    return prevItem;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        formatChapter: formatChapter,
        chapterNumber: chapterNumber,
        parseChapterDate: parseChapterDate,
        chapterDateLabel: chapterDateLabel,
        mapChapter: mapChapter,
        sameChapter: sameChapter,
        chapterIndex: chapterIndex,
        adjacentChapter: adjacentChapter
    };
}
