pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "motion_prefs.js" as Prefs

// "Reduce motion" for the whole app, read from the desktop once per session.
//
// The rule lives in services/motion_prefs.js (unit-tested by
// tests/motion_prefs.test.js); this singleton only feeds it the two sources:
// the KISARU_REDUCED_MOTION override and GTK's own switch. Both GTK files are
// probed because a machine may have only one of them, and a missing file is not
// an error: it just means "the desktop said nothing".
Singleton {
    id: root

    readonly property string configHome:
        Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string override: Quickshell.env("KISARU_REDUCED_MOTION")

    property string _gtk4Text: ""
    property string _gtk3Text: ""
    property bool _gtk4Loaded: false
    property bool _gtk3Loaded: false

    readonly property string gtkText: root._gtk4Loaded ? root._gtk4Text
        : root._gtk3Loaded ? root._gtk3Text : ""
    readonly property bool reduced: Prefs.reduced(root.override, root.gtkText)

    FileView {
        id: gtk4
        path: root.configHome + "/gtk-4.0/settings.ini"
        printErrors: false
        onLoaded: {
            root._gtk4Text = gtk4.text()
            root._gtk4Loaded = true
        }
    }

    FileView {
        id: gtk3
        path: root.configHome + "/gtk-3.0/settings.ini"
        printErrors: false
        onLoaded: {
            root._gtk3Text = gtk3.text()
            root._gtk3Loaded = true
        }
    }
}
