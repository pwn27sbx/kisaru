import QtQuick
import qs.app
import qs.Commons
import qs.Ui
import "../services/header_cell.js" as HeaderCell

// One labelled, selectable chip: the filter chips of the three Browse views and
// the SUB/DUB modes of the audio setting.
//
// It is NOT a `qs.Ui` Button on purpose. Button paints its selected label with
// the theme's `selected-color`, which this theme sets to the light accent, so a
// selected Button showed a light label on the orange fill; the header cells
// never used Button and were dark and bold. One look now, one component.
//
// The state machine (pressed beats hover beats selected) lives in
// services/header_cell.js and is tested there; this file only maps the answer
// to Style calls, exactly like components/PanelHeader.qml does.
ClickableRect {
    id: chip

    property string text: ""
    property bool current: false
    property string bodyFont: ""

    readonly property var _style: HeaderCell.cellStyle({
        current: chip.current,
        hovered: chip.hovered,
        pressed: chip.pressed
    })
    readonly property color _fillBase: chip.current ? Colors.on_primary : Colors.muted
    readonly property color _foreground:
        chip._style.label === HeaderCell.LABEL.ON ? Colors.on_primary : Colors.muted

    implicitWidth: label.implicitWidth + 2 * Style.spacing.controlPaddingX
    implicitHeight: label.implicitHeight + 2 * Style.spacing.controlPaddingY
    cursorShape: Qt.PointingHandCursor
    color: chip._style.fill === HeaderCell.FILL.SOLID ? Colors.primary
        : chip._style.fill === HeaderCell.FILL.PRESSED
            ? Style.pressedFillFor(chip._fillBase, Colors.primary)
            : chip._style.fill === HeaderCell.FILL.HOVER
                ? Style.hoverFillFor(chip._fillBase, Colors.primary)
                : "transparent"
    // No border: the solid fill is the selected state (owner, round 6).
    border.width: 0
    Behavior on color { ColorAnimation { duration: Motion.fast } }

    StyledText {
        id: label
        anchors.centerIn: parent
        text: chip.text
        color: chip._foreground
        font.family: chip.bodyFont
        font.pixelSize: Style.font.body
        font.bold: chip._style.strong
    }
}
