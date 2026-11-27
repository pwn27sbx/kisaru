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

function _dayLabel(date) {
    var day = String(date.getDate());
    var month = String(date.getMonth() + 1);
    return (day.length < 2 ? "0" + day : day) + "/" +
           (month.length < 2 ? "0" + month : month) + "/" + date.getFullYear();
}

// "09/04/2026" for every format we can read, "" otherwise. The raw day-first
// string is what the owner reads on the site, so the picker shows it as-is.
function chapterDateLabel(value) {
    var date = parseChapterDate(value);
    return date === null ? "" : _dayLabel(date);
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

// ── Versions ────────────────────────────────────────────────────────────────
// A source can list the same chapter twice: "1" and "1.1", where the second is
// a later re-upload, not a new chapter. Numbers alone cannot tell that apart
// from a genuine decimal, because both live in the same series: a "12.5"
// extra, a "55.1" with no chapter 55, a split numbering "12.1"/"12.2".
//
// So a decimal only merges inside a *generation*: many ".1" rows sharing one
// upload window, later than their own chapter, with ids taken from another
// block. Anything else stays exactly as the source listed it.

var REUPLOAD_FRACTION = "1";
var SPLIT_FRACTION = "2";
var GENERATION_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;
var MIN_GENERATION = 3;
var MIN_COVERAGE = 0.25;

function _chapterText(value) {
    return value === null || value === undefined ? "" : String(value).trim();
}

function _isIntegerText(text) {
    return text !== "" && /^\d+$/.test(text);
}

function _fraction(text) {
    var dot = text.lastIndexOf(".");
    return dot < 0 ? "" : text.slice(dot + 1);
}

function _baseOf(text) {
    var dot = text.lastIndexOf(".");
    return dot < 0 ? text : text.slice(0, dot);
}

// An id and its trailing number run, e.g. "zonatmo_org:114049" -> ["zonatmo_org:", 114049].
// Ids whose prefix differs from the other set (uuid hashes, "old-1"/"new-1")
// carry no comparable order, so the caller skips the check instead of guessing.
function _idBlock(id) {
    var text = _chapterText(id);
    var match = text.match(/^(.*?)(\d+)$/);
    return match ? { prefix: match[1], value: parseInt(match[2], 10) } : null;
}

function _dateOf(entry) {
    return parseChapterDate(entry && entry.publishAt);
}

// Integer base chapter -> keys of its ".1" candidates, plus the facts that
// decide whether they form a generation.
function _generationFamilies(byKey, order) {
    var bases = order.filter(function(key) { return _isIntegerText(key); });
    var integerCount = bases.length;
    if (integerCount === 0) return Object.create(null);

    var baseDates = {};
    var baseIds = [];
    for (var b = 0; b < bases.length; b++) {
        var baseEntries = byKey[bases[b]];
        var baseDate = _dateOf(baseEntries[0]);
        if (baseDate !== null) baseDates[bases[b]] = baseDate.getTime();
        var baseBlock = _idBlock(baseEntries[0].id);
        if (baseBlock) baseIds.push(baseBlock);
    }

    // Candidate facts per base: a ".1" whose integer base exists as one row.
    var facts = [];
    for (var i = 0; i < order.length; i++) {
        var key = order[i];
        if (_fraction(key) !== REUPLOAD_FRACTION) continue;
        var baseKey = _baseOf(key);
        if (!byKey[baseKey] || byKey[baseKey].length !== 1) continue;
        if (order.some(function(other) { return other !== key && _baseOf(other) === baseKey && _fraction(other) === SPLIT_FRACTION; })) {
            continue;                       // split numbering: N.1/N.2 are two halves
        }
        if (baseDates[baseKey] === undefined) continue;
        var entry = byKey[key][0];
        var date = _dateOf(entry);
        if (date === null || date.getTime() <= baseDates[baseKey]) continue;
        facts.push({ key: key, base: baseKey, date: date.getTime(), id: entry.id });
    }
    if (facts.length < MIN_GENERATION) return Object.create(null);

    // One generation = candidates chained by upload date, each within a week
    // of the previous one.
    facts.sort(function(a, b) { return a.date - b.date; });
    var families = Object.create(null);   // candidate key -> {base, generation}
    var cluster = [facts[0]];
    function close(family) {
        if (family.length < MIN_GENERATION) return;
        if (family.length / integerCount < MIN_COVERAGE) return;

        var blocks = family.map(function(fact) { return _idBlock(fact.id); });
        if (blocks.every(function(block) { return block !== null; })
            && baseIds.length && baseIds.every(function(block) { return block.prefix === blocks[0].prefix; })
            && blocks.every(function(block) { return block.prefix === blocks[0].prefix; })) {
            var minCandidate = Math.min.apply(null, blocks.map(function(block) { return block.value; }));
            var maxCandidate = Math.max.apply(null, blocks.map(function(block) { return block.value; }));
            var minBase = Math.min.apply(null, baseIds.map(function(block) { return block.value; }));
            var maxBase = Math.max.apply(null, baseIds.map(function(block) { return block.value; }));
            // Interleaved ids: the ".1" rows come from the same upload block,
            // not from a later one, so they are not a re-upload generation.
            if (minCandidate <= maxBase && maxCandidate >= minBase) return;
        }
        // One cluster is one upload batch: every candidate of the batch shares
        // this key, which is what "use this version for the whole series" stores.
        var generation = "reupload:" + _dayLabel(new Date(family[0].date));
        for (var c = 0; c < family.length; c++) {
            families[family[c].key] = { base: family[c].base, generation: generation };
        }
    }
    for (var f = 1; f < facts.length; f++) {
        if (facts[f].date - cluster[cluster.length - 1].date <= GENERATION_WINDOW_MS) {
            cluster.push(facts[f]);
        } else {
            close(cluster);
            cluster = [facts[f]];
        }
    }
    close(cluster);
    return families;
}

// Preferred version: what the user last read here, then what they picked from
// the picker, then the newest upload, then the last row in source order.
function _primaryVersion(versions, chapter, preferences) {
    var prefs = preferences || {};
    // What the user asked for wins: the chapter's own pick, then the version
    // chosen for the whole series. Last read only decides when nobody asked.
    var choices = prefs.choices || {};
    var chosen = Object.prototype.hasOwnProperty.call(choices, chapter) ? choices[chapter] : "";
    if (chosen) {
        for (var b = 0; b < versions.length; b++) {
            if (versions[b].id === chosen) return versions[b];
        }
    }
    var series = _chapterText(prefs.seriesGeneration);
    if (series) {
        for (var s = 0; s < versions.length; s++) {
            if (versions[s].generation === series) return versions[s];
        }
    }
    if (prefs.lastReadId) {
        for (var a = 0; a < versions.length; a++) {
            if (versions[a].id === prefs.lastReadId) return versions[a];
        }
    }
    var newest = versions[versions.length - 1];
    var newestDate = _dateOf(newest);
    for (var c = versions.length - 2; c >= 0; c--) {
        var date = _dateOf(versions[c]);
        if (date === null) continue;
        if (newestDate === null || date.getTime() > newestDate.getTime()) {
            newest = versions[c];
            newestDate = date;
        }
    }
    return newest;
}

// [{chapter, versions, primary}] in source order. `versions.length === 1` for
// every chapter the source listed once, so consumers need no special case.
function groupChapters(chapters, preferences) {
    var list = Array.isArray(chapters) ? chapters : [];
    // A source label is untrusted text: "constructor" or "toString" would hit
    // Object.prototype and throw on push, blanking the whole list.
    var byKey = Object.create(null);
    var order = [];
    for (var i = 0; i < list.length; i++) {
        var entry = list[i];
        if (!entry) continue;
        var key = _chapterText(entry.chapter);
        if (!byKey[key]) {
            byKey[key] = [];
            order.push(key);
        }
        byKey[key].push(entry);
    }

    var families = _generationFamilies(byKey, order);
    var groups = [];
    for (var g = 0; g < order.length; g++) {
        var chapter = order[g];
        if (families[chapter]) continue;    // attached to its base below
        var versions = _withGeneration(byKey[chapter], "");
        for (var h = 0; h < order.length; h++) {
            var family = families[order[h]];
            if (!family || family.base !== chapter) continue;
            versions.push(_withGeneration([byKey[order[h]][0]], family.generation)[0]);
        }
        if (versions.length > 1) {
            versions.sort(function(a, b) {
                var left = _dateOf(a);
                var right = _dateOf(b);
                if (left === null || right === null) return 0;
                return left.getTime() - right.getTime();
            });
        }
        groups.push({
            chapter: chapter,
            versions: versions,
            primary: _primaryVersion(versions, chapter, preferences)
        });
    }
    return groups;
}

// A version copy carrying the upload batch it belongs to. A chapter listed
// once by MangaDex keeps its scanlator, so "read group B for the whole series"
// is expressible too.
function _withGeneration(entries, generation) {
    var out = [];
    for (var i = 0; i < entries.length; i++) {
        var entry = entries[i] || {};
        var copy = Object.assign({}, entry);
        var key = _chapterText(generation);
        if (key === "") {
            var group = _chapterText(entry.group);
            key = group ? "group:" + group : "original";
        }
        copy.generation = key;
        out.push(copy);
    }
    return out;
}

// The generation key stored when the user says "use this version for the whole
// series", or "" when the version is not there.
function preferenceFor(group, versionId) {
    var version = pickVersion(group, versionId);
    return version ? _chapterText(version.generation) : "";
}

// The upload the user pointed at, or null.
function pickVersion(group, versionId) {
    var versions = (group && group.versions) || [];
    for (var i = 0; i < versions.length; i++) {
        if (versions[i] && versions[i].id === versionId) return versions[i];
    }
    return null;
}

// Rows the version picker draws: the source number with its own day-first
// date, the group when the source names one, and the state of that exact
// upload. `hiddenDownloads` masks every state while the entry hides behind the
// private mode, exactly like the chapter row does; the picker must not become
// a side channel for which upload is on disk.
function versionRows(group, stateFor, hiddenDownloads) {
    var versions = (group && group.versions) || [];
    var stateOf = typeof stateFor === "function" ? stateFor : function() { return null; };
    var rows = [];
    for (var i = 0; i < versions.length; i++) {
        var version = versions[i] || {};
        var state = hiddenDownloads ? null : stateOf(version.id);
        state = state || {};
        rows.push({
            id: version.id || "",
            number: _chapterText(version.chapter),
            group: _chapterText(version.group),
            generation: _chapterText(version.generation),
            date: chapterDateLabel(version.publishAt),
            state: hiddenDownloads ? "idle" : (state.kind || "idle"),
            done: hiddenDownloads ? 0 : (Number(state.done) || 0),
            total: hiddenDownloads ? 0 : (Number(state.total) || 0),
            downloadsVisible: !hiddenDownloads
        });
    }
    return rows;
}

// The chapter number a stored progress value belongs to: "2.1" (a version)
// folds onto "2", so the badge and the highlight land on the grouped row.
function canonicalNumber(groups, stored) {
    var wanted = _chapterText(stored);
    if (wanted === "") return wanted;
    var list = Array.isArray(groups) ? groups : [];
    for (var i = 0; i < list.length; i++) {
        var group = list[i];
        if (!group) continue;
        if (group.chapter === wanted) return group.chapter;
        for (var j = 0; j < (group.versions || []).length; j++) {
            if (group.versions[j] && _chapterText(group.versions[j].chapter) === wanted) return group.chapter;
        }
    }
    return wanted;
}

// Adjacent chapter one step away (-1 previous, +1 next) between grouped
// chapters. `currentId` may be any version id; siblings never take a step.
function adjacentGroup(groups, currentId, step) {
    if (!Array.isArray(groups) || !groups.length || !currentId) return null;
    if (step !== -1 && step !== 1) return null;

    var entries = [];
    var currentNum = null;
    for (var i = 0; i < groups.length; i++) {
        var group = groups[i];
        if (!group) continue;
        var number = chapterNumber(group.chapter);
        var num = number === null ? 0 : number;
        entries.push({ group: group, num: num, idx: i });
        if (currentNum === null) {
            for (var v = 0; v < (group.versions || []).length; v++) {
                if (group.versions[v] && group.versions[v].id === currentId) {
                    currentNum = num;
                    break;
                }
            }
        }
    }
    if (currentNum === null) return null;

    entries.sort(function(a, b) {
        return a.num !== b.num ? a.num - b.num : a.idx - b.idx;
    });

    if (step > 0) {
        for (var j = 0; j < entries.length; j++) {
            if (entries[j].num > currentNum) return entries[j].group;
        }
        return null;
    }
    var prevNum = null;
    var prevGroup = null;
    for (var k = 0; k < entries.length; k++) {
        if (entries[k].num < currentNum) {
            if (prevNum === null || entries[k].num > prevNum) {
                prevNum = entries[k].num;
                prevGroup = entries[k].group;
            }
        } else {
            break;
        }
    }
    return prevGroup;
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
        groupChapters: groupChapters,
        versionRows: versionRows,
        pickVersion: pickVersion,
        preferenceFor: preferenceFor,
        canonicalNumber: canonicalNumber,
        adjacentGroup: adjacentGroup,
        sameChapter: sameChapter,
        chapterIndex: chapterIndex,
        adjacentChapter: adjacentChapter
    };
}
