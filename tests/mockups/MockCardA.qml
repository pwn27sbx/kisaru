import QtQuick
import qs.app
import qs.Commons
import qs.components
import qs.Ui

// Option A, variant for comparison (owner, 2026-11-27): plain rows (click =
// read) plus one switch under the list, "Remember for the whole series". When
// it is on, the version the reader clicks also becomes the series generation.
//
// Mockup-only: never wired into the app.
Rectangle {
    id: card

    property bool rowHovered: false
    property bool toggleOn: false

    width: Style.space(330)
    height: content.implicitHeight + 2 * Style.spacing.xxl
    color: Colors.surface_container_high
    border.color: Colors.outline_variant
    border.width: Style.spacing.hairline
    radius: Style.cornerRadius

    Column {
        id: content
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: Style.spacing.xxl
            rightMargin: Style.spacing.xxl
        }
        spacing: Style.spacing.sm

        StyledText {
            width: parent.width
            text: "Versions"
            font.pixelSize: Style.font.body
            font.bold: true
            color: Colors.on_surface
        }

        Column {
            id: rows
            width: parent.width
            spacing: Style.spacing.xs

            MockVersionRow {
                id: rowOne
                label: "Chapter 66 · 09/04/2026"
                group: "Español"
                rowHovered: card.rowHovered
            }

            MockVersionRow {
                id: rowTwo
                label: "Chapter 66.1 · 21/04/2026"
                group: "Español (Latinoamérica)"
                current: true
            }
        }

        Rectangle {
            width: parent.width
            height: Style.spacing.hairline
            color: Colors.outline_variant
        }

        Item {
            width: parent.width
            height: Style.space(24)

            StyledText {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Remember for the whole series"
                font.pixelSize: Style.font.bodySmall
                color: Colors.on_surface
            }

            // The kit's own switch, presentation only: no input is synthesized.
            ToggleSwitch {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: card.toggleOn
                interactive: false
                cursorRing: false
                trackHeight: Style.space(18)
            }
        }
    }
}
