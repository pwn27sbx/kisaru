import QtQuick
import qs.app
import qs.Commons
import qs.services
import qs.components

// The small modal behind the folder row: a name to type, or a confirmation.
// One component for create, rename and delete so the three never drift apart.
Item {
    id: root

    property bool opened: false
    // true: type a name; false: confirm the message.
    property bool textMode: true
    property string heading: ""
    property string message: ""
    property string initialText: ""

    signal accepted(string value)
    signal canceled()

    visible: opened
    z: 500

    function openText(title, value) {
        root.textMode = true
        root.heading = title
        root.message = ""
        root.initialText = value || ""
        root.opened = true
        Qt.callLater(root._focus)
    }

    function openConfirm(title, text) {
        root.textMode = false
        root.heading = title
        root.message = text
        root.initialText = ""
        root.opened = true
        Qt.callLater(root._focus)
    }

    function close() {
        root.opened = false
        input.text = ""
    }

    function _focus() {
        if (!root.opened) return
        if (root.textMode) input.forceActiveFocus()
        else confirmButton.forceActiveFocus()
    }

    function _accept() {
        if (root.textMode && input.text.trim() === "") return
        var value = input.text
        root.close()
        root.accepted(value)
    }

    Rectangle {
        anchors.fill: parent
        color: Colors.withAlpha(Colors.background, 0.86)
        MouseArea {
            anchors.fill: parent
            onClicked: { root.close(); root.canceled() }
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 2 * Gutter.left, Style.space(180))
        height: content.implicitHeight + 2 * Style.spacing.xxl
        color: Colors.surface_container_high
        border.color: Colors.outline_variant
        border.width: Style.spacing.hairline
        radius: Style.cornerRadius

        Column {
            id: content
            anchors {
                left: parent.left; right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: Style.spacing.xxl; rightMargin: Style.spacing.xxl
            }
            spacing: Style.spacing.lg

            StyledText {
                width: parent.width
                text: root.heading
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                color: Colors.on_surface
                wrapMode: Text.Wrap
            }

            StyledText {
                width: parent.width
                visible: root.message !== ""
                text: root.message
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                color: Colors.on_surface_variant
                wrapMode: Text.Wrap
            }

            Rectangle {
                width: parent.width
                height: Style.space(30)
                visible: root.textMode
                radius: Style.cornerRadius
                color: Colors.surface_container
                border.color: Colors.outline_variant
                border.width: Style.spacing.hairline

                TextInput {
                    id: input
                    anchors.fill: parent
                    anchors.leftMargin: Style.spacing.md
                    anchors.rightMargin: Style.spacing.md
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    color: Colors.on_surface
                    selectionColor: Style.selectionFillFor(Colors.primary)
                    clip: true
                    onAccepted: root._accept()
                    Keys.onEscapePressed: { root.close(); root.canceled() }
                }
            }

            Row {
                anchors.right: parent.right
                spacing: Style.spacing.sm

                Rectangle {
                    width: cancelLabel.implicitWidth + 2 * Style.spacing.controlPaddingX
                    height: Style.space(26)
                    radius: Style.cornerRadius
                    color: cancelArea.containsMouse
                        ? Colors.surface_container : Colors.surface_container_low
                    border.color: Colors.outline_variant
                    border.width: Style.spacing.hairline

                    StyledText {
                        id: cancelLabel
                        anchors.centerIn: parent
                        text: I18n.t("action.cancel")
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        color: Colors.on_surface_variant
                    }
                    MouseArea {
                        id: cancelArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.close(); root.canceled() }
                    }
                }

                Rectangle {
                    id: confirmButton
                    width: confirmLabel.implicitWidth + 2 * Style.spacing.controlPaddingX
                    height: Style.space(26)
                    radius: Style.cornerRadius
                    color: root.textMode ? Colors.primary : Colors.error

                    activeFocusOnTab: true
                    Keys.onReturnPressed: root._accept()
                    Keys.onEnterPressed: root._accept()
                    Keys.onEscapePressed: { root.close(); root.canceled() }

                    StyledText {
                        id: confirmLabel
                        anchors.centerIn: parent
                        text: root.textMode ? I18n.t("folder.save") : I18n.t("folder.delete")
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                        color: root.textMode ? Colors.on_primary : Colors.on_error
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root._accept()
                    }
                }
            }
        }
    }
}
