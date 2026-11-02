import QtQuick
import qs.app
import qs.Commons
import qs.Ui
import "../services/header_cell.js" as HeaderCell

// One segment of the grid/list toggle. Both manga views used to inline this
// block; one file means a change to the fill, the glyph or the tooltip lands
// once instead of drifting between Browse and Library.
//
// Owner §30: no frame, and the cell is exactly as tall as a filter chip —
// components/Chip.qml is a line of body text plus `controlPaddingY` above and
// below, and this cell measures its glyph the same way, so the two controls
// cannot disagree about the row's height.
ClickableRect {
    id: chip

    property string glyph: ""
    property string label: ""
    property bool current: false
    property string bodyFont: ""
    // The tool bar makes its controls one height (§32.1); 0 keeps the chip formula.
    property int cellHeight: 0

    // A square cell: the height a chip gets, and the same for the width, which
    // is what an icon button of this family looks like.
    implicitWidth: implicitHeight
    implicitHeight: chip.cellHeight > 0
        ? chip.cellHeight
        : metrics.implicitHeight + 2 * Style.spacing.controlPaddingY
    cursorShape: Qt.PointingHandCursor
    // The glyph comes from a fallback font whose line is a pixel taller than the
    // body font's, so the cell measures a normal line instead: the toggle's row
    // height then equals the filter chips' by construction, not by luck.
    Text {
        id: metrics
        visible: false
        text: "Mg" // i18n-ignore — font metric sample, never drawn
        font.family: chip.bodyFont
        font.pixelSize: Style.font.body
    }
    // Selected is the solid accent; pressed and hover keep their fills, in the
    // same precedence services/header_cell.js uses for the header cells
    // (pressed first, then hover, then selected).
    readonly property var _style: HeaderCell.cellStyle({
        current: chip.current, hovered: chip.hovered, pressed: chip.pressed
    })
    color: chip._style.fill === HeaderCell.FILL.SOLID ? Colors.primary
        : chip._style.fill === HeaderCell.FILL.PRESSED
            ? Style.pressedFillFor(Colors.muted, Colors.primary)
            : chip._style.fill === HeaderCell.FILL.HOVER
                ? Style.hoverFillFor(Colors.muted, Colors.primary)
                : "transparent"
    border.width: 0
    Behavior on color { ColorAnimation { duration: Motion.fast } }

    StyledText {
        id: glyphText
        anchors.centerIn: parent
        text: chip.glyph
        font.family: chip.bodyFont
        font.pixelSize: Style.font.body
        // One recipe with the header cells and the chips: dark and bold when
        // selected (owner, A-8).
        font.bold: chip._style.strong
        color: chip._style.label === HeaderCell.LABEL.ON ? Colors.on_primary : Colors.muted
    }

    // No tooltip: the two glyphs say grid and list, and the bordered box it
    // drew above the control read as a defect (owner, round 6).
}
