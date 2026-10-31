import QtQuick
import qs.app
import qs.services
import qs.Commons
import qs.Ui

// One header row shared by the three panels (plan R2 §2.1).
//
// Far left: the optional panel brand (`brand`, a Component); the tabs follow
// it and shift right when it is present. Absent on callers that do not pass
// one, which keeps their header exactly as it was.
// Left: the Browse / Library tabs. The current one is a pill — the accent tint
// behind its label — and the other stays plain muted text; neither has a
// border.
// Right: search, the optional SUB/DUB pair, the module action, the optional
// EN/ES chip, and minimize, all on the same baseline, with the free space in
// the middle.
//
// The search field itself belongs to each panel (it owns the debounce and the
// backend call), so it is placed in the `overlay` slot: it covers the tabs
// while the search is open and never overlaps the actions.
Item {
    id: root

    property var tabs: []
    // Counters for the tabs above, one entry per tab. A `-1` (or a missing
    // entry) means "no counter". Kept parallel and separate on purpose: `tabs`
    // stays a string[], so the delegates keep rendering `String(modelData)`
    // instead of `[object Object]`.
    property var tabCounts: []
    // Draw the tabs as one segmented box (the Stitch header): both live inside
    // a faint surface with the theme radius and ~2 px padding, the current one
    // a filled pill, each count a small muted number beside its label. Off by
    // default, so the anime and the novel header keep the two loose labels
    // they have today.
    property bool segmentedTabs: false
    // Short panel name + glyph, supplied by the panel (Component). `null` here
    // is the default, so a caller without a brand is untouched.
    property Component brand: null
    property int tabIndex: 0
    property bool showSearch: true
    property bool searchOpen: false
    property bool showMode: false
    // While the settings view is open the content controls step aside: search,
    // SUB/DUB and the module action belong to the list, not to settings.
    property bool settingsMode: false
    property string mode: ""
    // Module-specific action (the novel panel's provider dropdown), placed
    // between the SUB/DUB pair and the language chip.
    property Component extraAction: null
    // The header's EN/ES chip. Anime and the novel panel keep it; the manga
    // panel sets it to false because the language lives in its settings page
    // now (owner, round 2: "it is a setting").
    property bool showLanguage: true
    property string fontFamily: Style.font.family

    // Items declared as children land here (the panel's search field).
    default property alias overlay: slot.data

    signal tabActivated(int index)
    signal searchClicked()
    signal settingsClicked()
    signal modeSelected(string value)
    signal minimizeClicked()

    implicitHeight: Style.space(48)
    implicitWidth: parent ? parent.width : 0

    // The brand is part of the tab row: it disappears with it while the
    // search field covers the left region.
    readonly property bool showBrand: root.brand !== null && !root.searchOpen

    Rectangle {
        anchors.fill: parent
        color: Colors.surface_container_low
    }

    // Brand block. An inactive Loader has no width, so the tabs fall back to
    // their original left margin when no brand is loaded.
    Loader {
        id: brandLoader
        anchors {
            left: parent.left
            leftMargin: Style.spacing.md
            verticalCenter: parent.verticalCenter
        }
        active: root.showBrand
        sourceComponent: root.brand
    }

    // Tabs. With `segmentedTabs` they share one container (the Stitch header):
    // faint surface, theme radius, a hairline and ~2 px padding, with the
    // current one a filled pill inside it. Without it the wrapper collapses to
    // the bare Row these callers have always had — same position, same
    // spacing, no paint — so anime and the novel panel do not move.
    Rectangle {
        id: tabsBox
        visible: !root.searchOpen
        anchors {
            left: brandLoader.active ? brandLoader.right : parent.left
            leftMargin: Style.spacing.md
            verticalCenter: parent.verticalCenter
        }
        width: tabsRow.implicitWidth + (root.segmentedTabs ? 2 * Style.spacing.xxs : 0)
        height: root.segmentedTabs
            ? Style.spacing.controlHeight + 2 * Style.spacing.xxs
            : tabsRow.implicitHeight
        radius: Style.cornerRadius
        color: root.segmentedTabs ? Colors.surface_container : "transparent"
        border.width: root.segmentedTabs ? Style.spacing.hairline : 0
        border.color: Colors.outline_variant

        Row {
            id: tabsRow
            x: root.segmentedTabs ? Style.spacing.xxs : 0
            y: root.segmentedTabs ? Style.spacing.xxs : 0
            spacing: root.segmentedTabs ? Style.spacing.xxs : Style.spacing.md

            Repeater {
                model: root.tabs

                // The tab pill. qs.Ui's Button draws ONE text run, and Stitch's
                // tabs need two (the label plus a smaller, muted count), so the
                // pill is built here instead. Its box, fills and ring mirror
                // Button's own: same paddings, same reserved state border (so a
                // hover ring never relayouts the row), same state precedence
                // (pressed → hover → current) and the same 120 ms colour fade.
                // Orientation, position and spacing are unchanged, so a caller
                // that does not pass `segmentedTabs` (anime, the novel panel)
                // keeps the tabs it has today.
                delegate: ClickableRect {
                    id: tab

                    required property var modelData
                    required property int index

                    readonly property bool isCurrent: index === root.tabIndex
                    // -1 / missing entry: this tab carries no counter.
                    readonly property int count: {
                        var counts = root.tabCounts
                        if (!counts || index >= counts.length)
                            return -1
                        var value = Number(counts[index])
                        return isFinite(value) ? value : -1
                    }
                    // The ring Button reserves for its widest state border and
                    // paints on hover-cursor; taken from the same tokens so a
                    // theme that changes them moves this pill with it.
                    readonly property int _ring: Math.max(Style.hoverBorderWidth,
                                                         Style.selectedBorderWidth)
                    readonly property color _foreground: isCurrent ? Colors.text : Colors.muted

                    implicitWidth: tabRow.implicitWidth + 2 * Style.spacing.controlPaddingX + 2 * _ring
                    // Segmented: the cell fills the container's interior, so the
                    // active pill and the inactive label are the same height.
                    implicitHeight: root.segmentedTabs
                        ? Style.spacing.controlHeight
                        : tabRow.implicitHeight + 2 * Style.spacing.controlPaddingY + 2 * _ring
                    // Segmented: the cell sits inside the container's padding
                    // and takes its curve, so a rounded theme never shows a
                    // square fill poking through the corner.
                    radius: root.segmentedTabs ? Style.cornerRadius : 0
                    cursorShape: Qt.PointingHandCursor
                    color: tab.pressed ? Style.pressedFillFor(tab._foreground, Colors.primary)
                         : tab.hovered ? Style.hoverFillFor(tab._foreground, Colors.primary)
                         : tab.isCurrent ? Style.selectedFillFor(Colors.primary)
                         : "transparent"
                    border.width: tab.hovered ? tab._ring : 0
                    border.color: Style.hoverBorderFor(tab._foreground, Colors.primary)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    Row {
                        id: tabRow
                        anchors.centerIn: parent
                        // Only a segmented tab with a counter has two runs, so
                        // the gap exists only there (no stray space in the pill).
                        spacing: root.segmentedTabs && tab.count >= 0
                            ? Style.spacing.xs : 0

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            // Without the segmented box the count stays inside
                            // the one string, exactly as it always was.
                            text: root.segmentedTabs
                                ? String(tab.modelData)
                                : (tab.count >= 0
                                    ? String(tab.modelData) + " · " + tab.count
                                    : String(tab.modelData))
                            color: tab._foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                        }

                        // Stitch's count: a small muted number beside the label,
                        // not part of it.
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.segmentedTabs && tab.count >= 0
                            width: visible ? implicitWidth : 0
                            text: tab.count >= 0 ? String(tab.count) : ""
                            color: Colors.muted
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                        }
                    }

                    onClicked: root.tabActivated(tab.index)
                }
            }
        }
    }

    Item {
        id: slot
        anchors {
            left: parent.left
            right: actionsRow.left
            top: parent.top
            bottom: parent.bottom
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

        PanelActionButton {
            visible: !root.settingsMode && root.showSearch && root.tabIndex === 0
            iconText: "⌕"
            hasCursor: root.searchOpen
            size: Style.space(36)
            fontSize: Style.font.iconLarge
            onClicked: root.searchClicked()
        }

        Row {
            visible: !root.settingsMode && root.showMode && root.tabIndex === 0
            spacing: Style.spacing.xs

            Repeater {
                model: ["sub", "dub"]

                delegate: Button {
                    required property string modelData

                    readonly property bool active: modelData === root.mode

                    text: modelData.toUpperCase()
                    bordered: false
                    selected: active
                    foreground: active ? Colors.text : Colors.muted
                    fontFamily: root.fontFamily
                    fontSize: Style.font.caption
                    horizontalPadding: Style.spacing.lg
                    onClicked: root.modeSelected(modelData)
                }
            }
        }

        Loader {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.settingsMode && root.extraAction !== null && root.tabIndex === 0 && !root.searchOpen
            sourceComponent: root.extraAction
        }

        LanguageToggle {
            visible: root.showLanguage && !root.settingsMode
            anchors.verticalCenter: parent.verticalCenter
        }

        PanelActionButton {
            iconText: "󰒓"
            tooltipText: I18n.t("settings.open")
            focusable: true
            hasCursor: root.settingsMode
            size: Style.space(36)
            onClicked: root.settingsClicked()
        }

        PanelActionButton {
            iconText: "─"
            size: Style.space(36)
            onClicked: root.minimizeClicked()
        }
    }
}
