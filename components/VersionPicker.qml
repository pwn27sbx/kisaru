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
Item {
    id: root

    property bool opened: false
    property var rows: []
    property string currentId: ""
    property bool wholeSeries: false
    property string bodyFont: Style.font.family

    signal chosen(string versionId)
    signal downloadRequested(string versionId)
    signal closed()

    visible: opened
    z: 400

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

    onOpenedChanged: if (opened) Qt.callLater(function() { card.forceActiveFocus() })

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
        width: Math.min(parent.width - 2 * Gutter.left, Style.space(220))
        height: content.implicitHeight + 2 * Style.spacing.xxl
        color: Colors.surface_container_high
        border.color: Colors.outline_variant
        border.width: Style.spacing.hairline
        radius: Style.cornerRadius
        focus: true
        Keys.onEscapePressed: root._dismiss()

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
                            readonly property bool current: modelData.id === root.currentId
                            width: list.width
                            height: Style.space(34)
                            color: current
                                ? Colors.primary
                                : (hovered ? Colors.surface_container : Colors.clear(Colors.surface_container))

                            Row {
                                anchors {
                                    left: parent.left; verticalCenter: parent.verticalCenter
                                    leftMargin: Style.spacing.sm
                                    rightMargin: Style.spacing.sm
                                }
                                width: parent.width - 2 * Style.spacing.sm
                                spacing: Style.spacing.xs

                                Column {
                                    width: parent.width - downloadControl.width - Style.spacing.xs
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Style.spacing.hairline

                                    StyledText {
                                        width: parent.width
                                        text: KisaruI18n.t("chapter", { 1: row.modelData.number })
                                            + (row.modelData.date !== "" ? " · " + row.modelData.date : "")
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

                            onClicked: root._choose(row.modelData.id)
                        }
                    }

                    Rectangle {
                        width: list.width
                        height: 1
                        color: Colors.outline_variant
                        opacity: 0.4
                    }

                    // "Use this version for the whole series" (owner): the
                    // pick then applies to every chapter that has this upload
                    // batch, so switching 66 chapters stops being 66 actions.
                    ClickableRect {
                        id: wholeSeriesRow
                        width: list.width
                        height: Math.max(Style.space(26), wholeSeriesLabel.implicitHeight + Style.spacing.xs)
                        color: hovered ? Colors.surface_container : Colors.clear(Colors.surface_container)

                        Row {
                            anchors {
                                left: parent.left; right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: Style.spacing.sm; rightMargin: Style.spacing.sm
                            }
                            spacing: Style.spacing.xs

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Style.space(12); height: Style.space(12)
                                radius: Style.spacing.hairline
                                border.color: root.wholeSeries ? Colors.primary : Colors.outline_variant
                                border.width: Style.spacing.hairline
                                color: root.wholeSeries ? Colors.primary : Colors.clear(Colors.primary)

                                StyledText {
                                    anchors.centerIn: parent
                                    visible: root.wholeSeries
                                    text: "✓"
                                    font.family: root.bodyFont
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                    color: Colors.on_primary
                                }
                            }

                            StyledText {
                                id: wholeSeriesLabel
                                width: parent.width - Style.space(18)
                                text: KisaruI18n.t("versions.wholeSeries")
                                font.family: root.bodyFont
                                font.pixelSize: Style.font.caption
                                color: Colors.on_surface
                                wrapMode: Text.WordWrap
                            }
                        }

                        onClicked: root.wholeSeries = !root.wholeSeries
                    }
                }
            }
        }
    }
}
