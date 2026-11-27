import QtQuick
import Quickshell
import qs.app
import qs.Commons
import qs.services
import qs.modules.manga.components as MangaUI
import qs.modules.anime.components as AnimeUI
import qs.modules.novel.components as NovelUI
import "../../services/list_badge.js" as ListBadge

// Headless harness for the list row alignment (owner, 2026-11-27).
//
// It loads the REAL DetailView of one panel and its real singletons, with
// XDG_DATA_HOME/XDG_CONFIG_HOME pointed at a scratch folder by the runner, so
// the owner's library and settings are never read or written and no window of
// the owner's session is touched (offscreen platform).
//
// The fixture is the one the brief names: chapters 262, 262.2 and 271, plus long
// titles, so the badge column would be as wide as "Ch. 262.2" only. The
// measurement reads real geometry after a real layout: where each title starts,
// where the badge column starts and how wide it is, and where the row separator
// begins and ends.
//
// KH_SCENARIO
//   manga (default) · anime · novel
//
// Prints one `RESULT PASS|FAIL …` line with the measured pixels. Run through
// tests/row_align_harness/run.js or tests/list_row_alignment.test.js.

ShellRoot {
    // A plain Qt window on purpose (not FloatingWindow): it is a real
    // QQuickWindow, so `grabToImage` can save the PNG evidence under the
    // offscreen platform.
    Window {
        id: win

        // A panel-sized window, like the owner's ~560 px list.
        width: 560
        height: 620
        visible: true
        color: "#101010"

        readonly property string scenario: Quickshell.env("KH_SCENARIO") || "manga"
        // When set, the rendered window is saved as <scenario>.png there.
        readonly property string captureDir: Quickshell.env("KH_CAPTURE") || ""

        // The brief's fixture: a plain number, a decimal one (wider badge) and a
        // third number, with long titles so a title's own width cannot hide a
        // column that moves.
        readonly property var mangaChapters: [
            { id: "row-align-271", chapter: "271", title: "La continuación del sueño", publishAt: "2024-10-06" },
            { id: "row-align-2622", chapter: "262.2", title: "La batalla decisiva en el área deshabitada de Shinjuku, un título largo", publishAt: "2024-09-05" },
            { id: "row-align-262", chapter: "262", title: "Capítulo 262", publishAt: "2024-09-05" }
        ]

        readonly property var animeEpisodes: [
            { id: "row-align-ep1", number: "1" },
            { id: "row-align-ep100", number: "100" },
            { id: "row-align-ep10", number: "10" }
        ]

        readonly property var novelChapters: [
            { id: "row-align-n1", chapter: "1", title: "El comienzo de un viaje que no cabe en una línea" },
            { id: "row-align-n12", chapter: "12", title: "Un capítulo con un título larguísimo para forzar el ancho de la fila" },
            { id: "row-align-n122", chapter: "12.2", title: "Extra" }
        ]

        // The picker scenario: one chapter the source listed twice (a re-upload),
        // so the row shows the versions chip and the card has two rows whose
        // dates must not be cut.
        readonly property var versionedChapters: [
            { id: "row-align-v1", chapter: "1234.12", title: "Capítulo 1234.12", publishAt: "2026-04-09" },
            { id: "row-align-v2", chapter: "1234.12", title: "Capítulo 1234.12 (re-subida)", publishAt: "2026-04-21" },
            { id: "row-align-v0", chapter: "1234", title: "Capítulo 1234", publishAt: "2026-03-28" }
        ]

        property var chipFields: ({})

        // The title text each row must show: matched by text so the measurement
        // finds the title item without knowing the delegate's internals.
        readonly property var expectedTitles: {
            if (win.scenario === "manga") return win.mangaChapters.map(ch => ch.title)
            if (win.scenario === "novel") return win.novelChapters.map(ch => ch.title)
            return win.animeEpisodes.map(ep => KisaruI18n.t("episode", { 1: ep.number }))
        }

        function typeName(item) {
            const name = String(item)
            const open = name.indexOf("(")
            return open >= 0 ? name.slice(0, open) : name
        }

        function walk(item, fn) {
            if (!item) return
            fn(item)
            const kids = item.children
            if (!kids) return
            for (let i = 0; i < kids.length; i++) walk(kids[i], fn)
        }

        function firstOfType(item, prefix) {
            let hit = null
            walk(item, function (child) {
                if (!hit && typeName(child).indexOf(prefix) === 0) hit = child
            })
            return hit
        }

        function findList(view) {
            let hit = null
            walk(view, function (child) {
                if (hit || typeName(child).indexOf("ListView") < 0) return
                if (child.contentItem && child.contentItem.children.length > 0) hit = child
            })
            return hit
        }

        function titleOf(row) {
            const titles = win.expectedTitles
            let hit = null
            walk(row, function (child) {
                if (hit || child.text === undefined) return
                if (titles.indexOf(String(child.text)) >= 0) hit = child
            })
            return hit
        }

        function separatorOf(row) {
            const kids = row.children || []
            for (let i = 0; i < kids.length; i++) {
                const child = kids[i]
                if (Math.round(child.height) === 1 && Math.round(child.width) > 40) return child
            }
            return null
        }

        // What a row really contains, for a failure message: the type names are
        // the only stable thing to look at when a lookup misses.
        function typesIn(item) {
            const names = []
            walk(item, function (child) {
                const name = win.typeName(child)
                if (name !== "" && names.indexOf(name) < 0) names.push(name)
            })
            return names.slice(0, 12).join(",")
        }

        function spread(values) {
            if (values.length === 0) return 0
            return Math.max.apply(null, values) - Math.min.apply(null, values)
        }

        function rounded(value) {
            return Math.round(value * 10) / 10
        }

        function report(fields, pass, detail) {
            let line = "RESULT " + (pass ? "PASS" : "FAIL")
            for (const key of Object.keys(fields)) line += " " + key + "=" + fields[key]
            if (!pass && detail) line += " why=" + detail
            console.log(line)
            if (win.captureDir === "") {
                Qt.quit()
                return
            }
            win.contentItem.grabToImage(function(result) {
                if (!result.saveToFile(win.captureDir + "/" + win.scenario + ".png"))
                    console.log("CAPTURE FAILED " + win.scenario)
                Qt.quit()
            })
        }

        function feed() {
            if (win.scenario === "manga") {
                Manga.currentManga = {
                    id: "row-align-manga",
                    name: "Jujutsu Kaisen",
                    title: "Jujutsu Kaisen",
                    coverUrl: "",
                    authors: [],
                    status: "",
                    description: "",
                    chapters: win.mangaChapters
                }
            } else if (win.scenario === "picker") {
                Manga.currentManga = {
                    id: "row-align-picker",
                    name: "Jujutsu Kaisen",
                    title: "Jujutsu Kaisen",
                    coverUrl: "",
                    authors: [],
                    status: "",
                    description: "",
                    chapters: win.versionedChapters
                }
            } else if (win.scenario === "anime") {
                Anime.currentAnime = {
                    id: "row-align-anime",
                    name: "Demo Show",
                    englishName: "Demo Show",
                    episodes: win.animeEpisodes
                }
            } else {
                Novel.currentNovel = {
                    id: "row-align-novel",
                    name: "Demo Novel",
                    title: "Demo Novel",
                    author: "",
                    coverUrl: "",
                    status: "",
                    genres: [],
                    description: "",
                    partial: false,
                    chapters: win.novelChapters
                }
            }
        }

        function measure() {
            const view = viewLoader.item
            if (!view) return win.report({}, false, "no-view")
            const list = win.findList(view)
            if (!list) return win.report({}, false, "no-list")

            const rows = []
            const delegates = list.contentItem.children
            for (let i = 0; i < delegates.length; i++) {
                const row = delegates[i]
                if (!row.visible || row.height <= 40 || row.width <= 100) continue
                // The list may keep helper items next to the delegates; a row is
                // the thing that carries a badge.
                if (!win.firstOfType(row, "ListBadge")) continue
                rows.push(row)
            }
            if (rows.length < 3) return win.report({ rows: rows.length }, false, "few-rows:" + win.typesIn(list.contentItem))

            const inset = Style.space(ListBadge.ROW_INSET)
            const badgeX = [], badgeW = [], titleX = [], sepLeft = [], sepRight = [], bodyLeft = [], bodyRight = []
            for (const row of rows) {
                const badge = win.firstOfType(row, "ListBadge")
                const title = win.titleOf(row)
                const separator = win.separatorOf(row)
                if (!badge) return win.report({ rows: rows.length }, false, "no-badge:" + win.typesIn(row))
                if (!title) return win.report({ rows: rows.length }, false, "no-title:" + win.typesIn(row))
                if (!separator) return win.report({ rows: rows.length }, false, "no-separator:" + win.typesIn(row))

                const rowAt = row.mapToItem(view, 0, 0)
                const badgeAt = badge.mapToItem(view, 0, 0)
                const titleAt = title.mapToItem(view, 0, 0)
                const separatorAt = separator.mapToItem(view, 0, 0)

                bodyLeft.push(rowAt.x)
                bodyRight.push(rowAt.x + row.width)
                badgeX.push(badgeAt.x)
                badgeW.push(badge.width)
                titleX.push(titleAt.x)
                sepLeft.push(separatorAt.x)
                sepRight.push(separatorAt.x + separator.width)
            }

            // Every title on one x; the badge column (one width, one left edge)
            // starts where the separator starts; the separator ends where the
            // row's content ends.
            const titleSpread = win.spread(titleX)
            const badgeSpread = win.spread(badgeX)
            const widthSpread = win.spread(badgeW)
            let separatorAligned = true
            let separatorEnds = true
            for (let i = 0; i < rows.length; i++) {
                if (Math.abs(sepLeft[i] - badgeX[i]) > 0.5) separatorAligned = false
                if (Math.abs(sepLeft[i] - (bodyLeft[i] + inset)) > 0.5) separatorAligned = false
                if (Math.abs(sepRight[i] - (bodyRight[i] - inset)) > 0.5) separatorEnds = false
            }
            const titlesAfterBadges = titleX.every(function (x, i) {
                return x >= badgeX[i] + badgeW[i]
            })

            const pass = titleSpread < 0.5 && badgeSpread < 0.5 && widthSpread < 0.5
                && separatorAligned && separatorEnds && titlesAfterBadges

            let why = ""
            if (titleSpread >= 0.5) why = "title-x-spread"
            else if (badgeSpread >= 0.5) why = "badge-x-spread"
            else if (widthSpread >= 0.5) why = "badge-width-spread"
            else if (!separatorAligned) why = "separator-not-at-badge-left"
            else if (!separatorEnds) why = "separator-not-at-content-right"
            else if (!titlesAfterBadges) why = "title-inside-badge-column"

            win.report({
                scenario: win.scenario,
                rows: rows.length,
                inset: inset,
                rowLeft: win.rounded(bodyLeft[0]),
                rowRight: win.rounded(bodyRight[0]),
                badgeX: win.rounded(badgeX[0]),
                badgeW: win.rounded(badgeW[0]),
                titleX: win.rounded(titleX[0]),
                sepLeft: win.rounded(sepLeft[0]),
                sepRight: win.rounded(sepRight[0]),
                titleSpread: win.rounded(titleSpread),
                badgeSpread: win.rounded(badgeSpread),
                widthSpread: win.rounded(widthSpread)
            }, pass, why)
        }

        // ── versions chip + picker (owner, 2026-11-27) ────────────────────────
        function findPicker(view) {
            return win.firstOfType(view, "VersionPicker")
        }

        function measureChip() {
            const view = viewLoader.item
            if (!view) return win.report({}, false, "no-view")
            let label = null
            walk(view, function (child) {
                if (label || child.text === undefined) return
                if (win.typeName(child).indexOf("Text") < 0) return
                if (String(child.text).indexOf("▾") >= 0) label = child
            })
            if (!label) return win.report({}, false, "no-versions-chip")
            const chip = label.parent
            win.chipFields = {
                chipH: win.rounded(chip.height),
                chipRadius: win.rounded(chip.radius),
                chipBorder: win.rounded(chip.border.width),
                chipLabel: String(label.text) === KisaruI18n.tn("versions.count", 2) + " ▾" ? 1 : 0,
                chipHand: chip.cursorShape === Qt.PointingHandCursor ? 1 : 0
            }
            // Emit the chip's own signal: its click wiring is what opens the
            // same picker as before, and this checks it without a pointer.
            chip.clicked(null)
            pickerTimer.start()
        }

        function measurePicker() {
            const view = viewLoader.item
            const picker = win.findPicker(view)
            if (!picker || picker.opened !== true)
                return win.report(win.chipFields, false, "picker-closed")

            let titleText = null
            walk(picker, function (child) {
                if (titleText || child.text === undefined) return
                if (String(child.text) === KisaruI18n.t("versions.title")) titleText = child
            })
            if (!titleText) return win.report(win.chipFields, false, "picker-no-title")
            const card = titleText.parent.parent
            const chapterPrefix = KisaruI18n.t("chapter", { 1: "" }).trim()
            const readLabel = KisaruI18n.t("versions.read")
            const seriesLabel = KisaruI18n.t("versions.wholeSeries")

            const labels = []
            const actions = []
            walk(card, function (child) {
                if (child.text === undefined) return
                if (win.typeName(child).indexOf("Text") < 0) return
                const text = String(child.text)
                if (text.indexOf(chapterPrefix) === 0) labels.push(child)
                if (text === readLabel || text === seriesLabel) actions.push(text)
            })

            let truncated = 0
            let dated = 0
            for (const item of labels) {
                // `truncated` is the text's own verdict: elided, so a date is
                // lost. `contentWidth` would already be the elided width.
                if (item.truncated === true || item.implicitWidth > item.width + 0.5) truncated += 1
                if (String(item.text).indexOf("/2026") >= 0) dated += 1
            }
            const cardFits = card.width <= view.width - 2 * Gutter.left + 0.5
            const readCount = actions.filter(text => text === readLabel).length
            const seriesCount = actions.filter(text => text === seriesLabel).length

            const pass = labels.length === 2
                && truncated === 0
                && dated === labels.length
                && readCount === 2
                && seriesCount === 2
                && cardFits
                && win.chipFields.chipLabel === 1
                && win.chipFields.chipHand === 1
                && Math.abs(win.chipFields.chipH - Style.space(24)) < 0.5
                && Math.abs(win.chipFields.chipRadius - Style.cornerRadius) < 0.5
                && Math.abs(win.chipFields.chipBorder - Style.spacing.hairline) < 0.5

            let why = ""
            if (labels.length !== 2) why = "picker-rows"
            else if (truncated !== 0) why = "date-truncated"
            else if (dated !== labels.length) why = "date-missing"
            else if (readCount !== 2 || seriesCount !== 2) why = "picker-actions"
            else if (!cardFits) why = "card-wider-than-panel"
            else if (win.chipFields.chipLabel !== 1) why = "chip-label"
            else if (win.chipFields.chipHand !== 1) why = "chip-cursor"
            else if (Math.abs(win.chipFields.chipH - Style.space(24)) >= 0.5) why = "chip-height"
            else if (Math.abs(win.chipFields.chipRadius - Style.cornerRadius) >= 0.5) why = "chip-radius"
            else if (Math.abs(win.chipFields.chipBorder - Style.spacing.hairline) >= 0.5) why = "chip-border"

            win.report({
                scenario: win.scenario,
                rows: labels.length,
                panelW: win.rounded(view.width),
                gutter: win.rounded(Gutter.left),
                cardW: win.rounded(card.width),
                labelW: win.rounded(labels.length ? labels[0].width : 0),
                labelNeeds: win.rounded(labels.length ? labels[0].implicitWidth : 0),
                truncated: truncated,
                read: readCount,
                series: seriesCount,
                chipH: win.chipFields.chipH,
                chipRadius: win.chipFields.chipRadius,
                chipBorder: win.chipFields.chipBorder,
                chipHWant: win.rounded(Style.space(24)),
                chipRadiusWant: win.rounded(Style.cornerRadius),
                chipBorderWant: win.rounded(Style.spacing.hairline),
                chipLabel: win.chipFields.chipLabel,
                chipHand: win.chipFields.chipHand
            }, pass, why)
        }

        Loader {
            id: viewLoader
            anchors.fill: parent
            width: parent.width
            height: parent.height
            sourceComponent: (win.scenario === "manga" || win.scenario === "picker") ? mangaView
                : (win.scenario === "anime" ? animeView : novelView)
        }

        Component {
            id: mangaView
            MangaUI.DetailView { anchors.fill: parent }
        }

        Component {
            id: animeView
            AnimeUI.DetailView { anchors.fill: parent }
        }

        Component {
            id: novelView
            NovelUI.DetailView { anchors.fill: parent }
        }

        Timer {
            id: feedTimer
            interval: 100
            repeat: true
            running: true
            onTriggered: {
                if (!viewLoader.item) return
                stop()
                win.feed()
                layoutTimer.start()
            }
        }

        Timer {
            id: layoutTimer
            interval: 700
            onTriggered: win.scenario === "picker" ? win.measureChip() : win.measure()
        }

        Timer {
            id: pickerTimer
            interval: 500
            onTriggered: win.measurePicker()
        }
    }
}
