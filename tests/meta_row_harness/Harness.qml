import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.app
import qs.services
import qs.modules.anime.components

// Headless harness for the two owner-reported Detail bugs (2026-11-27).
//
// It loads the REAL modules/anime/components/DetailView.qml and the real
// singletons, with XDG_DATA_HOME/XDG_CONFIG_HOME pointed at a scratch folder by
// the runner, so the owner's library and settings are never read or written.
// No window of the owner's session is touched: this runs with the offscreen
// platform.
//
// KH_SCENARIO
//   meta   open a library entry and measure the meta bar: row 1 must stay (count
//          + last-watched badge) and row 2 must render its Skip, Folder and
//          Hide controls. On 70c3f2d row 2 measures 0 because
//          `metaActionsRow.visible` ORed its own children's effective `visible`.
//   flash  animate a hover fill from its off colour to Colors.surface_container
//          twice: with "transparent" (the old pattern) and with Colors.clear()
//          (the fixed one). No sampled frame of the fixed one may be darker than
//          both endpoints; the old one must dip below them, which is the dark
//          flash the owner saw.
//
// Prints one `RESULT PASS|FAIL …` line. Run through tests/meta_row_harness/run.js
// or the two node tests.

ShellRoot {
    FloatingWindow {
        id: win
        implicitWidth: 550
        implicitHeight: 900
        visible: true
        color: "#101010"

        readonly property string scenario: Quickshell.env("KH_SCENARIO") || "meta"

        DetailView {
            id: view
            anchors.fill: parent
            visible: win.scenario === "meta"
        }

        // ── meta scenario ────────────────────────────────────────────────────
        readonly property var show: ({
            id: "demo-1",
            name: "Demo Show",
            englishName: "Demo Show",
            thumbnail: "",
            score: 8.1,
            episodes: [
                { id: "demo-1-1", number: 1 },
                { id: "demo-1-2", number: 2 },
                { id: "demo-1-3", number: 3 }
            ]
        })

        function typeName(item) {
            var name = String(item)
            var open = name.indexOf("(")
            return open >= 0 ? name.slice(0, open) : name
        }

        function walk(item, fn) {
            if (!item) return
            fn(item)
            var kids = item.children
            if (!kids) return
            for (var i = 0; i < kids.length; i++) walk(kids[i], fn)
        }

        // The meta bar is the only ColumnLayout laid out as two stacked rows.
        function findMetaColumn(root) {
            var hit = null
            walk(root, function (item) {
                if (hit || typeName(item).indexOf("ColumnLayout") < 0) return
                var rows = []
                var kids = item.children
                for (var i = 0; i < kids.length; i++)
                    if (typeName(kids[i]).indexOf("RowLayout") >= 0) rows.push(kids[i])
                if (rows.length >= 2) hit = { column: item, row1: rows[0], row2: rows[1] }
            })
            return hit
        }

        function visibleTexts(root) {
            var seen = []
            walk(root, function (item) {
                if (item.text === undefined) return
                var text = String(item.text)
                if (text !== "") seen.push({ text: text, visible: item.visible })
            })
            return seen
        }

        function hasVisibleText(seen, prefix) {
            for (var i = 0; i < seen.length; i++)
                if (seen[i].visible && seen[i].text.indexOf(prefix) === 0) return true
            return false
        }

        function measureMeta() {
            var meta = findMetaColumn(view)
            if (!meta) { console.log("RESULT FAIL no-meta-column"); Qt.quit(); return }

            var seen = visibleTexts(view)
            var counts = hasVisibleText(seen, "3 episodes")
            var lastWatched = hasVisibleText(seen, "Last: Ep. 3")
            var skip = hasVisibleText(seen, "Skip")
            var folder = hasVisibleText(seen, "Folder")
            var hide = hasVisibleText(seen, "Hide")

            var row1H = Math.round(meta.row1.height)
            var row2H = Math.round(meta.row2.height)
            var barH = meta.column.parent ? Math.round(meta.column.parent.height) : -1

            var pass = row2H > 0 && barH >= row1H + row2H
                && counts && lastWatched && skip && folder && hide
            console.log("RESULT " + (pass ? "PASS" : "FAIL")
                + " metaBarH=" + barH + " row1H=" + row1H + " row2H=" + row2H
                + " count=" + (counts ? 1 : 0) + " last=" + (lastWatched ? 1 : 0)
                + " skip=" + (skip ? 1 : 0) + " folder=" + (folder ? 1 : 0)
                + " hide=" + (hide ? 1 : 0))
            Qt.quit()
        }

        Timer {
            id: openDetail
            interval: 50
            repeat: true
            running: win.scenario === "meta"
            onTriggered: {
                if (!Anime.libraryLoaded || Anime.currentAnime !== null) return
                stop()
                Anime.currentAnime = win.show
                measure.start()
            }
        }

        Timer {
            id: measure
            interval: 600
            onTriggered: win.measureMeta()
        }

        // ── flash scenario ───────────────────────────────────────────────────
        Item {
            id: flash
            anchors.fill: parent
            visible: win.scenario === "flash"

            readonly property color bg: Colors.background
            readonly property color target: Colors.surface_container
            property var newSamples: []
            property var oldSamples: []

            function lum(rgb) {
                return 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b
            }

            // What the eye sees: the animated colour composited over the row.
            function lumOver(c) {
                var a = c.a
                return lum({
                    r: c.r * a + flash.bg.r * (1 - a),
                    g: c.g * a + flash.bg.g * (1 - a),
                    b: c.b * a + flash.bg.b * (1 - a)
                })
            }

            Rectangle { anchors.fill: parent; color: flash.bg }

            Rectangle {
                id: newRect
                x: 20; y: 20; width: 200; height: 50
                property bool hot: false
                color: hot ? flash.target : Colors.clear(flash.target)
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            // The pattern exactly as 70c3f2d had it: kept as the measurement's
            // negative control, never used by the views.
            Rectangle {
                id: oldRect
                x: 20; y: 90; width: 200; height: 50
                property bool hot: false
                color: hot ? flash.target : "transparent"
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }

            Timer {
                id: sampler
                interval: 4
                repeat: true
                onTriggered: {
                    flash.newSamples.push(flash.lumOver(newRect.color))
                    flash.oldSamples.push(flash.lumOver(oldRect.color))
                }
            }

            function min(values) {
                var out = Infinity
                for (var i = 0; i < values.length; i++) if (values[i] < out) out = values[i]
                return out
            }

            function max(values) {
                var out = -Infinity
                for (var i = 0; i < values.length; i++) if (values[i] > out) out = values[i]
                return out
            }

            function report() {
                sampler.stop()
                var bgLum = flash.lumOver(flash.bg)
                var targetLum = flash.lumOver(flash.target)
                var floorY = Math.min(bgLum, targetLum)
                var newMin = flash.min(flash.newSamples)
                var oldMin = flash.min(flash.oldSamples)
                // The fade must have actually run: a binding that threw (for
                // example a missing Colors.clear) leaves the colour parked.
                var span = flash.max(flash.newSamples) - newMin
                var fixed = flash.newSamples.length > 5
                    && newMin >= floorY - 0.004
                // The control proves the metric sees the bug at all; if the
                // theme made "transparent" harmless this scenario says so.
                var control = oldMin < floorY - 0.01
                var pass = fixed && control && span > 0.005
                console.log("RESULT " + (pass ? "PASS" : "FAIL")
                    + " samples=" + flash.newSamples.length
                    + " bgLum=" + bgLum.toFixed(4)
                    + " targetLum=" + targetLum.toFixed(4)
                    + " newMin=" + newMin.toFixed(4)
                    + " oldMin=" + oldMin.toFixed(4)
                    + " span=" + span.toFixed(4))
                Qt.quit()
            }

            Component.onCompleted: {
                if (win.scenario !== "flash") return
                if (typeof Colors.clear !== "function") {
                    console.log("RESULT FAIL missing-Colors.clear")
                    Qt.quit()
                    return
                }
                start.start()
            }

            Timer {
                id: start
                interval: 200
                onTriggered: {
                    sampler.start()
                    newRect.hot = true
                    oldRect.hot = true
                    finish.start()
                }
            }

            Timer {
                id: finish
                interval: 400
                onTriggered: flash.report()
            }
        }
    }
}
