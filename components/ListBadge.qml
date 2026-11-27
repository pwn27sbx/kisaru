import QtQuick
import qs.app
import qs.Commons
import "../services/list_badge.js" as ListBadge

// The chapter/episode pill that opens each row of the three Detail lists.
//
// It draws inside a fixed column (components/BadgeColumn.qml): the list passes
// the width of its widest badge, so "Ch. 262.2" and "Ch. 271" occupy the same
// slot and every title in the list starts on the same x (owner, 2026-11-27).
// Without a column width it falls back to its own text, which is what a caller
// with a single row wants.
Rectangle {
    id: root

    // Already localized by the caller (Ch. 262 / Ep. 3).
    property string label: ""
    // The row is the one the reader stopped at: accent fill, on-accent text.
    property bool active: false
    property string fontFamily: ""
    // Width handed down by the list's components/BadgeColumn.qml. 0 = natural.
    property real columnWidth: 0

    readonly property real naturalWidth:
        badgeLabel.implicitWidth + ListBadge.PADDING_X

    // Never narrower than its own label, even if the column arrived stale.
    implicitWidth: Math.max(root.columnWidth, root.naturalWidth)
    implicitHeight: ListBadge.HEIGHT
    width: implicitWidth
    height: implicitHeight
    radius: Style.cornerRadius
    color: root.active ? Colors.primary : Colors.primary_container

    StyledText {
        id: badgeLabel

        anchors.centerIn: parent
        width: Math.min(implicitWidth, parent.width)
        text: root.label
        font.family: root.fontFamily
        // The same size, weight and spacing BadgeColumn measures with.
        font.pixelSize: ListBadge.FONT_PIXEL_SIZE // style-ignore — bespoke size
        font.bold: true
        font.letterSpacing: ListBadge.LETTER_SPACING
        color: root.active ? Colors.on_primary : Colors.on_primary_container
        elide: Text.ElideRight
    }
}
