import QtQuick
import qs.app
import qs.Commons
import qs.services
import qs.components

// The three-dot menu of the folder toolbar. The trigger is a bare glyph; the
// popup uses the same surface, border and rows as MenuSelect.
Item {
    id: root

    // [{ value, label, danger }]
    required property var options
    property string bodyFont: Style.font.family

    signal chosen(var value)

    implicitWidth: Style.space(26)
    implicitHeight: Style.space(26)
    readonly property bool open: popup.visible

    ClickableRect {
        anchors.fill: parent
        color: "transparent"
        cursorShape: Qt.PointingHandCursor
        onClicked: popup.visible = !popup.visible

        MaterialIcon {
            anchors.centerIn: parent
            text: "󰇙"
            font.pixelSize: Style.font.bodySmall
            color: Colors.card_secondary
        }
    }

    Rectangle {
        id: popup
        visible: false
        z: 100
        anchors {
            top: parent.bottom
            right: parent.right
            topMargin: Style.spacing.xs
        }
        width: Style.space(150)
        height: list.implicitHeight + 2 * Style.spacing.xs
        color: Colors.surface_container_high
        border.color: Colors.outline_variant
        border.width: Style.spacing.hairline
        radius: Style.cornerRadius

        Column {
            id: list
            anchors.fill: parent
            anchors.margins: Style.spacing.xs
            spacing: Style.spacing.hairline

            Repeater {
                model: root.options

                delegate: ClickableRect {
                    required property var modelData

                    width: parent.width
                    height: Style.space(26)
                    color: hovered ? Colors.surface_container : "transparent"
                    cursorShape: Qt.PointingHandCursor

                    StyledText {
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: Style.spacing.sm
                        }
                        text: modelData.label
                        font.family: root.bodyFont
                        font.pixelSize: Style.font.bodySmall
                        font.bold: modelData.danger === true
                        color: modelData.danger === true ? Colors.error : Colors.on_surface
                    }
                    onClicked: {
                        popup.visible = false
                        root.chosen(modelData.value)
                    }
                }
            }
        }
    }
}
