// What the Library actually shows: folders, hidden folders and the lock state.
//
// One rule for the three panels: every grid, list, empty state, badge, status
// line and search reads the visible list from here, and nobody walks the raw
// `libraryList` for display. The raw list stays the write side (`isInLibrary`,
// `getLibraryEntry`, `libraryEntryId`), because filtering those would make
// `addToLibrary` duplicate an entry that is merely hidden.
//
// Fail closed: while locked, or before organizer.json has loaded, an entry
// whose `folder` cannot be resolved is hidden. A missing folder is not an
// error the user should see; it is a title that must not leak.
//
// Options: { loaded: bool, locked: bool, folder: string }
//   - `loaded` is true only after the folder file was read successfully;
//   - `locked` defaults to true, so a caller that forgets it hides too much
//     instead of too little;
//   - `folder` is the active folder id, "" for Todas.

var NO_FOLDER = "";

function folderIdOf(entry) {
    if (!entry || entry.folder === undefined || entry.folder === null) return NO_FOLDER;
    return String(entry.folder);
}

function folderMap(folders) {
    var map = Object.create(null);
    var list = folders || [];
    for (var i = 0; i < list.length; i++) {
        if (list[i] && list[i].id) map[list[i].id] = list[i];
    }
    return map;
}

function findFolder(folders, id) {
    if (!id) return null;
    return folderMap(folders)[id] || null;
}

function isHiddenFolder(folders, id) {
    var folder = findFolder(folders, id);
    return folder ? folder.hidden === true : false;
}

function isVisible(entry, folders, options) {
    var opts = options || {};
    var id = folderIdOf(entry);
    if (id === NO_FOLDER) return true;
    // Before the folder list is known a pushed entry cannot be resolved.
    if (opts.loaded !== true) return false;
    var folder = findFolder(folders, id);
    if (!folder) return false;
    var locked = opts.locked !== false;
    if (locked && folder.hidden === true) return false;
    return true;
}

function visibleEntries(entries, folders, options) {
    var opts = options || {};
    var active = opts.folder ? String(opts.folder) : NO_FOLDER;
    var list = entries || [];
    var out = [];
    for (var i = 0; i < list.length; i++) {
        if (!isVisible(list[i], folders, opts)) continue;
        if (active !== NO_FOLDER && folderIdOf(list[i]) !== active) continue;
        out.push(list[i]);
    }
    return out;
}

// The number every badge and the status line shows: all visible titles, not
// just the active folder's (the folder name is the status line's other half).
function visibleCount(entries, folders, options) {
    return visibleEntries(entries, folders, options).length;
}

// Whether a folder is closed off by the lock. Only a hidden folder, or one
// that cannot be resolved, is closed while locked: an ordinary folder opens
// while locked and without any secret. Before the organizer loads nothing can
// be resolved, so a pushed folder fails closed while locked.
function lockedOut(folderId, folders, options) {
    if (!folderId) return false;
    var opts = options || {};
    if (opts.locked === false) return false;
    if (opts.loaded === false) return true;
    var folder = findFolder(folders, folderId);
    return !folder || folder.hidden === true;
}

// The folder chips: a hidden folder does not exist while locked.
function visibleFolders(folders, locked) {
    var list = folders || [];
    var out = [];
    for (var i = 0; i < list.length; i++) {
        if (locked && list[i].hidden === true) continue;
        out.push(list[i]);
    }
    return out;
}

function findEntry(entries, id) {
    var list = entries || [];
    for (var i = 0; i < list.length; i++) {
        if (list[i].id === id) return list[i];
    }
    return null;
}

// Folder list CRUD, immutable: the caller replaces the array and saves.
function newFolder(folders, name, id) {
    var clean = String(name === undefined || name === null ? "" : name).trim();
    if (clean === "" || !id) return folders || [];
    var copy = (folders || []).slice();
    copy.push({ id: String(id), name: clean, hidden: false });
    return copy;
}

function renamedFolder(folders, id, name) {
    var clean = String(name === undefined || name === null ? "" : name).trim();
    var list = folders || [];
    if (clean === "") return list;
    var found = false;
    var out = list.map(function(folder) {
        if (folder.id !== id) return folder;
        found = true;
        return Object.assign({}, folder, { name: clean });
    });
    return found ? out : list;
}

function hiddenFolder(folders, id, hidden) {
    return (folders || []).map(function(folder) {
        if (folder.id !== id) return folder;
        return Object.assign({}, folder, { hidden: hidden === true });
    });
}

function removedFolder(folders, id) {
    return (folders || []).filter(function(folder) { return folder.id !== id; });
}

// Deleting a folder never deletes a title: it only clears the pointer.
function entriesWithoutFolder(entries, folderId) {
    return (entries || []).map(function(entry) {
        if (folderIdOf(entry) !== folderId) return entry;
        return Object.assign({}, entry, { folder: NO_FOLDER });
    });
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        NO_FOLDER: NO_FOLDER,
        folderIdOf: folderIdOf,
        folderMap: folderMap,
        findFolder: findFolder,
        isHiddenFolder: isHiddenFolder,
        isVisible: isVisible,
        lockedOut: lockedOut,
        visibleEntries: visibleEntries,
        visibleCount: visibleCount,
        visibleFolders: visibleFolders,
        findEntry: findEntry,
        newFolder: newFolder,
        renamedFolder: renamedFolder,
        hiddenFolder: hiddenFolder,
        removedFolder: removedFolder,
        entriesWithoutFolder: entriesWithoutFolder
    };
}
