import QtQuick
import qs.app
import qs.Commons
import qs.Ui

// One segment of the grid/list toggle. Both manga views used to inline this
// block; one file means a change to the fill, the glyph or the tooltip lands
// once instead of drifting between Browse and Library.
ClickableRect {
    id: chip

    property string glyph: ""
    property string label: ""
    property bool current: false
    property string bodyFont: ""
    // Cell size. The default is the kit's control height, which is what the
    // loose chips used; a caller that puts the chip inside a segmented box
    // passes the compact cell Stitch draws.
    property int cellSize: Style.spacing.controlHeight

    implicitWidth: chip.cellSize
    implicitHeight: chip.cellSize
    cursorShape: Qt.PointingHandCursor
    // Selected is the solid accent; hover keeps its tint (owner, round 6).
    color: chip.current ? Colors.primary
        : chip.pressed ? Style.pressedFillFor(Colors.muted, Colors.primary)
        : chip.hovered ? Style.hoverFillFor(Colors.muted, Colors.primary)
        : "transparent"
    border.width: 0

    StyledText {
        anchors.centerIn: parent
        text: chip.glyph
        font.family: chip.bodyFont
        font.pixelSize: Style.font.body
        color: chip.current ? Colors.on_primary : Colors.muted
    }

    // No tooltip: the two glyphs say grid and list, and the bordered box it
    // drew above the control read as a defect (owner, round 6).
}
