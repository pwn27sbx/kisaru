pragma Singleton
import Quickshell
import "app_paths.js" as Paths

// Where the anime/manga/novel backends live: one venv (made by install.sh)
// for all three servers, and the scripts shipped next to this config.
//
// The venv lives under the project's name (D6). There is no fallback to the
// inherited one on purpose: install.sh builds the new venv before this code can
// run, and a silent fallback would hide a broken install behind an old
// interpreter with old packages.
Singleton {
    readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share"
    readonly property string python: dataHome + "/" + Paths.DATA_DIR + "/venv/bin/python3"

    readonly property string animePython: python
    readonly property string mangaPython: python
    readonly property string novelPython: python

    readonly property string scripts: Quickshell.shellPath("scripts")
}
