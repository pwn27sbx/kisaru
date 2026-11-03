// The library's local search (owner §33.1: "busca dentro de lo guardado").
//
// In Library the header's search does not touch the network: it filters the
// entries already in memory by title, as the text arrives. The three panels
// share this predicate so the matching rule cannot drift between them, and it is
// pure so it can be tested without a screen.
//
// Matching: case-insensitive, accents folded ("muñeca" finds "MUÑECA" and
// "muneca" finds "muñeca"), and an empty query returns everything (which is what
// makes Esc and the clear cell restore the whole shelf).
function fold(text) {
    var s = String(text === undefined || text === null ? "" : text).toLowerCase();
    // NFD + strip combining marks: enough for the Spanish titles this app shows.
    if (typeof s.normalize === "function") {
        s = s.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    }
    return s;
}

function matches(entry, query) {
    var q = fold(query).trim();
    if (q === "") return true;
    return fold(entry && entry.title ? entry.title : "").indexOf(q) >= 0;
}

function filter(entries, query) {
    var list = entries || [];
    var q = fold(query).trim();
    if (q === "") return list;
    var out = [];
    for (var i = 0; i < list.length; i++) {
        if (matches(list[i], q)) out.push(list[i]);
    }
    return out;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { fold: fold, matches: matches, filter: filter };
}
