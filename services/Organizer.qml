pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "app_paths.js" as Paths
import "library_view.js" as LibraryViewJs

// The folder list, shared by the three panels and written atomically.
//
// organizer.json is new data under $DATA/kisaru. A missing file is an empty
// organizer; a file that will not parse keeps the last good folders, raises
// `loadFailed` and refuses every later save, so a broken file is never
// overwritten. Titles are never stored here: only `{id, name, hidden}`.
Singleton {
    id: root

    readonly property string _dataHome:
        Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")
    readonly property string path: Paths.organizerPath(root._dataHome)

    property var data: ({})
    property bool loaded: false
    property bool loadFailed: false

    FileView {
        id: organizerFile
        path: root.path
        atomicWrites: true
        onLoaded: {
            var text = organizerFile.text().trim()
            if (text === "") {
                root.loaded = true
                root.loadFailed = false
                return
            }
            try {
                var parsed = JSON.parse(text)
                if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
                    throw new Error("not an object")
                root.data = parsed
                root.loadFailed = false
            } catch (e) {
                // Keep the last good list; _commit refuses to save over it.
                console.warn("[Organizer] organizer parse error:", e)
                root.loadFailed = true
            }
            root.loaded = true
        }
        onLoadFailed: {
            // Missing file: a fresh install with no folders, not a broken one.
            root.data = ({})
            root.loaded = true
            root.loadFailed = false
        }
    }

    Component.onCompleted: organizerFile.reload()

    // The folder list of one kind, always an array.
    function folders(kind) {
        var entry = root.data ? root.data[kind] : null
        return entry && Array.isArray(entry.folders) ? entry.folders : []
    }

    function folder(kind, id) {
        return LibraryViewJs.findFolder(root.folders(kind), id)
    }

    function isHidden(kind, id) {
        return LibraryViewJs.isHiddenFolder(root.folders(kind), id)
    }

    function _commit(kind, folders) {
        if (!root.loaded || root.loadFailed) return false
        var next = {}
        for (var key in root.data) {
            if (Object.prototype.hasOwnProperty.call(root.data, key))
                next[key] = root.data[key]
        }
        var current = next[kind] && typeof next[kind] === "object" ? next[kind] : {}
        next[kind] = Object.assign({}, current, { folders: folders })
        root.data = next
        organizerFile.setText(JSON.stringify(root.data, null, 2))
        return true
    }

    function addFolder(kind, name) {
        var id = "f" + Date.now().toString(36) + Math.random().toString(36).slice(2, 7)
        if (!root._commit(kind, LibraryViewJs.newFolder(root.folders(kind), name, id)))
            return ""
        return id
    }

    function renameFolder(kind, id, name) {
        return root._commit(kind, LibraryViewJs.renamedFolder(root.folders(kind), id, name))
    }

    function deleteFolder(kind, id) {
        return root._commit(kind, LibraryViewJs.removedFolder(root.folders(kind), id))
    }

    function setHidden(kind, id, hidden) {
        return root._commit(kind, LibraryViewJs.hiddenFolder(root.folders(kind), id, hidden))
    }
}
