import QtQuick
import qs.app
import qs.Commons
import qs.services
import "../services/caret.js" as Caret

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

    // Width the caret needs plus a hair of air, so the text never collides with it.
    readonly property int caretRoom: Style.space(2) + Style.space(2)

    implicitHeight: Style.space(30)
    radius: Style.cornerRadius
    color: Colors.surface_container
    border.color: input.activeFocus ? Colors.primary : Colors.outline_variant
    border.width: input.activeFocus ? 1.5 : 1
    Behavior on border.width { NumberAnimation { duration: Motion.fast } }

    TextInput {
        id: input
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            right: keyArea.left
            // The header's brand ink line plus the room the caret needs: the
            // caret stands at the ink line and the first character starts right
            // of it, so an empty field never has the caret on top of the
            // placeholder (owner, 2026-11-02).
            leftMargin: Gutter.left + Gutter.ink + root.caretRoom
            rightMargin: Style.spacing.sm
        }
        color: Colors.on_surface
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        // No clip here: the caret is drawn in the room reserved to its LEFT, and
        // clipping would cut it away. The field itself clips, so the text still
        // cannot paint outside it.
        // TextInput writes the delegate's x from cursorRectangle on every move, so
        // the delegate itself must stay a zero-width anchor: the visible bar is a
        // child and takes the negative offset, landing before the first character
        // instead of over it (diagnosis, 2026-11-02).
        cursorDelegate: Item {
            width: 0
            height: Math.round(input.font.pixelSize * 1.25)

            Rectangle {
                // Before the first character at the start; at the cursor once
                // text exists, so the negative offset never lands on a letter.
                x: Caret.barX(input.cursorPosition, width, Style.space(2))
                width: Style.space(2)
                height: parent.height
                anchors.verticalCenter: parent.verticalCenter
                color: Colors.primary
            }
        }
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
        // The inactive tab's dim, not the near-invisible one (owner, 2026-11-02).
        color: Colors.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        visible: !root.hasText
    }

    // The clear cell: a bare x with a comfortable hit area, no box or border,
    // aligned to the field's right gutter and centred with the text.
    Item {
        id: keyArea
        anchors {
            right: parent.right
            rightMargin: Style.spacing.sm
            verticalCenter: parent.verticalCenter
        }
        width: Style.space(28)
        height: Style.space(28)

        ClickableRect {
            id: clearCell

            anchors.fill: parent
            visible: root.hasText
            cursorShape: Qt.PointingHandCursor
            color: clearCell.hovered ? Colors.surface_container_high : "transparent"
            radius: Style.cornerRadius
            onClicked: root.userClear()

            StyledText {
                anchors.centerIn: parent
                text: "✕"
                color: clearCell.hovered ? Colors.on_surface : Colors.card_secondary
                font.family: root.fontFamily
                // One step above body: the mark reads at a glance without
                // turning into a second icon next to the search glyph.
                font.pixelSize: Style.font.title
                Behavior on color { ColorAnimation { duration: Motion.fast } }
            }
        }
    }
}
