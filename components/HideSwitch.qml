import QtQuick
import qs.app
import qs.Commons
import qs.services
import qs.components
import "../services/toolbar.js" as Toolbar

// The one clear hide switch: eye, state word and track, with no box around it.
// The same component is used inside a folder and in a title's Detail.
ClickableRect {
    id: root

    property bool checked: false
    property string bodyFont: Style.font.family

    implicitWidth: row.implicitWidth + 2 * Style.spacing.controlPaddingX
    implicitHeight: Style.space(26)
    color: "transparent"
    cursorShape: Qt.PointingHandCursor

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Style.spacing.sm

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            text: root.checked ? "󰈈" : "󰈉"
            font.pixelSize: Style.font.caption
            color: Colors.card_secondary
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.t(Toolbar.hideKey(root.checked))
            font.family: root.bodyFont
            font.pixelSize: Style.font.caption
            font.bold: true
            color: Colors.on_surface
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(24)
            height: Style.space(12)
            radius: height / 2 // style-ignore — a switch track is a capsule
            color: root.checked ? Colors.primary : Colors.outline_variant

            Rectangle {
                width: Style.space(8)
                height: width
                radius: width / 2 // style-ignore — the knob is a circle
                anchors.verticalCenter: parent.verticalCenter
                x: root.checked ? parent.width - width - Style.space(2) : Style.space(2)
                color: root.checked ? Colors.on_primary : Colors.on_surface_variant
            }
        }
    }
}
