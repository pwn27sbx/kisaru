import QtQuick
import qs.app
import qs.Commons
import qs.Ui

// The settings page's card: a title and its description on the left, a control
// on the right — the container qs.Ui's Toggle draws for the language row.
//
// It exists because a setting whose control is not a switch (the anime panel's
// SUB|DUB pair) must still look like the others: same height, same fill, same
// border, same paddings and type. Those tokens come from Toggle's own
// implementation, not from a second opinion, so the two rows cannot drift.
// The card is a container, not a control: the row does not hover or take focus.
BorderSurface {
    id: root

    property string label: ""
    property string description: ""
    property string fontFamily: Style.font.family
    property color foreground: Colors.on_surface
    property color accent: Colors.primary

    // The control that sits on the right, as the Toggle puts its switch there.
    default property alias control: controlSlot.data

    implicitHeight: Math.max(54, content.implicitHeight + Style.spacing.huge)
    radius: Style.cornerRadius
    color: Style.controlFill(false, false, root.foreground, root.accent)
    borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

    Row {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: root.borderLeft + Style.spacing.rowPaddingX
        anchors.rightMargin: root.borderRight + Style.spacing.rowPaddingX
        spacing: Style.spacing.rowPaddingX

        Column {
            width: parent.width - controlSlot.width - parent.spacing
            spacing: Style.spacing.xs
            anchors.verticalCenter: parent.verticalCenter

            StyledText {
                width: parent.width
                text: root.label
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
                elide: Text.ElideRight
            }

            StyledText {
                visible: root.description !== ""
                text: root.description
                color: Qt.darker(root.foreground, 1.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
                width: parent.width
            }
        }

        Item {
            id: controlSlot
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
        }
    }
}
