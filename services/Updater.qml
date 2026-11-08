pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "updater.js" as Core

// Release check and banner state, shared by the three readers (S1, S3, A3).
//
// Readers are Loaders that unload shortly after closing (shell.qml), so the
// "checked" and "Later" flags cannot live in a reader: they live here, once
// per Kisaru process. shell.qml calls check() from every ReaderSlot's
// onOpened, which is the first moment a panel is really shown.
//
// The check is one Process, no timers: scripts/update-check.sh gathers the
// checkout state and the remote tags with a 5 s `timeout`; services/updater.js
// decides whether a numbered release is newer. Offline, timeout or any error
// means no banner and one log line.
Singleton {
    id: root

    // A5: the installed manifest is the local version. Missing or invalid
    // leaves `local` empty, which never shows a banner.
    readonly property string shellDir: Quickshell.shellDir
    readonly property string manifestPath: root.shellDir + "/omarchy/pwnsxb.kisaru/manifest.json"
    readonly property string checkScript: root.shellDir + "/scripts/update-check.sh"

    property string local: ""

    // A check was started; at most once per process (S1).
    property bool checked: false
    // Later was pressed; hidden for the rest of this process (S3).
    property bool dismissed: false

    // Checkout state from the script (A6, A8).
    property bool checkout: false
    property string branch: ""
    property bool dirty: false
    property var tags: []
    property bool failed: false
    property bool applied: false

    readonly property string latest: (root.failed || root.local === "")
        ? "" : Core.updateAvailable(root.local, root.tags)

    readonly property bool visible: root.checked && root.latest !== "" && !root.dismissed

    // Why Update is not offered ("" means it is): a copy install cannot pull,
    // and neither can another branch or a dirty tree (S4, A6, A16).
    readonly property string blocked: {
        if (!root.checkout) return "reinstall"
        if (root.branch !== "main") return "not-main"
        if (root.dirty) return "dirty"
        return ""
    }
    readonly property bool canUpdate: root.visible && root.blocked === ""

    function check() {
        if (root.checked) return
        root.checked = true
        if (!probe.running) probe.running = true
    }

    function dismiss() { root.dismissed = true }

    // S5/A7: the absolute bin/kisaru, so the floating terminal updates the
    // tree this panel runs from, not whatever is first on PATH.
    function launch(panel) {
        Quickshell.execDetached([
            "omarchy-launch-floating-terminal-with-presentation",
            root.shellDir + "/bin/kisaru", "update", "--reopen", panel
        ])
    }

    function apply(text) {
        if (root.applied) return
        root.applied = true
        var result = Core.parseCheck(text)
        if (result.error) {
            root.failed = true
            console.log("kisaru: update check failed; no banner")
            return
        }
        root.checkout = result.checkout
        root.branch = result.branch
        root.dirty = result.dirty
        root.tags = result.tags
    }

    FileView {
        id: manifest
        path: root.manifestPath
        onLoaded: root.local = Core.versionFromManifest(manifest.text())
        onLoadFailed: root.local = ""
    }

    Component.onCompleted: manifest.reload()

    Process {
        id: probe
        command: ["bash", root.checkScript, root.shellDir]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.apply(text)
        }
        // A command that could not even start prints nothing; that is still
        // one failure, never a silent "no update".
        onExited: function(code) {
            if (code !== 0 && !root.applied) root.apply("error=1")
        }
    }
}
