import QtQuick
import qs.app
import qs.Commons
import qs.components

// Option B mockup (owner, 2026-11-27): plain rows, click = read that upload.
// The trailing whole-series icon carries the active state of the generation
// applied to the series; the ✓ marks the version being read. No "Read" chip.
//
// Mockup-only: never wired into the app.
Rectangle {
    id: card

    property bool rowHovered: false
    property bool iconHovered: false
    property bool tooltipVisible: false

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
                showSeries: true
                // This upload is the one already applied to the series.
                seriesActive: true
                rowHovered: card.rowHovered
            }

            MockVersionRow {
                id: rowTwo
                label: "Chapter 66.1 · 21/04/2026"
                group: "Español (Latinoamérica)"
                current: true
                showSeries: true
                seriesActive: false
                seriesHovered: card.iconHovered
            }
        }
    }

    // The tooltip the real control would open. It floats over the card like a
    // Qt tooltip popup, so it is drawn after the content.
    Rectangle {
        id: tooltip
        visible: card.tooltipVisible
        z: 10
        width: tooltipLabel.implicitWidth + 2 * Style.spacing.controlPaddingX
        height: tooltipLabel.implicitHeight + 2 * Style.spacing.controlPaddingY
        color: Colors.surface_container_highest
        border.color: Colors.outline_variant
        border.width: Style.spacing.hairline
        radius: Style.cornerRadius
        x: content.x + rows.x + rowTwo.width - rowTwo.seriesCenterFromRight - width / 2
        y: content.y + rows.y + rowTwo.y + rowTwo.height + Style.spacing.xxs

        StyledText {
            id: tooltipLabel
            anchors.centerIn: parent
            text: "Use this version for the whole series"
            font.pixelSize: Style.font.bodySmall
            color: Colors.on_surface
        }
    }
}
