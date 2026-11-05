import QtQuick
import qs.Commons
import qs.app
import qs.services
import qs.components
import "../services/manga_card.js" as MangaCard

// A folder where a title card would be: the same cell, the same cover ratio,
// a 2x2 mosaic of its inner covers and its name plus title count below.
//
// It mirrors CoverCard's box (margins, radius, hairline, bottom info block) so a
// folder and a title are the same size in the Library grid.
ClickableRect {
    id: root

    property var covers: []
    property bool coversReady: true
    property string name: ""
    property int count: 0
    property bool hidden: false
    property string bodyFont: ""

    readonly property int _infoPadding: Style.space(8)
    readonly property int _infoInset: Style.space(8)

    anchors.margins: Style.space(5)
    radius: Style.cornerRadius
    color: Colors.surface_container
    border.width: Style.spacing.hairline
    border.color: Colors.withAlpha(Colors.on_surface, 0.06)
    clip: true

    // Same cover band as CoverCard: width * 3/4.4, so the two cards line up.
    Item {
        id: cover
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: root.width * MangaCard.COVER_RATIO

        CoverMosaic {
            anchors.fill: parent
            covers: root.covers
            ready: root.coversReady
            glyphSize: Style.font.heading
        }

        // The same three-stop scrim as a title card, so the artwork dissolves
        // into the info block instead of ending on a hard edge.
        Rectangle {
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: parent.height
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Colors.withAlpha(Colors.surface_container, 0.55) }
                GradientStop { position: 1.0; color: Colors.surface_container }
            }
        }

        // Hidden folders exist only while unlocked; the chip says so without
        // giving the folder away after a lock (the card itself is gone then).
        Rectangle {
            visible: root.hidden
            anchors {
                top: parent.top
                right: parent.right
                topMargin: Style.space(6)
                rightMargin: Style.space(6)
            }
            height: Style.space(16)
            radius: Style.cornerRadius
            width: hiddenLabel.implicitWidth + Style.space(12)
            color: Colors.withAlpha(Colors.surface_container, 0.9)
            border.width: Style.spacing.hairline
            border.color: Colors.outline_variant

            MaterialIcon {
                id: hiddenLabel
                anchors.centerIn: parent
                text: "󰌾"
                font.pixelSize: Style.font.caption
                color: Colors.on_surface_variant
            }
        }
    }

    // Name and count, the title card's info block with a second line.
    Rectangle {
        id: infoBlock
        anchors {
            bottom: parent.bottom
            left: parent.left
            right: parent.right
        }
        height: infoColumn.implicitHeight + root._infoPadding
        color: Colors.surface_container

        Column {
            id: infoColumn
            anchors {
                left: parent.left
                leftMargin: root._infoInset
                verticalCenter: parent.verticalCenter
            }
            width: infoBlock.width - 2 * root._infoInset
            spacing: Style.spacing.xs

            StyledText {
                width: parent.width
                text: root.name
                font.family: root.bodyFont
                font.pixelSize: Style.font.bodySmall
                font.weight: Font.DemiBold
                font.letterSpacing: 0.2
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                lineHeight: 1.3
            }

            StyledText {
                width: parent.width
                text: I18n.tn("folder.count", root.count)
                font.family: root.bodyFont
                font.pixelSize: Style.font.caption
                font.letterSpacing: 0.3
                color: Colors.card_secondary
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }

    Rectangle {
        z: 10
        anchors.fill: parent
        radius: root.radius
        color: Colors.primary
        opacity: root.pressed ? Style.pressedFillAlpha : (root.hovered ? Style.hoverFillAlpha : 0)
        Behavior on opacity { NumberAnimation { duration: Motion.base } }
    }
}
