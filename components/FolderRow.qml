import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.app
import qs.Commons
import qs.services
import qs.components
import "../services/library_view.js" as LibraryViewJs

// The folder row under the Library header: Todas, one chip per folder, `+`,
// and the padlock while unlocked. Presentational only: the panel/LibraryView
// owns the dialogs and the writes, so this component never touches a library.
Item {
    id: root

    // "manga", "novel" or "anime".
    required property string kind
    property string activeFolder: ""

    readonly property var folders:
        LibraryViewJs.visibleFolders(Organizer.folders(root.kind), Privacy.locked)
    readonly property var active:
        activeFolder === "" ? null : Organizer.folder(root.kind, root.activeFolder)
    readonly property bool editable: !Privacy.locked && root.active !== null

    signal folderSelected(string folderId)
    signal createRequested()
    signal renameRequested(string folderId)
    signal hideRequested(string folderId, bool hidden)
    signal deleteRequested(string folderId)
    signal lockRequested()

    implicitHeight: Style.space(40)

    // One chip, shared by Todas, each folder and `+`.
    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool current: false
        property bool dangerous: false
        signal clicked()

        height: Style.space(26)
        radius: Style.cornerRadius
        width: Math.max(labelText.implicitWidth + 2 * Style.spacing.controlPaddingX,
                        Style.space(28))
        color: chip.current ? Colors.primary
            : (chipArea.containsMouse ? Colors.surface_container_high : Colors.surface_container)
        border.color: chip.current ? Colors.primary : Colors.outline_variant
        border.width: Style.spacing.hairline
        Behavior on color { ColorAnimation { duration: Motion.fast } }

        StyledText {
            id: labelText
            anchors.centerIn: parent
            text: chip.label
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: chip.current
            color: chip.current ? Colors.on_primary
                : (chip.dangerous ? Colors.error : Colors.on_surface)
        }
        MouseArea {
            id: chipArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }

    // A bare glyph button for rename / hide / delete / lock.
    component GlyphButton: Item {
        id: button
        property string glyph: ""
        property string tooltip: ""
        property color tone: Colors.on_surface_variant
        signal clicked()

        implicitWidth: Style.space(26)
        implicitHeight: Style.space(26)

        Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: glyphArea.containsMouse ? Colors.surface_container_high : "transparent"
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }
        MaterialIcon {
            anchors.centerIn: parent
            text: button.glyph
            font.pixelSize: Style.font.bodySmall
            color: button.tone
        }
        MouseArea {
            id: glyphArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
            ToolTip.visible: containsMouse
            ToolTip.delay: 600
            ToolTip.text: button.tooltip
        }
    }

    RowLayout {
        anchors.fill: parent
        // The row is a band of controls, so its visible box lines up with the
        // cards' ink and the header brand, not with their outer box.
        anchors.leftMargin: Gutter.left + Gutter.ink
        anchors.rightMargin: Gutter.right + Gutter.ink
        spacing: Style.spacing.sm

        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: root.implicitHeight
            contentWidth: chips.implicitWidth
            contentHeight: chips.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Row {
                id: chips
                spacing: Style.spacing.sm
                anchors.verticalCenter: parent.verticalCenter

                Chip {
                    label: I18n.t("folder.all")
                    current: root.activeFolder === ""
                    onClicked: root.folderSelected("")
                }

                Repeater {
                    model: root.folders

                    delegate: Chip {
                        required property var modelData
                        label: modelData.name + (modelData.hidden ? "  " + "󰌾" : "")
                        current: modelData.id === root.activeFolder
                        onClicked: root.folderSelected(modelData.id)
                    }
                }

                Chip {
                    label: "+"
                    onClicked: root.createRequested()
                }
            }
        }

        // Only a selected folder can be renamed, hidden or deleted, and only
        // while unlocked: while locked those controls do not exist.
        GlyphButton {
            visible: root.editable
            glyph: "󰏫"
            tooltip: I18n.t("folder.rename")
            onClicked: root.renameRequested(root.activeFolder)
        }
        GlyphButton {
            visible: root.editable && Privacy.configured
            glyph: root.active && root.active.hidden ? "󰈈" : "󰈉"
            tooltip: root.active && root.active.hidden
                ? I18n.t("folder.show") : I18n.t("folder.hide")
            onClicked: root.hideRequested(root.activeFolder,
                !(root.active && root.active.hidden))
        }
        GlyphButton {
            visible: root.editable
            glyph: "󰆴"
            tone: Colors.error
            tooltip: I18n.t("folder.delete")
            onClicked: root.deleteRequested(root.activeFolder)
        }

        GlyphButton {
            visible: Privacy.configured && !Privacy.locked
            glyph: "󰌾"
            tooltip: I18n.t("privacy.lock")
            onClicked: root.lockRequested()
        }
    }
}
