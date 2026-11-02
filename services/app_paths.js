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

// The inherited libraries live under the same data home the app uses, so the
// fallback honours XDG_DATA_HOME exactly like the runtime does (owner decision,
// 2026-11-02): with the variable set, `$XDG_DATA_HOME/quickshell/<file>` is the
// inherited location, and without it the home default. Pinned by a test where
// the two differ, so a fallback can never silently read the wrong root.
function legacyLibraryPath(dataHome, panel) {
    return libraryPath(dataHome, panel, true);
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
