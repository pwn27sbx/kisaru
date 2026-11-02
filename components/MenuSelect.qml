import QtQuick
import qs.app
import qs.Commons
import qs.services
import "../services/filter_menu.js" as Menu

// A dropdown that fits the panel's chrome: current label + caret, and a list
// below it. One implementation for the two places that need one — the novel
// panel's provider picker (it was inline and mouse-only) and the filter menu
// of the tool bar (owner, §32) — so there is no second copy to drift.
//
// Square corners, theme colours, the current row in solid accent, hover tint on
// the rest. Mouse and keyboard: Enter/Space opens, ↑/↓ move, Enter picks, Esc
// closes. The index and label arithmetic lives in services/filter_menu.js and
// is unit-tested there; this file only draws and routes.
Item {
    id: root

    // [{ label: "Hot", value: "" }, …]
    required property var options
    property var currentValue: undefined
    // Height of the button: the tool bar's control height, or the header's own.
    property int controlHeight: Style.space(30)
    // While true the button dims and refuses to open (a search is showing
    // results the filter no longer describes).
    property bool dimmed: false
    // Shown while the choice is being applied (the novel provider switch).
    property bool busy: false
    property string fallbackLabel: ""
    property string fontFamily: Style.font.family
    property int popupWidth: Style.space(160)
    // The header cell opens its list to the left; the tool bar opens it below
    // the button's own left edge.
    property bool alignRight: false

    signal chosen(var value)

    readonly property string currentLabel:
        Menu.labelFor(root.options, root.currentValue, root.fallbackLabel)
    readonly property bool open: popup.visible
    property int _highlight: -1

    implicitWidth: buttonRow.implicitWidth + 2 * Style.spacing.controlPaddingX
    implicitHeight: root.controlHeight
    opacity: root.dimmed ? 0.45 : 1
    Behavior on opacity { ColorAnimation { duration: Motion.fast } }

    function toggle() {
        if (root.dimmed) return
        if (popup.visible) {
            popup.visible = false
        } else {
            root._highlight = Menu.openingIndex(root.options, root.currentValue)
            popup.visible = true
            root.forceActiveFocus()
        }
    }

    function choose(index) {
        if (index < 0 || index >= root.options.length) return
        popup.visible = false
        root.chosen(root.options[index].value)
    }

    activeFocusOnTab: true
    Accessible.role: Accessible.ComboBox
    Accessible.name: root.currentLabel
    Accessible.onPressAction: root.toggle()

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
            if (popup.visible) {
                popup.visible = false
                event.accepted = true
            }
            return
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            if (popup.visible) root.choose(root._highlight)
            else root.toggle()
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
            var delta = event.key === Qt.Key_Down ? 1 : -1
            if (popup.visible) root._highlight = Menu.next(root._highlight, root.options.length, delta)
            else root.toggle()
            event.accepted = true
        }
    }

    Rectangle {
        anchors.fill: parent
        color: mouse.containsMouse || root.open
            ? Style.hoverFillFor(Colors.muted, Colors.primary) : "transparent"
        Behavior on color { ColorAnimation { duration: Motion.fast } }
    }

    Row {
        id: buttonRow
        anchors.centerIn: parent
        spacing: Style.spacing.sm

        StyledText {
            text: root.currentLabel
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.letterSpacing: 0.3
            color: Colors.on_surface
            anchors.verticalCenter: parent.verticalCenter
        }

        Spinner {
            visible: root.busy
            width: Style.space(10)
            border.width: Style.spacing.hairline
            anchors.verticalCenter: parent.verticalCenter
            duration: Motion.loop
            running: root.busy
        }

        MaterialIcon {
            visible: !root.busy
            text: "󰅀"
            font.pixelSize: Style.font.caption
            color: Colors.on_surface_variant
            anchors.verticalCenter: parent.verticalCenter
            rotation: root.open ? 180 : 0
            Behavior on rotation { NumberAnimation { duration: Motion.fast } }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: !root.dimmed
        onClicked: root.toggle()
    }

    Rectangle {
        id: popup
        visible: false
        anchors.top: parent.bottom
        anchors.topMargin: Style.spacing.xs
        anchors.left: root.alignRight ? undefined : parent.left
        anchors.right: root.alignRight ? parent.right : undefined
        width: root.popupWidth
        height: list.implicitHeight + 2 * Style.spacing.xs
        color: Colors.surface_container_high
        border.color: Colors.outline_variant
        border.width: Style.spacing.hairline
        z: 100

        Column {
            id: list
            anchors.fill: parent
            anchors.margins: Style.spacing.xs
            spacing: Style.spacing.hairline

            Repeater {
                model: root.options

                delegate: ClickableRect {
                    required property var modelData
                    required property int index

                    readonly property bool current: modelData.value === root.currentValue
                    readonly property bool highlighted: index === root._highlight

                    width: parent.width
                    height: Style.space(26)
                    color: current ? Colors.primary
                        : (highlighted || hovered ? Style.hoverFillFor(Colors.muted, Colors.primary)
                                                  : "transparent")
                    cursorShape: Qt.PointingHandCursor

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Style.spacing.sm
                        text: parent.modelData.label
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: parent.current
                        color: parent.current ? Colors.on_primary : Colors.on_surface
                    }

                    onClicked: root.choose(index)
                }
            }
        }
    }
}
