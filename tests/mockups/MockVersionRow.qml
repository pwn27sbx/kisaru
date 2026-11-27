import QtQuick
import qs.app
import qs.Commons
import qs.components

// One version row of the redesign mockups (owner, 2026-11-27).
//
// Mockup-only file: it lives under tests/mockups/ and never replaces
// components/VersionPicker.qml. It paints option B's row — a plain row whose
// click reads that upload — with the check that marks the version being read
// and the two trailing controls (whole series, download). Option A reuses it
// with `showSeries: false`.
Rectangle {
    id: root

    property string label: ""
    property string group: ""
    property bool current: false
    property bool showSeries: false
    property bool seriesActive: false
    property bool rowHovered: false
    property bool seriesHovered: false

    readonly property int controlWidth: Style.space(28)
    readonly property int controlHeight: Style.space(24)
    // Distance from the row's right edge to the centre of the whole-series
    // control: the card positions the tooltip under it.
    readonly property real seriesCenterFromRight:
        Style.spacing.xs + controlWidth + Style.spacing.xs + controlWidth / 2

    width: parent ? parent.width : 0
    height: body.implicitHeight + 2 * Style.spacing.sm
    color: root.rowHovered ? Style.hoverFillFor(Colors.on_surface, Colors.primary)
        : Colors.clear(Style.hoverFillFor(Colors.on_surface, Colors.primary))
    radius: Style.cornerRadius
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }

    Row {
        id: body
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: Style.spacing.sm
            rightMargin: Style.spacing.xs
        }
        spacing: Style.spacing.xs

        // The version being read. The slot is always reserved so the labels of
        // both rows start on the same x.
        Item {
            id: checkSlot
            width: Style.space(12)
            height: Style.font.bodySmall
            anchors.verticalCenter: parent.verticalCenter

            StyledText {
                anchors.centerIn: parent
                visible: root.current
                text: "✓"
                font.pixelSize: Style.font.subtitle
                font.bold: true
                color: Colors.primary
            }
        }

        Column {
            id: textColumn
            width: parent.width - checkSlot.width - trailing.width - 2 * body.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.hairline

            StyledText {
                width: parent.width
                text: root.label
                elide: Text.ElideRight
                font.pixelSize: Style.font.bodySmall
                font.bold: root.current
                color: Colors.on_surface
            }

            StyledText {
                width: parent.width
                visible: root.group !== ""
                text: root.group
                elide: Text.ElideRight
                font.pixelSize: Style.font.caption
                color: Colors.on_surface_variant
                opacity: 0.8
            }
        }

        Row {
            id: trailing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xs

            // "Use this version for the whole series". Solid accent when this
            // upload's generation is the one applied to the series.
            Rectangle {
                id: seriesControl
                visible: root.showSeries
                width: root.showSeries ? root.controlWidth : 0
                height: root.controlHeight
                radius: Style.cornerRadius
                color: root.seriesActive ? Colors.primary
                    : root.seriesHovered ? Style.hoverFillFor(Colors.on_surface, Colors.primary)
                    : Colors.clear(Style.hoverFillFor(Colors.on_surface, Colors.primary))

                StyledText {
                    anchors.centerIn: parent
                    text: "󰂻"
                    font.pixelSize: Style.font.heading
                    color: root.seriesActive ? Colors.on_primary : Colors.on_surface_variant
                }
            }

            // The same ↓ the chapter list already paints for one download.
            Rectangle {
                id: downloadControl
                width: root.controlWidth
                height: root.controlHeight
                radius: Style.cornerRadius
                color: Colors.clear(Colors.surface_container_high)

                StyledText {
                    anchors.centerIn: parent
                    text: "↓"
                    font.pixelSize: Style.font.bodySmall
                    color: Colors.on_surface_variant
                }
            }
        }
    }
}
