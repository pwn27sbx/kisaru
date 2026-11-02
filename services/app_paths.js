// Where the app's own config and data live (owner decision D6, 2026-11-01).
//
// The project is called kisaru. The inherited names are still on disk until the
// owner's cleanup (D4), so every reader asks for the new path first and uses the
// inherited one only while nothing exists at the new one. Keeping the decision a
// pure function lets the QML carry just the two filesystem probes and lets the
// rule be tested without a shell (tests/app_paths.test.js).

var CONFIG_DIR = "kisaru";
var LEGACY_CONFIG_DIR = "qs-novelmangareader";

var DATA_DIR = "kisaru";

// The libraries used to live in the neutral folder shared with the whole rice,
// which is why they are not under a project name at all.
var LEGACY_LIBRARY_DIR = "quickshell";

var LIBRARY_FILES = {
    manga: "manga_library.json",
    anime: "anime_library.json",
    novel: "new_novel_library.json"
};

// newPath when it exists, oldPath while it is the only one that does, and
// newPath when neither does (a fresh install writes to the new name).
function resolvePath(newPath, oldPath, newFound, oldFound) {
    if (newFound) return newPath;
    if (oldFound) return oldPath;
    return newPath;
}

// ~/.local/share/<dir>/<file>: the new folder, or the inherited one.
function libraryPath(dataHome, panel, legacy) {
    var name = LIBRARY_FILES[panel];
    if (!name) throw new Error("app_paths: unknown library " + String(panel));
    var dir = legacy ? LEGACY_LIBRARY_DIR : DATA_DIR;
    return dataHome + "/" + dir + "/" + name;
}

// The inherited libraries were written with a literal `~/.local/share`, not with
// XDG_DATA_HOME, so the fallback has to look there even when the variable is
// set. This is not a guess: before the migration the three services each read
// `Quickshell.env("HOME") + "/.local/share/quickshell/<file>"`. Honouring XDG
// here would look in a place the old code never wrote to, and the migration
// would report an empty library on a machine that has its data.
function legacyLibraryPath(home, panel) {
    return libraryPath(home + "/.local/share", panel, true);
}

if (typeof module !== "undefined" && module.exports)
    module.exports = {
        CONFIG_DIR: CONFIG_DIR,
        LEGACY_CONFIG_DIR: LEGACY_CONFIG_DIR,
        DATA_DIR: DATA_DIR,
        LEGACY_LIBRARY_DIR: LEGACY_LIBRARY_DIR,
        LIBRARY_FILES: LIBRARY_FILES,
        resolvePath: resolvePath,
        libraryPath: libraryPath,
        legacyLibraryPath: legacyLibraryPath
    };
