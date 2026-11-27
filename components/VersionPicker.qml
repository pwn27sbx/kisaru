import QtQuick
import QtQuick.Controls
import qs.app
import qs.Commons
import qs.services
import qs.components

// The uploads behind one chapter (owner, 2026-11-27).
//
// A source can list the same chapter twice — "1" and "1.1", a later re-upload.
// The Detail row shows one chapter and opens this card to choose which upload
// to read or download. The rows arrive already resolved by the caller
// (modules/manga/components/DetailView.qml): number, date, group, generation
// and the download state of that version; this file only draws them.
//
// Option B (owner, 2026-11-27): the row IS the action. Clicking it reads that
// chapter with that upload, so the old "Read" chip — a button inside the row
// that duplicated it — is gone. The only controls are the two trailing icons:
// the books glyph settles that upload's generation for the whole series (filled
// when it is the generation already applied, with its tooltip explaining it)
// and ↓ downloads that upload. A ✓ marks the version being read.
//
// The card is as wide as its longest row needs and no wider than the panel: a
// row used to cut the date of the upload ("21/04/20…") because the card was a
// fixed 220.
Item {
    id: root

    property bool opened: false
    property var rows: []
    property string currentId: ""
    // The upload generation already applied to the whole series ("" when the
    // reader has not applied one). The books icon lights up on that row.
    property string seriesGeneration: ""
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

    // The action the reader took. The row reads this chapter (false); the books
    // icon settles the upload's generation for the whole series (true). The
    // caller reads `wholeSeries` when it takes the pick.
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
    readonly property real _checkWidth: Style.space(12)
    readonly property real _controlWidth: Style.space(28)
    // One row, measured as it paints: the check slot, the label, the books icon
    // and the download control, with the row's own margins. The last xxl is the
    // air between the label and the icons, so a long date never hugs them.
    readonly property real _lineWidth:
        Style.spacing.sm + root._checkWidth
        + Style.spacing.xs + root._labelWidth
        + Style.spacing.xs + root._controlWidth
        + Style.spacing.xs + root._controlWidth
        + Style.spacing.xs + Style.spacing.xxl
    readonly property real _cardWidth: Math.min(parent.width - 2 * Gutter.left,
        Math.max(Style.space(330),
            root._lineWidth + 2 * Style.spacing.xxl + 2 * Style.spacing.hairline))

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
                            // Same generation as the one applied to the whole
                            // series ("" never matches: no series pick yet).
                            readonly property bool seriesActive:
                                root.seriesGeneration !== ""
                                && modelData.generation === root.seriesGeneration
                            readonly property bool focused: index === root.focusIndex
                            width: list.width
                            height: body.implicitHeight + 2 * Style.spacing.sm
                            // A layered hover: surface_container is darker than
                            // this card's surface_container_high, so the token
                            // ladder alone made the hover vanish.
                            color: hovered
                                ? Style.hoverFillFor(Colors.on_surface, Colors.primary)
                                : Colors.clear(Style.hoverFillFor(Colors.on_surface, Colors.primary))
                            border.color: focused && !current ? Colors.primary : Colors.clear(Colors.primary)
                            border.width: focused && !current ? Style.spacing.hairline : 0
                            Behavior on color { ColorAnimation { duration: Motion.fast } }

                            Row {
                                id: body
                                anchors {
                                    left: parent.left; right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: Style.spacing.sm; rightMargin: Style.spacing.xs
                                }
                                spacing: Style.spacing.xs

                                // The version being read. The slot stays
                                // reserved so both labels start on one x.
                                Item {
                                    id: checkSlot
                                    width: root._checkWidth
                                    height: Style.font.subtitle
                                    anchors.verticalCenter: parent.verticalCenter

                                    StyledText {
                                        anchors.centerIn: parent
                                        visible: row.current
                                        text: "✓"
                                        font.family: root.bodyFont
                                        font.pixelSize: Style.font.subtitle
                                        font.bold: true
                                        color: Colors.primary
                                    }
                                }

                                Column {
                                    id: labels
                                    width: parent.width - checkSlot.width - controls.width - 2 * parent.spacing
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Style.spacing.hairline

                                    StyledText {
                                        width: parent.width
                                        text: root._label(row.modelData)
                                        font.family: root.bodyFont
                                        font.pixelSize: Style.font.bodySmall
                                        font.bold: row.current
                                        color: Colors.on_surface
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        width: parent.width
                                        visible: row.modelData.group !== ""
                                        text: row.modelData.group
                                        textFormat: Text.PlainText
                                        font.family: root.bodyFont
                                        font.pixelSize: Style.font.caption
                                        color: Colors.on_surface_variant
                                        opacity: 0.7
                                        elide: Text.ElideRight
                                    }
                                }

                                Row {
                                    id: controls
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Style.spacing.xs

                                    // "Use this version for the whole series":
                                    // filled when this upload's generation is
                                    // already the one applied to the series.
                                    Rectangle {
                                        id: seriesControl
                                        width: root._controlWidth
                                        height: Style.space(24)
                                        radius: Style.cornerRadius
                                        color: row.seriesActive
                                            ? Colors.primary
                                            : seriesArea.containsMouse
                                                ? Style.hoverFillFor(Colors.on_surface, Colors.primary)
                                                : Colors.clear(Style.hoverFillFor(Colors.on_surface, Colors.primary))
                                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                                        StyledText {
                                            anchors.centerIn: parent
                                            text: "󰂻"
                                            font.family: root.bodyFont
                                            font.pixelSize: Style.font.heading
                                            color: row.seriesActive ? Colors.on_primary : Colors.on_surface_variant
                                        }

                                        MouseArea {
                                            id: seriesArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root._read(row.modelData.id, true)
                                        }

                                        ToolTip {
                                            id: seriesTip
                                            visible: seriesArea.containsMouse
                                            text: KisaruI18n.t("versions.wholeSeriesTooltip")
                                            delay: 400
                                            padding: Style.space(0)

                                            background: Rectangle {
                                                color: Colors.surface_container_highest
                                                border.color: Colors.outline_variant
                                                border.width: Style.spacing.hairline
                                            }
                                            contentItem: Text {
                                                text: seriesTip.text
                                                textFormat: Text.PlainText
                                                color: Colors.on_surface
                                                font.family: root.bodyFont
                                                font.pixelSize: Style.font.bodySmall
                                                leftPadding: Style.spacing.controlPaddingX
                                                rightPadding: Style.spacing.controlPaddingX
                                                topPadding: Style.spacing.controlPaddingY
                                                bottomPadding: Style.spacing.controlPaddingY
                                            }
                                        }
                                    }

                                    // Download one upload, not the whole chapter.
                                    Rectangle {
                                        id: downloadControl
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: row.modelData.downloadsVisible !== false
                                        width: root._controlWidth; height: Style.space(24)
                                        radius: Style.cornerRadius
                                        color: downloadArea.containsMouse
                                            ? Style.hoverFillFor(Colors.on_surface, Colors.primary)
                                            : Colors.clear(Style.hoverFillFor(Colors.on_surface, Colors.primary))
                                        readonly property string kind: row.modelData.state
                                        readonly property string glyph: root._glyph(row.modelData)

                                        Behavior on color { ColorAnimation { duration: Motion.fast } }

                                        StyledText {
                                            anchors.centerIn: parent
                                            text: downloadControl.glyph
                                            font.family: root.bodyFont
                                            font.pixelSize: downloadControl.kind === "downloading"
                                                ? Style.font.caption : Style.font.bodySmall
                                            color: downloadControl.kind === "downloaded"
                                                ? Colors.primary : Colors.on_surface_variant
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
                            }

                            onClicked: root._read(row.modelData.id, false)
                        }
                    }
                }
            }
        }
    }

    // Measuring only, never drawn: the rows' exact label font (bold is the
    // widest state a row can be in), so the card is sized by what it really
    // paints instead of a guess.
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
    }
}
