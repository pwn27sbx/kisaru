import QtQuick
import QtQuick.Layouts
import qs.app
import qs.Commons
import qs.services
import qs.components

// Row 2 of every panel: the filter menu, the search field and the layout
// toggle, in one line with one height and one pair of edges (owner, §32/§32.1).
//
// The margins are the panel's content gutter (services/Gutter.qml), the same
// the grids, the lists and their skeletons use, so the first control's left
// edge IS the first card's left edge and the toggle's right edge IS the last
// card's right edge. No control has a margin of its own: that is the whole
// point of the rule, and it is why the gutter is a singleton and not a number
// copied six times.
//
// The panel keeps its search behaviour: this component forwards `edited` and
// `cleared` and publishes the field's contract (`text`, `activeFocus`,
// `forceFocus()`, `blur()`, `clear()`) so the `/` shortcut and the debounce stay
// where they were.
RowLayout {
    id: root

    // ── what the panel passes in ──────────────────────────────────────────
    property string panel: ""           // "manga" | "anime" | "novel"
    property bool listMode: false
    // [{ label, value }] and the current one; an empty list hides the menu.
    property var filterOptions: []
    property var filterValue: undefined
    // While a search is showing results the filter no longer describes them.
    property bool filterDimmed: false
    property string fallbackFilterLabel: ""
    property bool showSearch: true
    property string searchPlaceholder: ""
    property string fontFamily: Style.font.family

    signal filterChosen(var value)
    signal edited()
    signal cleared()

    // ── the search field's contract, for the panels ───────────────────────
    readonly property string text: field.text
    readonly property bool searchActiveFocus: field.activeFocus
    function forceFocus() { field.forceFocus() }
    function clear() { field.clear() }
    function blur() { field.blur() }
    function setText(value) { field.setText(value) }

    // One height for the row: controls, gaps and the row itself.
    readonly property int controlHeight: Style.space(30)

    Layout.fillWidth: true
    Layout.leftMargin: Gutter.left
    Layout.rightMargin: Gutter.right
    Layout.topMargin: Style.spacing.sm
    Layout.bottomMargin: Style.spacing.sm
    spacing: Style.spacing.sm
    // The popup has to paint over the stack below this row, like the header's.
    z: 2


    MenuSelect {
        id: menu
        visible: root.filterOptions !== undefined && root.filterOptions.length > 0
        Layout.alignment: Qt.AlignVCenter
        controlHeight: root.controlHeight
        options: root.filterOptions
        currentValue: root.filterValue
        dimmed: root.filterDimmed
        fallbackLabel: root.fallbackFilterLabel
        fontFamily: root.fontFamily
        onChosen: function(value) { root.filterChosen(value) }
    }

    SearchField {
        id: field
        visible: root.showSearch
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredHeight: root.controlHeight
        placeholder: root.searchPlaceholder
        fontFamily: root.fontFamily
        onEdited: root.edited()
        onCleared: root.cleared()
    }

    // Without a search field the toggle still belongs at the right edge.
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: root.controlHeight
        visible: !root.showSearch
    }

    ViewModeToggle {
        id: toggle
        Layout.alignment: Qt.AlignVCenter
        panel: root.panel
        listMode: root.listMode
        fontFamily: root.fontFamily
        cellHeight: root.controlHeight
    }
}
