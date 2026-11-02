pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "prefs.js" as Core
import "app_paths.js" as Paths

// The app's preferences, and the ONLY writer of <config>/kisaru/settings.json.
//
// The directory is `kisaru`; the inherited `qs-novelmangareader` one is read
// only while the new one does not exist yet (owner decision D6), so the app
// keeps its settings during the migration window and a fresh install never
// writes into the old folder.
//
// Three features own a key here: the language row (`language`), the readers
// (`scrollFactor`) and the manga Browse/Library layout (`viewMode`). There used
// to be two writers with two in-memory copies of the file, which is how one key
// could clobber the other; every write now goes through `setSetting()`, which
// merges into what is on disk-as-loaded and preserves the rest
// (services/prefs.js).
//
// The values are reactive: `scrollFactor` is read by the readers' wheel
// handlers, `language` by I18n and `viewMode` by the two manga views, so a
// change applies without a restart.
Singleton {
    id: root

    readonly property string _baseDir:
        Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string _newDir: root._baseDir + "/" + Paths.CONFIG_DIR
    readonly property string _oldDir: root._baseDir + "/" + Paths.LEGACY_CONFIG_DIR
    // Probes: which of the two holds a settings file today.
    property bool _newSeen: false
    property bool _oldSeen: false
    property bool oldChecked: false
    readonly property string settingsDir:
        Paths.resolvePath(root._newDir, root._oldDir, root._newSeen, root._oldSeen)
    readonly property string settingsPath: root.settingsDir + "/settings.json"

    property string raw: ""
    // A write can land before the first load finishes; the late `onLoaded` must
    // not put the old file back over it (observed: the language write was
    // reverted by the load that started earlier).
    property bool _touched: false
    property bool _loaded: false
    // Writes that arrive before the file is read are held and applied on top of
    // it, so a first-run click can never drop keys it has not seen yet.
    property var _pending: ({})

    // "es" | "en" when the file says so, "" otherwise (I18n applies the rest
    // of its precedence: QS_LANG -> settings -> LANG -> en).
    readonly property string language: {
        const value = Core.parseSettings(root.raw).language
        return (value === "es" || value === "en") ? value : ""
    }

    // 1..10; a missing or broken value falls back to the default. The bounds
    // come from the same place the clamp does, so the slider cannot drift.
    readonly property real scrollFactorMin: Core.MIN_SCROLL_FACTOR
    readonly property real scrollFactorMax: Core.MAX_SCROLL_FACTOR
    readonly property real scrollFactor: Core.normalizeScrollFactor(Core.parseSettings(root.raw).scrollFactor)

    // "grid" | "list" per panel (owner, round 6). Manga falls back to the old
    // single key, so the layout the user already had survives the upgrade.
    function viewModeFor(panel) {
        return Core.viewModeFor(Core.parseSettings(root.raw), panel)
    }


    // "sub" | "dub": the anime panel's audio mode. It reads like the language —
    // one preference, one key — so a DUB choice survives a restart.
    readonly property string animeMode: Core.normalizeAnimeMode(Core.parseSettings(root.raw).animeMode)

    function setSetting(key, value) {
        if (!root._loaded) {
            root._pending[key] = value
            return
        }
        root._write(key, value)
    }

    function _write(key, value) {
        root._touched = true
        root.raw = Core.withSetting(root.raw, key, value)
        writer.setText(root.raw)
    }

    function _flushPending() {
        const keys = Object.keys(root._pending)
        for (let i = 0; i < keys.length; i++)
            root._write(keys[i], root._pending[keys[i]])
        root._pending = ({})
    }

    function setLanguage(code) {
        root.setSetting("language", Core.normalizeLanguage(code))
    }

    function setScrollFactor(value) {
        root.setSetting("scrollFactor", Core.normalizeScrollFactor(value))
    }

    // The views pass their panel and "grid" / "list"; normalizing here means a
    // typo can never be what lands in the file (and the next read would ignore
    // it anyway).
    function setViewMode(panel, value) {
        root.setSetting(Core.viewModeKey(panel), Core.normalizeViewMode(value))
    }

    function setAnimeMode(value) {
        root.setSetting("animeMode", Core.normalizeAnimeMode(value))
    }

    FileView {
        id: reader
        path: root.settingsPath
        onLoaded: {
            root._newSeen = root.settingsDir === root._newDir
            root._loaded = true
            if (!root._touched)
                root.raw = reader.text()
            root._flushPending()
        }
        onLoadFailed: {
            // The new file is missing: if the inherited one exists, the probe
            // flips settingsDir and this read runs again there.
            if (root._oldSeen && root.settingsDir !== root._oldDir)
                return
            if (!root.oldChecked)
                return
            root._loaded = true
            if (!root._touched)
                root.raw = ""
            root._flushPending()
        }
    }

    // Does the inherited settings file exist? Read-only, never written.
    FileView {
        id: oldProbe
        path: root._oldDir + "/settings.json"
        onLoaded: {
            root._oldSeen = true
            root.oldChecked = true
            root._finishWhenProbeFindsNothing()
        }
        onLoadFailed: {
            root._oldSeen = false
            root.oldChecked = true
            root._finishWhenProbeFindsNothing()
        }
    }

    // The read of the new file can fail before this probe settles; when there is
    // no inherited file either, the path never changes and no second read comes,
    // so the empty settings are finished here (review finding R3-ProbeRace).
    function _finishWhenProbeFindsNothing() {
        if (!root.oldChecked || root._loaded)
            return
        if (root.settingsDir !== root._newDir)
            return          // a reload against the inherited file is coming
        root._loaded = true
        if (!root._touched)
            root.raw = ""
        root._flushPending()
    }

    FileView {
        id: writer
        path: root.settingsPath
    }

    // The config dir may not exist on a fresh setup; create it before writing —
    // but only once the probes have decided WHICH directory is the app's, or a
    // fresh `~/.config/kisaru` would be created next to the inherited one and
    // then block the migration's symlink.
    Process {
        id: ensureDir
        command: ["mkdir", "-p", root.settingsDir]
    }

    // QML change handlers cannot be generated for names starting with `_`,
    // so the probe flag is public.
    onOldCheckedChanged: if (root.oldChecked) ensureDir.running = true

    Component.onCompleted: {
        if (root.oldChecked) ensureDir.running = true
        reader.reload()
    }
}
