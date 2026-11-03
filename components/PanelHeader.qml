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
//   [ BRAND ][ Browse ][ Library ▢1 ] …[ provider ][⚙][─]
//
// The selected cell is a solid accent block with the dark bold label; the rest
// stay plain and tint on hover. `services/header_cell.js` decides which paint
// applies and is tested; this file only maps that answer to Style calls.
//
// A tab's count is a badge, and only the panels that want one pass it: Browse
// carries no number (the status bar already counts the loaded list) and an
// empty Library hides its badge instead of showing a zero (owner, A-8).
//
// Owner §33: the header is the WHOLE chrome now. The filter menu, the search and
// the icons share its one row, and the search is an icon that grows a field
// leftwards over the brand and the tabs when it is used. There is no second row
// under it any more, and the grid/list switch moved to the settings page.
//
// Everything lines up with the cards' ink (services/Gutter.qml): the brand's
// first pixel and the last icon end on the same lines the covers do.
Item {
    id: root

    property var tabs: []
    // Counters for the tabs above, one entry per tab. A `-1` (or a missing
    // entry) means "no counter", and a `0` means "nothing to count yet": both
    // draw no badge. Kept parallel and separate on purpose: `tabs` stays a
    // string[], so the delegates keep rendering `String(modelData)` instead of
    // `[object Object]`.
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

    // ── The tool row, inside the header (owner §33) ───────────────────────
    // The filter menu (manga/anime/novel Browse). Empty hides it, which is what
    // Library does.
    property var filters: []
    property var filterValue: undefined
    property string filterFallbackLabel: ""
    property bool filterDimmed: false
    // The growing search field over the left side.
    property bool searchOpen: false
    property string searchPlaceholder: ""

    signal tabActivated(int index)
    signal settingsClicked()
    signal minimizeClicked()
    signal filterChosen(var value)
    signal searchClicked()
    signal searchEdited()
    signal searchCleared()

    // The search field's contract, so the panels keep their debounce and their
    // "/" shortcut exactly where they were.
    readonly property string searchText: searchField.text
    readonly property bool searchActiveFocus: searchField.activeFocus
    function forceFocus() { searchField.forceFocus() }
    function clear() { searchField.clear() }
    function blur() { searchField.blur() }
    function setText(value) { searchField.setText(value) }

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

        // How much of the on-accent colour the badge keeps behind its number.
        readonly property real badgeFillOpacity: 0.18

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
            // The gap exists only when there is a badge to separate.
            spacing: HeaderCell.showBadge(cell.count) ? Style.spacing.xs : 0

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: cell.label
                color: cell._foreground
                font.family: cell.bodyFont
                font.pixelSize: Style.font.body
                // Current is bold here too: one recipe for every selected label.
                font.bold: cell._style.strong
            }

            // The count is a badge, not loose digits after the word: a small box
            // with a faint fill, so "Library ▢3" reads as one control and stays
            // legible on both the solid accent and the idle cell. Zero is not
            // shown at all (owner, A-8).
            Rectangle {
                id: badge
                anchors.verticalCenter: parent.verticalCenter
                visible: HeaderCell.showBadge(cell.count)
                width: Math.max(Style.space(16),
                    badgeText.implicitWidth + 2 * Style.spacing.xs)
                height: Math.max(Style.space(16),
                    badgeText.implicitHeight + Style.spacing.xs)
                radius: Style.cornerRadius
                color: cell.current
                    ? Colors.withAlpha(Colors.on_primary, cell.badgeFillOpacity)
                    : Colors.surface_container_high

                StyledText {
                    id: badgeText
                    anchors.centerIn: parent
                    text: HeaderCell.showBadge(cell.count) ? String(cell.count) : ""
                    color: cell.current ? Colors.on_primary : Colors.on_surface
                    font.family: cell.bodyFont
                    font.pixelSize: Style.font.caption
                    font.bold: true
                }
            }
        }
    }

    Loader {
        id: brandLoader
        anchors {
            left: parent.left
            // The brand's text is the left edge of the cards' ink (owner §33).
            leftMargin: Gutter.left + Gutter.ink
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
            // The header's icons end where the cards end, lane included.
            rightMargin: Gutter.right
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

        // Owner §33: the filter menu first, then the search, then the two icons.
        MenuSelect {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.filters !== undefined && root.filters.length > 0
            controlHeight: root.implicitHeight
            options: root.filters
            currentValue: root.filterValue
            fallbackLabel: root.filterFallbackLabel
            dimmed: root.filterDimmed
            fontFamily: root.fontFamily
            onChosen: function(value) { root.filterChosen(value) }
        }

        PanelActionButton {
            id: searchButton
            iconText: "󰍉"
            tooltipText: I18n.t("search.open")
            focusable: true
            hasCursor: root.searchOpen
            size: root.implicitHeight
            onClicked: root.searchClicked()
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

    // ── The search, grown leftwards over the brand and the tabs (owner §33) ──
    // Its right edge is the search icon; its width is the distance from there to
    // the brand's ink line, animated so it reads as growing out of the icon.
    SearchField {
        id: searchField
        // Above the brand, the tabs and the filter: the open field covers them
        // (owner, 2026-11-02 — it was drawn underneath).
        z: 10
        // The full header block, like the tab and icon cells: one flat band, not
        // a smaller pill inside it.
        y: 0
        height: root.implicitHeight
        radius: Style.space(0) // style-ignore — the header cells are square
        visible: root.searchOpen || width > 1
        clip: true
        // Its right edge is the search icon; its width runs back to the brand's
        // ink line, and x follows so the box grows out of the icon leftwards.
        // Reactive on purpose: mapToItem() is not, and a binding that calls it is
        // evaluated once at creation, when the row has not laid out yet
        // (diagnosis, 2026-11-02: fullWidth froze at 0 and the field became a
        // 0-width square). searchButton.x and actionsRow.x are real properties,
        // so this re-evaluates when the layout moves.
        readonly property real fullWidth: Math.max(0,
            searchButton.x + actionsRow.x - Style.spacing.sm - (Gutter.left + Gutter.ink))
        // The right edge is fixed (it follows the icon's left); the width grows
        // from 0 to fullWidth and x follows it, so the box grows leftwards.
        x: (Gutter.left + Gutter.ink) + (fullWidth - width)
        width: root.searchOpen ? fullWidth : 0
        Behavior on width { NumberAnimation { duration: Motion.base; easing.type: Motion.easeOut } }
        placeholder: root.searchPlaceholder
        fontFamily: root.fontFamily
        onEdited: root.searchEdited()
        onCleared: root.searchCleared()
    }
}
