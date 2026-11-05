// Folder cards: what a folder looks like and where it sits in the Library.
//
// The views compose this with services/library_view.js: they pass the entries
// that are already visible, so a hidden folder never reaches the root and a
// hidden title can never become a cover. Nothing here decides visibility.
//
//   coverList   up to four cover URLs, skipping empty ones
//   partition   visible entries into { byFolder, folderless } (in order)
//   rootItems   folders first (organizer order), then folderless titles
//   searchTitles  a query over ALL visible titles, regardless of folder
function coverList(entries, coverOf, limit) {
    var max = limit === undefined ? 4 : limit;
    var list = entries || [];
    var out = [];
    for (var i = 0; i < list.length && out.length < max; i++) {
        var url = coverOf ? coverOf(list[i]) : "";
        if (url) out.push(url);
    }
    return out;
}

function folderItem(folder, entries, coverOf, limit) {
    var list = entries || [];
    return {
        kind: "folder",
        id: folder.id,
        name: folder.name,
        hidden: folder.hidden === true,
        count: list.length,
        covers: coverList(list, coverOf, limit)
    };
}

// The folder map and the titles with no folder, both in the library's order.
function partition(entries, folderIdOf) {
    var list = entries || [];
    var byFolder = Object.create(null);
    var folderless = [];
    for (var i = 0; i < list.length; i++) {
        var id = folderIdOf ? folderIdOf(list[i]) : "";
        if (id === "") {
            folderless.push(list[i]);
            continue;
        }
        if (!byFolder[id]) byFolder[id] = [];
        byFolder[id].push(list[i]);
    }
    return { byFolder: byFolder, folderless: folderless };
}

// Folders first, in organizer order; then titles that belong to no folder.
function rootItems(folders, folderless, byFolder, coverOf, limit) {
    var out = [];
    var list = folders || [];
    var map = byFolder || {};
    for (var i = 0; i < list.length; i++)
        out.push(folderItem(list[i], map[list[i].id], coverOf, limit));

    var titles = folderless || [];
    for (var j = 0; j < titles.length; j++)
        out.push({ kind: "title", entry: titles[j] });
    return out;
}

// A query over every visible title, whatever folder it lives in. `fold` is
// services/library_filter.js's fold and `titleOf` is the panel's display name,
// so anime searches its English/romaji name instead of a missing `title`.
function searchTitles(entries, query, fold, titleOf) {
    var list = entries || [];
    var q = String(fold ? fold(query) : query).trim();
    if (q === "") return list.slice();
    var out = [];
    for (var i = 0; i < list.length; i++) {
        var title = titleOf ? titleOf(list[i]) : (list[i] && list[i].title);
        var text = String(fold ? fold(title) : title);
        if (text.indexOf(q) >= 0) out.push(list[i]);
    }
    return out;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        coverList: coverList,
        folderItem: folderItem,
        partition: partition,
        rootItems: rootItems,
        searchTitles: searchTitles
    };
}
