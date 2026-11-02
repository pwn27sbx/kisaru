import QtQuick
import qs.app
import qs.Commons

// The always-visible search pill (owner, round 6: one look for all three panels).
//
// One full-width pill: the search glyph on the left, the placeholder in the
// middle and the "/" key badge on the right, which becomes the clear cell once
// there is text. Stitch's sub-bar, and the shape the manga panel already had
// when the other two still opened a search box inside the header.
//
// The field does not search: the panel owns its debounce and its service call,
// so `edited()` is emitted on every keystroke and the panel decides what to do.
// `cleared()` fires only when a person clears (Esc or the clear cell): the
// panel hangs "leave the search" off it. A programmatic `clear()` is silent.
Rectangle {
    id: root

    property string placeholder: ""
    property string fontFamily: Style.font.family
    readonly property string text: input.text
    readonly property bool hasText: input.text.length > 0

    signal edited()
    signal cleared()

    function forceFocus() {
        input.forceActiveFocus()
    }

    // Programmatic clear: no `edited()` (a filter that invalidates the query
    // must not also kick the panel's debounce into a second fetch) and no
    // `cleared()` either (the panel's handler blurs the field and resets the
    // list — a side effect only a person asking to clear should trigger).
    property bool _silent: false

    function clear() {
        root._silent = true
        input.text = ""
        root._silent = false
    }

    // What Esc and the clear cell do: empty the field and TELL the panel, which
    // is where "leave the search" lives.
    function userClear() {
        root.clear()
        root.cleared()
    }

    function blur() {
        input.focus = false
    }

    // "Search this title across the other sources" needs to fill the field
    // without pretending a person typed: silent, like clear(), and it does fire
    // nothing by itself.
    function setText(value) {
        root._silent = true
        input.text = String(value === undefined || value === null ? "" : value)
        root._silent = false
    }

    implicitHeight: Style.space(30)
    radius: Style.cornerRadius
    color: Colors.surface_container
    border.color: input.activeFocus ? Colors.primary : Colors.outline_variant
    border.width: input.activeFocus ? 1.5 : 1
    Behavior on border.width { NumberAnimation { duration: Motion.fast } }

    StyledText {
        anchors {
            left: parent.left
            leftMargin: Style.spacing.md
            verticalCenter: parent.verticalCenter
        }
        text: "⌕"
        color: Colors.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
    }

    TextInput {
        id: input
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            right: keyArea.left
            leftMargin: Style.space(26)
            rightMargin: Style.spacing.sm
        }
        color: Colors.on_surface
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        clip: true
        onTextChanged: if (!root._silent) root.edited()
        // Esc clears and leaves: `cleared()` is what tells the panel to
        // restore its list and hand the focus back.
        Keys.onEscapePressed: root.userClear()
    }

    StyledText {
        anchors {
            verticalCenter: parent.verticalCenter
            left: input.left
        }
        text: root.placeholder
        color: Colors.on_surface_variant
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        visible: !root.hasText
        opacity: 0.6
    }

    // The "/" key hint; it becomes the clear cell once there is text, so the
    // mouse keeps the affordance without a second control in the row.
    Item {
        id: keyArea
        anchors {
            right: parent.right
            rightMargin: Style.spacing.sm
            verticalCenter: parent.verticalCenter
        }
        width: Style.space(16)
        height: Style.space(16)

        Rectangle {
            anchors.fill: parent
            visible: !root.hasText
            radius: Style.cornerRadius
            color: Colors.surface_container_highest
            border.width: Style.spacing.hairline
            border.color: Colors.outline_variant

            StyledText {
                anchors.centerIn: parent
                text: "/"
                color: Colors.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
            }
        }

        ClickableRect {
            anchors.fill: parent
            visible: root.hasText
            cursorShape: Qt.PointingHandCursor
            color: Colors.surface_container_highest
            border.width: Style.spacing.hairline
            border.color: Colors.outline_variant
            onClicked: root.userClear()

            StyledText {
                anchors.centerIn: parent
                text: "✕"
                color: Colors.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
            }
        }
    }
}
