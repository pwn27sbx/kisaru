pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "app_paths.js" as Paths
import "lock_state.js" as LockState
import "privacy.js" as PrivacyJs
import qs.services

// Private mode: one secret file, one helper process, one lock state.
//
// The app never derives the key and never stores the word. It reads the record
// only for its salt and tag, uses the tag to decide whether a keystroke is worth
// a helper run, and sends the candidate on stdin. The helper prints nothing and
// exits 0 on a match; a generation counter discards a late answer and a 2 s
// watchdog kills a helper that never answers.
//
// Locked is the initial state (process start). The shell's one hook, the
// padlock and the word typed again all go through the same reducer. A missing
// or broken file means no secret is configured and the mode stays locked.
Singleton {
    id: root

    readonly property string _dataHome:
        Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")
    readonly property string path: Paths.privacyPath(root._dataHome)
    readonly property string helper: ReaderEnv.scripts + "/privado.py"

    property var record: null
    property bool configLoaded: false
    property var _state: LockState.initial()
    readonly property bool locked: _state.locked
    readonly property bool configured: root.record !== null
    readonly property bool checking: _state.checking

    // The current check: its callback, its word and whether the exit we are
    // about to see belongs to a process we killed on purpose.
    property var _done: null
    property string _word: ""
    property bool _killing: false

    signal wordAccepted()

    FileView {
        id: privacyFile
        path: root.path
        watchChanges: true
        onFileChanged: privacyFile.reload()
        onLoaded: {
            var wasLoaded = root.configLoaded
            var parsed = PrivacyJs.parse(privacyFile.text())
            root.record = parsed
            root.configLoaded = true
            // A replaced or removed word must not leave the panel open.
            if (wasLoaded || parsed === null) root.lock()
        }
        onLoadFailed: {
            root.record = null
            root.configLoaded = true
            root.lock()
        }
    }

    Process {
        id: checker
        command: [ReaderEnv.python, "-I", root.helper, "--check", root.path]
        stdinEnabled: true
        onStarted: {
            if (root._word.length === 0) {
                checker.running = false
                return
            }
            checker.write(root._word)
            // Closing the write channel is the EOF the helper waits for.
            checker.stdinEnabled = false
            watchdog.restart()
        }
        onExited: function(code) {
            if (root._killing) {
                root._killing = false
                return
            }
            root._settle(code)
        }
    }

    Timer {
        id: watchdog
        interval: 2000
        repeat: false
        onTriggered: {
            root._settle(2)
            if (checker.running) {
                root._killing = true
                checker.running = false
            }
        }
    }

    function _apply(action) {
        root._state = LockState.reduce(root._state, action)
    }

    // Feed a typed query. Returns "miss" when the tag already rules it out (the
    // caller searches normally), "checking" when the helper is running.
    function consider(word, done) {
        var candidate = PrivacyJs.foldWord(word)

        // Every keystroke invalidates the check before it.
        root._done = null
        root._word = ""
        watchdog.stop()
        if (checker.running) {
            root._killing = true
            checker.running = false
        }
        root._apply({ type: LockState.CANCEL })

        if (!root.configured || candidate.length === 0) return "miss"
        if (!PrivacyJs.tagMatches(Qt.md5, root.record, candidate)) return "miss"

        root._done = typeof done === "function" ? done : null
        root._word = candidate
        root._apply({ type: LockState.START })
        checker.stdinEnabled = true
        checker.running = true
        return "checking"
    }

    function _settle(code) {
        if (!root._state.checking) return
        watchdog.stop()
        var done = root._done
        root._done = null
        root._word = ""
        root._apply({ type: LockState.SETTLE,
            generation: root._state.generation, ok: code === 0 })
        if (code === 0) root.wordAccepted()
        if (done) done(code)
    }

    // The padlock, the shell hook and a replaced file all land here.
    function lock() {
        watchdog.stop()
        if (checker.running) {
            root._killing = true
            checker.running = false
        }
        root._done = null
        root._word = ""
        root._apply({ type: LockState.LOCK })
    }
}
