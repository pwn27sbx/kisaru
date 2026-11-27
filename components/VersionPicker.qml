import QtQuick
import qs.app
import qs.Commons
import qs.services
import qs.components

// The uploads behind one chapter (owner, 2026-11-27).
//
// A source can list the same chapter twice — "1" and "1.1", a later re-upload.
// The Detail row shows one chapter and opens this card to choose which upload
// to read or download. The rows arrive already resolved by the caller
// (modules/manga/components/DetailView.qml): number, date, group and the
// download state of that version; this file only draws them.
//
// Picking is explicit (owner, 2026-11-27): every row offers "Read" (that upload
// for this chapter) and "Use for whole series" (that upload's generation for
// every chapter). The old flow asked for a scope in a tick box BEFORE the
// version, so the owner read it as "nothing happens" and had to guess.
//
// The card is as wide as its longest row needs and no wider than the panel: a
// row used to cut the date of the upload ("21/04/20…") because the card was a
// fixed 220.
Item {
    id: root

    property bool opened: false
    property var rows: []
    property string currentId: ""
    property bool wholeSeries: false
    property string bodyFont: Style.font.family
    // The row the keyboard is on: Up/Down move it and Enter reads it.
    property int focusIndex: 0

    signal chosen(string versionId)
    signal downloadRequested(string versionId)
    signal closed()

    visible: opened
    z: 400

    // "Chapter 8.1 · 21/04/2026". One expression, so the row and the width
    // measurement below can never disagree about the longest label.
    function _label(row) {
        return KisaruI18n.t("chapter", { 1: row.number })
            + (row.date !== "" ? " · " + row.date : "")
    }

    // Dismiss without choosing: the caller clears its own state on `closed`.
    function _dismiss() {
        root.opened = false
        root.closed()
    }

    // One branch per state, so the glyph and the progress text stay readable.
    function _glyph(row) {
        if (row.state === "downloaded") return "✓"
        if (row.state === "error") return "!"
        if (row.state === "downloading") {
            return row.total > 0 ? row.done + "/" + row.total : "…"
        }
        return "↓"
    }

    function _choose(id) {
        root.opened = false
        root.chosen(id)
    }

    // The explicit per-row action. The scope is the action the reader clicked,
    // never a tick left behind from before; the caller reads `wholeSeries` when
    // it takes the pick.
    function _read(id, wholeSeries) {
        root.wholeSeries = wholeSeries === true
        root._choose(id)
    }

    function _readFocused() {
        const row = root.rows[root.focusIndex]
        if (row) root._read(row.id, false)
    }

    function _moveFocus(step) {
        const last = root.rows.length - 1
        if (last < 0) return
        root.focusIndex = Math.max(0, Math.min(last, root.focusIndex + step))
    }

    onOpenedChanged: {
        if (!opened) return
        // Enter acts on the version the reader is already on.
        for (let i = 0; i < rows.length; i++)
            if (rows[i].id === currentId) focusIndex = i
        Qt.callLater(function() { card.forceActiveFocus() })
    }

    // ── Width: the longest row, capped by the panel ───────────────────────────
    readonly property real _labelWidth: {
        let widest = 0
        for (let i = 0; i < labelProbes.count; i++) {
            const width = labelProbes.itemAt(i).implicitWidth
            if (width > widest) widest = width
        }
        return widest
    }
    // The label line: the text, the gap, and the download control.
    readonly property real _lineWidth: root._labelWidth + Style.spacing.xs + Style.space(28)
    // The action line: both buttons, measured as the buttons themselves.
    readonly property real _actionsWidth:
        readProbe.implicitWidth + Style.spacing.sm + seriesProbe.implicitWidth
    readonly property real _contentWidth: Math.max(root._lineWidth, root._actionsWidth)
    readonly property real _cardWidth: Math.min(parent.width - 2 * Gutter.left,
        Math.max(Style.space(220),
            root._contentWidth + 2 * Style.spacing.xxl + 2 * Style.spacing.sm
            + 2 * Style.spacing.hairline))

    Rectangle {
        anchors.fill: parent
        color: Colors.withAlpha(Colors.background, 0.86)
        MouseArea {
            anchors.fill: parent
            onClicked: root._dismiss()
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: root._cardWidth
        height: content.implicitHeight + 2 * Style.spacing.xxl
        color: Colors.surface_container_high
        border.color: Colors.outline_variant
        border.width: Style.spacing.hairline
        radius: Style.cornerRadius
        focus: true
        Keys.onEscapePressed: root._dismiss()
        Keys.onUpPressed: root._moveFocus(-1)
        Keys.onDownPressed: root._moveFocus(1)
        Keys.onReturnPressed: root._readFocused()
        Keys.onEnterPressed: root._readFocused()

        Column {
            id: content
            anchors {
                left: parent.left; right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: Style.spacing.xxl; rightMargin: Style.spacing.xxl
            }
            spacing: Style.spacing.sm

            StyledText {
                width: parent.width
                text: KisaruI18n.t("versions.title")
                font.family: root.bodyFont
                font.pixelSize: Style.font.body
                font.bold: true
                color: Colors.on_surface
            }

            Flickable {
                width: parent.width
                height: Math.min(list.height, Style.space(220))
                contentHeight: list.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: list
                    width: parent.width

                    Repeater {
                        model: root.rows

                        delegate: ClickableRect {
                            id: row
                            required property var modelData
                            required property int index
                            readonly property bool current: modelData.id === root.currentId
                            readonly property bool focused: index === root.focusIndex
                            width: list.width
                            height: body.implicitHeight + 2 * Style.spacing.xs
                            color: current
                                ? Colors.primary
                                : (hovered ? Colors.surface_container : Colors.clear(Colors.surface_container))
                            border.color: focused && !current ? Colors.primary : Colors.clear(Colors.primary)
                            border.width: focused && !current ? Style.spacing.hairline : 0
                            Behavior on color { ColorAnimation { duration: Motion.fast } }

                            Column {
                                id: body
                                anchors {
                                    left: parent.left; right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: Style.spacing.sm; rightMargin: Style.spacing.sm
                                }
                                spacing: Style.spacing.xs

                                Row {
                                    width: parent.width
                                    spacing: Style.spacing.xs

                                    Column {
                                        width: parent.width - downloadControl.width - parent.spacing
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Style.spacing.hairline

                                        StyledText {
                                            width: parent.width
                                            text: root._label(row.modelData)
                                            font.family: root.bodyFont
                                            font.pixelSize: Style.font.bodySmall
                                            font.bold: row.current
                                            color: row.current ? Colors.on_primary : Colors.on_surface
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            width: parent.width
                                            visible: row.modelData.group !== ""
                                            text: row.modelData.group
                                            textFormat: Text.PlainText
                                            font.family: root.bodyFont
                                            font.pixelSize: Style.font.caption
                                            color: row.current ? Colors.on_primary : Colors.on_surface_variant
                                            opacity: row.current ? 0.9 : 0.7
                                            elide: Text.ElideRight
                                        }
                                    }

                                    // Download one upload, not the whole chapter.
                                    Rectangle {
                                        id: downloadControl
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: row.modelData.downloadsVisible !== false
                                        width: Style.space(28); height: Style.space(24)
                                        radius: Style.cornerRadius
                                        color: downloadArea.containsMouse && !row.current
                                            ? Colors.surface_container_high : Colors.clear(Colors.surface_container_high)
                                        readonly property string kind: row.modelData.state
                                        readonly property string glyph: root._glyph(row.modelData)

                                        StyledText {
                                            anchors.centerIn: parent
                                            text: downloadControl.glyph
                                            font.family: root.bodyFont
                                            font.pixelSize: downloadControl.kind === "downloading"
                                                ? Style.font.caption : Style.font.bodySmall
                                            color: downloadControl.kind === "downloaded"
                                                ? (row.current ? Colors.on_primary : Colors.primary)
                                                : (row.current ? Colors.on_primary : Colors.on_surface_variant)
                                        }
                                        MouseArea {
                                            id: downloadArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: (downloadControl.kind === "idle"
                                                          || downloadControl.kind === "error")
                                                ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: {
                                                if (downloadControl.kind === "idle"
                                                        || downloadControl.kind === "error")
                                                    root.downloadRequested(row.modelData.id)
                                            }
                                        }
                                    }
                                }

                                // The explicit actions: read this chapter with
                                // this upload, or settle the upload for the
                                // whole series (owner, 2026-11-27).
                                Row {
                                    spacing: Style.spacing.sm

                                    Chip {
                                        text: KisaruI18n.t("versions.read")
                                        bodyFont: root.bodyFont
                                        onAccent: row.current
                                        onClicked: root._read(row.modelData.id, false)
                                    }
                                    Chip {
                                        text: KisaruI18n.t("versions.wholeSeries")
                                        bodyFont: root.bodyFont
                                        onAccent: row.current
                                        onClicked: root._read(row.modelData.id, true)
                                    }
                                }
                            }

                            onClicked: root._read(row.modelData.id, false)
                        }
                    }
                }
            }
        }
    }

    // Measuring only, never drawn: the rows' exact label font (bold is the
    // widest state a row can be in) and the two action buttons themselves, so
    // the card is sized by what it really paints instead of a guess.
    Item {
        visible: false

        Repeater {
            id: labelProbes
            model: root.rows

            delegate: StyledText {
                visible: false
                text: root._label(modelData)
                font.family: root.bodyFont
                font.pixelSize: Style.font.bodySmall
                font.bold: true
            }
        }

        Chip {
            id: readProbe
            visible: false
            text: KisaruI18n.t("versions.read")
            bodyFont: root.bodyFont
        }
        Chip {
            id: seriesProbe
            visible: false
            text: KisaruI18n.t("versions.wholeSeries")
            bodyFont: root.bodyFont
        }
    }
}
