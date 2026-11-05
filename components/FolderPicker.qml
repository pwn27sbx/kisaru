import QtQuick
import qs.app
import qs.Commons
import qs.services
import qs.components

// The real folder list behind Detail's "Carpeta: …" button.
//
// It lists the visible folders (a hidden one is only here while unlocked), the
// "Ninguna" choice and one row that creates a folder in place. Choosing closes
// the list; the caller writes the entry.
Item {
    id: root

    property bool opened: false
    property var folders: []
    property string current: ""
    property string bodyFont: Style.font.family

    signal chosen(string folderId)
    signal createRequested()
    signal closed()

    visible: opened
    z: 400

    function _pick(id) {
        root.opened = false
        root.chosen(id)
    }

    function _create() {
        root.opened = false
        root.createRequested()
    }

    onOpenedChanged: if (opened) Qt.callLater(function() { card.forceActiveFocus() })

    Rectangle {
        anchors.fill: parent
        color: Colors.withAlpha(Colors.background, 0.86)
        MouseArea {
            anchors.fill: parent
            onClicked: { root.opened = false; root.closed() }
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
        focus: true
        Keys.onEscapePressed: { root.opened = false; root.closed() }

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
                text: I18n.t("folder.pick")
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

                    // "Ninguna": the entry leaves every folder.
                    ClickableRect {
                        width: list.width
                        height: Style.space(26)
                        color: root.current === ""
                            ? Colors.primary : (hovered ? Colors.surface_container : "transparent")

                        StyledText {
                            anchors {
                                left: parent.left; verticalCenter: parent.verticalCenter
                                leftMargin: Style.spacing.sm
                            }
                            text: I18n.t("folder.none")
                            font.family: root.bodyFont
                            font.pixelSize: Style.font.bodySmall
                            font.bold: root.current === ""
                            color: root.current === "" ? Colors.on_primary : Colors.on_surface
                        }
                        onClicked: root._pick("")
                    }

                    Repeater {
                        model: root.folders

                        delegate: ClickableRect {
                            required property var modelData
                            width: list.width
                            height: Style.space(26)
                            color: root.current === modelData.id
                                ? Colors.primary : (hovered ? Colors.surface_container : "transparent")

                            StyledText {
                                anchors {
                                    left: parent.left; verticalCenter: parent.verticalCenter
                                    leftMargin: Style.spacing.sm
                                }
                                text: modelData.name
                                font.family: root.bodyFont
                                font.pixelSize: Style.font.bodySmall
                                font.bold: root.current === modelData.id
                                color: root.current === modelData.id
                                    ? Colors.on_primary : Colors.on_surface
                                elide: Text.ElideRight
                                width: parent.width - 2 * Style.spacing.sm
                            }
                            onClicked: root._pick(modelData.id)
                        }
                    }

                    Rectangle {
                        width: list.width
                        height: 1
                        color: Colors.outline_variant
                        opacity: 0.4
                    }

                    ClickableRect {
                        width: list.width
                        height: Style.space(26)
                        color: hovered ? Colors.surface_container : "transparent"

                        Row {
                            anchors {
                                left: parent.left; verticalCenter: parent.verticalCenter
                                leftMargin: Style.spacing.sm
                            }
                            spacing: Style.spacing.xs

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰐕"
                                font.pixelSize: Style.font.caption
                                color: Colors.primary
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.t("folder.create")
                                font.family: root.bodyFont
                                font.pixelSize: Style.font.bodySmall
                                color: Colors.primary
                            }
                        }
                        onClicked: root._create()
                    }
                }
            }
        }
    }
}
