import QtQuick
import qs.app
import qs.Commons
import qs.services
import qs.components

// A folder-toolbar action with a visible label: icon plus text, always on,
// never hover-only. The label uses the card's readable secondary tone; the
// icon may carry the action's colour (error for delete).
ClickableRect {
    id: root

    property string icon: ""
    property string label: ""
    property color iconTone: Colors.card_secondary
    property string bodyFont: Style.font.family

    implicitWidth: row.implicitWidth + 2 * Style.spacing.controlPaddingX
    implicitHeight: Style.space(26)
    radius: Style.cornerRadius
    color: hovered ? Colors.surface_container_high : Colors.surface_container
    border.color: Colors.outline_variant
    border.width: Style.spacing.hairline

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Style.spacing.xs

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            font.pixelSize: Style.font.caption
            color: root.iconTone
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            font.family: root.bodyFont
            font.pixelSize: Style.font.caption
            font.bold: true
            color: Colors.on_surface
        }
    }
}
