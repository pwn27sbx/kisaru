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
        sameChapter: sameChapter,
        chapterIndex: chapterIndex,
        adjacentChapter: adjacentChapter
    };
}
