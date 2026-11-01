import QtQuick
import qs.app
import qs.services
import qs.Commons
import qs.Ui
import "../services/header_cell.js" as HeaderCell

// The header row, shared by the three panels (owner, round 6).
//
// One strip of full-height cells, no box inside a box:
//
//   [ BRAND ][ Browse 32 ][ Library 1 ] … [ provider ] [⚙][─]
//
// The selected cell wears the active filter chip's recipe (accent tint, 1 px
// accent ring, resolved state colour); the rest stay plain and tint on hover.
// `services/header_cell.js` decides which paint applies and is tested; this file
// only maps that answer to Style calls.
//
// The search is not here: each panel puts the always-visible `SearchField` under
// this row (owner, round 6), so the header has no search state and no overlay.
// Panel-wide preferences that used to live here (SUB/DUB) moved to the settings
// page for the same reason the language did: they are settings, not navigation.
Item {
    id: root

    property var tabs: []
    // Counters for the tabs above, one entry per tab. A `-1` (or a missing
    // entry) means "no counter". Kept parallel and separate on purpose: `tabs`
    // stays a string[], so the delegates keep rendering `String(modelData)`
    // instead of `[object Object]`.
    property var tabCounts: []
    property Component brand: null
    property int tabIndex: 0
    // While the settings view is open the content controls step aside: the
    // extra cell belongs to the list, not to settings.
    property bool settingsMode: false
    // A control that is not a pair (the novel panel's provider dropdown),
    // rendered as one full-height cell before the gear.
    property Component extraCell: null
    property string fontFamily: Style.font.family

    signal tabActivated(int index)
    signal settingsClicked()
    signal minimizeClicked()

    implicitHeight: Style.space(48)
    implicitWidth: parent ? parent.width : 0

    // The extra cell belongs to the list on the first tab.
    readonly property bool _listTab: root.tabIndex === 0 && !root.settingsMode

    Rectangle {
        anchors.fill: parent
        color: Colors.surface_container_low
    }

    // One cell of the row: full height, plain until it is current or hovered.
    component Cell: ClickableRect {
        id: cell

        required property string label
        required property bool current
        // -1 (the default) means "this cell carries no counter".
        property int count: -1
        property string bodyFont: root.fontFamily

        // Button's own state precedence, resolved in header_cell.js.
        readonly property var _style: HeaderCell.cellStyle({
            current: cell.current,
            hovered: cell.hovered,
            pressed: cell.pressed
        })
        // The selected cell is a solid accent with the on-accent label, the
        // same reading as FilterBar's active chip (owner, round 6).
        readonly property color _fillBase: cell.current ? Colors.on_primary : Colors.muted
        // Selected reads as a solid accent cell with the on-accent label; the
        // tint plus ring is gone (owner, round 6).
        readonly property color _foreground:
            cell._style.label === HeaderCell.LABEL.ON ? Colors.on_primary : cell._fillBase

        // How much of the on-accent colour the counter keeps.
        readonly property real counterOpacity: 0.75

        implicitWidth: content.implicitWidth + 2 * Style.spacing.controlPaddingX
        // The cell IS the header row, so the tint reaches its top and bottom.
        implicitHeight: root.implicitHeight
        radius: 0 // style-ignore — the header cells are square
        cursorShape: Qt.PointingHandCursor
        color: cell._style.fill === HeaderCell.FILL.SOLID ? Colors.primary
            : cell._style.fill === HeaderCell.FILL.PRESSED
                ? Style.pressedFillFor(cell._fillBase, Colors.primary)
                : cell._style.fill === HeaderCell.FILL.HOVER
                    ? Style.hoverFillFor(cell._fillBase, Colors.primary)
                    : "transparent"
        // No border at all: the solid fill is the selected state, hover is the
        // tint, and nothing draws a ring (owner, round 6).
        border.width: 0
        Behavior on color { ColorAnimation { duration: Motion.fast } }

        Row {
            id: content
            anchors.centerIn: parent
            // The gap exists only when there is a counter to separate.
            spacing: cell.count >= 0 ? Style.spacing.xs : 0

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: cell.label
                color: cell._foreground
                font.family: cell.bodyFont
                font.pixelSize: Style.font.body
            }

            // The counter: a small muted number beside the label, not part of
            // it. `visible` alone is enough — a Row skips invisible items, and
            // binding width to implicitWidth on Text is the classic path to a
            // binding loop (Qt logged one).
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: cell.count >= 0
                text: cell.count >= 0 ? String(cell.count) : ""
                // On the solid accent the counter keeps contrast without
                // competing with the label.
                color: cell.current
                    ? Colors.withAlpha(Colors.on_primary, cell.counterOpacity)
                    : Colors.muted
                font.family: cell.bodyFont
                font.pixelSize: Style.font.caption
            }
        }
    }

    Loader {
        id: brandLoader
        anchors {
            left: parent.left
            leftMargin: Style.spacing.md
            verticalCenter: parent.verticalCenter
        }
        sourceComponent: root.brand
    }

    Row {
        id: cellsRow
        anchors {
            left: brandLoader.active ? brandLoader.right : parent.left
            leftMargin: Style.spacing.md
            top: parent.top
            bottom: parent.bottom
        }

        Repeater {
            model: root.tabs

            delegate: Cell {
                required property var modelData
                required property int index

                label: String(modelData)
                current: index === root.tabIndex
                count: {
                    var counts = root.tabCounts
                    if (!counts || index >= counts.length) return -1
                    var value = Number(counts[index])
                    return isFinite(value) ? value : -1
                }
                onClicked: root.tabActivated(index)
            }
        }
    }

    Row {
        id: actionsRow
        anchors {
            right: parent.right
            rightMargin: Style.spacing.md
            verticalCenter: parent.verticalCenter
        }
        spacing: Style.spacing.controlGap

        // The panel's own control (novel's provider dropdown), one cell tall —
        // the control inside is expected to be one cell of the row.
        Loader {
            id: extraLoader
            anchors.verticalCenter: parent.verticalCenter
            visible: root._listTab && root.extraCell !== null
            height: root.implicitHeight
            width: item ? item.implicitWidth : 0
            sourceComponent: root.extraCell
        }

        PanelActionButton {
            iconText: "󰒓"
            tooltipText: I18n.t("settings.open")
            focusable: true
            hasCursor: root.settingsMode
            size: root.implicitHeight
            onClicked: root.settingsClicked()
        }

        PanelActionButton {
            iconText: "─"
            size: root.implicitHeight
            onClicked: root.minimizeClicked()
        }
    }
}
