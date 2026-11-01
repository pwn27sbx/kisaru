import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.app
import qs.Commons
import qs.services
import qs.modules.novel.components
import qs.components
import qs.Ui
import "../../services/status_line.js" as StatusLine

Item {
    id: root

    // El panel se atenúa cuando el puntero no está encima (pintado sobre la
    // pantalla, ver shell.qml). HoverHandler escucha el área completa del panel,
    // no solo sus hijos.
    HoverHandler { id: pointer }

    readonly property bool pointerInside: pointer.hovered
    anchors {
        top: parent.top
        bottom: parent.bottom
        right: parent.right
    }
    implicitWidth: fullscreen ? (parent && parent.parent ? parent.parent.width : 1200) : 550
    visible: false

    Behavior on implicitWidth { NumberAnimation { duration: Motion.slow; easing.type: Motion.easeOut } }

    readonly property string fontBody: Style.font.family

    property bool fullscreen: false
    property int tabIndex: 0

    // Gear in the header: the settings view replaces the content stack.
    property bool settingsMode: false
    readonly property int settingsPageIndex: 2   // third page of the content stack

    property int browseStack:  0
    property int libraryStack: 0

    // Hidden but kept loaded: shell.qml skips the unload while this is set,
    // so the toggle brings the panel back exactly as it was left.
    property bool minimized: false

    function minimize() {
        minimized = true
        visible = false
    }

    // "/" focuses the always-visible search field; the visibility guard keeps
    // it from firing over another panel, and the focus guard from swallowing a
    // "/" typed INTO the field.
    Shortcut {
        sequence: "/"
        context: Qt.WindowShortcut
        enabled: root.visible && !root.settingsMode && root.tabIndex === 0
                 && !(searchField && searchField.activeFocus)
        onActivated: root.focusSearch()
    }

    function focusSearch() {
        if (searchField) searchField.forceFocus()
    }

    // Clears the text only: Browse calls this when a filter invalidates the
    // query, and the field stays where the user was typing.
    function clearSearch() {
        if (searchField) searchField.clear()
    }

    // Esc: empty the field, hand the focus back and show the unfiltered list.
    function closeSearch() {
        if (!searchField) return
        searchField.blur()
        browseView.resetList()
    }

    // Header brand: the app glyph plus this panel's short name (decision 1).
    Component {
        id: brandComponent
        PanelBrand { title: I18n.t("brand.novel"); fontFamily: root.fontBody }
    }

    Rectangle { anchors.fill: parent; color: Colors.background }

    ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(0)

        // ── Header (brand · tabs · provider · settings · minimize) ────────────
        PanelHeader {
            Layout.fillWidth: true; z: 2
            tabs: [I18n.t("tab.browse"), I18n.t("tab.library")]
            tabIndex: root.tabIndex
            tabCounts: [Novel.novelList.length, Novel.libraryList.length]
            brand: brandComponent
            fontFamily: root.fontBody
            settingsMode: root.settingsMode
            onTabActivated: function(index) {
                root.settingsMode = false
                root.tabIndex = index
            }
            onSettingsClicked: root.settingsMode = !root.settingsMode
            onMinimizeClicked: root.minimize()

            // The provider picker stays in the header (owner, round 6: it is
            // used all the time to switch sources), as one cell of the row.
            extraCell: Item {
                id: providerButton
                implicitWidth: providerRow.implicitWidth + Style.spacing.xl * 2

                // One cell of the header row: plain until hovered, like the
                // tabs beside it (owner, round 6).
                Rectangle {
                    anchors.fill: parent
                    color: providerDropArea.containsMouse
                        ? Style.hoverFillFor(Colors.muted, Colors.primary) : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.base } }
                }

                Row {
                    id: providerRow
                    anchors.centerIn: parent
                    spacing: Style.space(5)

                    StyledText {
                        text: {
                            for (var i = 0; i < Novel.availableProviders.length; i++) {
                                if (Novel.availableProviders[i].name === Novel.activeProvider)
                                    return Novel.availableProviders[i].label
                            }
                            return Novel.activeProvider
                        }
                        font.family: root.fontBody; font.pixelSize: Style.font.bodySmall
                        font.letterSpacing: 0.3
                        color: Novel.isSwitchingProvider ? Colors.on_surface_variant : Colors.on_surface
                        anchors.verticalCenter: parent.verticalCenter
                        Behavior on color { ColorAnimation { duration: Motion.base } }
                    }

                    Spinner {
                        visible: Novel.isSwitchingProvider
                        width: 10; border.width: 1.5
                        anchors.verticalCenter: parent.verticalCenter
                        duration: Motion.loop
                        running: Novel.isSwitchingProvider
                    }

                    // The arrow is a Material Design Icons glyph: the text
                    // "▾" this used to draw is not in the theme font and showed
                    // up as a dot in the round-6 capture (owner report).
                    MaterialIcon {
                        visible: !Novel.isSwitchingProvider
                        text: "󰅀"
                        font.pixelSize: Style.font.caption
                        color: Colors.on_surface_variant
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: providerDropArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: if (!Novel.isSwitchingProvider) providerPopup.visible = !providerPopup.visible
                }

                Rectangle {
                    id: providerPopup
                    visible: false
                    anchors { top: parent.bottom; right: parent.right; topMargin: Style.spacing.md }
                    width: 160
                    height: providerList.implicitHeight + Style.spacing.md * 2
                    radius: Style.cornerRadius
                    color: Colors.surface_container_high
                    border.color: Colors.outline_variant
                    border.width: 1
                    z: 100

                    Column {
                        id: providerList
                        anchors { fill: parent; margins: Style.spacing.md }
                        spacing: Style.spacing.xs

                        Repeater {
                            model: Novel.availableProviders

                            delegate: ClickableRect {
                                required property var modelData

                                width: parent.width
                                height: 30
                                radius: Style.cornerRadius
                                color: modelData.name === Novel.activeProvider
                                    ? Style.selectedFillFor(Colors.text, Colors.primary) : "transparent"
                                cursorShape: Qt.PointingHandCursor

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: Style.spacing.sm
                                    text: modelData.label
                                    font.family: root.fontBody
                                    font.pixelSize: Style.font.bodySmall
                                    color: modelData.name === Novel.activeProvider ? Colors.text : Colors.on_surface_variant
                                }

                                onClicked: {
                                    Novel.setProvider(modelData.name)
                                    providerPopup.visible = false
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Search field (always on screen, under the header) ────────────────
        SearchField {
            id: searchField
            visible: root.tabIndex === 0 && !root.settingsMode
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(30)
            Layout.leftMargin: Style.spacing.md
            Layout.rightMargin: Style.spacing.md
            Layout.topMargin: Style.spacing.sm
            Layout.bottomMargin: Style.spacing.sm
            placeholder: I18n.t("novel.search")
            fontFamily: root.fontBody
            onEdited: searchDebounce.restart()
            onCleared: root.closeSearch()
        }

        // The one debounce the field goes through.
        Timer {
            id: searchDebounce
            interval: 350
            onTriggered: {
                if (searchField.text.trim().length > 0) {
                    browseView.currentFilter = "search"
                    Novel.searchNovels(searchField.text.trim(), "", "All", true)
                } else {
                    browseView.resetList()
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            currentIndex: root.settingsMode ? root.settingsPageIndex : root.tabIndex


            Item {
                BrowseView {
                    id: browseView
                    anchors.fill: parent
                    visible: root.browseStack === 0
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.slow; easing.type: Motion.easeOut } }

                    onSearchCleared: root.clearSearch()

                    onNovelSelected: function(novelId) {
                        root.browseStack = 1
                    }
                }

                DetailView {
                    id: browseDetail
                    anchors.fill: parent
                    visible: root.browseStack === 1
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.slow; easing.type: Motion.easeOut } }

                    onBackRequested:    { root.browseStack = 0 }
                    onChapterSelected:  { root.browseStack = 2 }
                }

                ReaderView {
                    id: browseReader
                    anchors.fill: parent
                    visible: root.browseStack === 2
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.slow; easing.type: Motion.easeOut } }

                    isFullscreen: root.fullscreen
                    onToggleFullscreen: root.fullscreen = !root.fullscreen

                    onBackRequested: {
                        root.browseStack = 1
                        browseReader.reset()
                    }
                }
            }

            Item {
                LibraryView {
                    anchors.fill: parent
                    visible: root.libraryStack === 0
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.slow; easing.type: Motion.easeOut } }

                    onNovelSelected: function(novelId) {
                        root.libraryStack = 1
                    }
                }

                DetailView {
                    id: libraryDetail
                    anchors.fill: parent
                    visible: root.libraryStack === 1
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.slow; easing.type: Motion.easeOut } }

                    onBackRequested:   { root.libraryStack = 0 }
                    onChapterSelected: { root.libraryStack = 2 }
                }

                ReaderView {
                    id: libraryReader
                    anchors.fill: parent
                    visible: root.libraryStack === 2
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.slow; easing.type: Motion.easeOut } }

                    isFullscreen: root.fullscreen
                    onToggleFullscreen: root.fullscreen = !root.fullscreen

                    onBackRequested: {
                        root.libraryStack = 1
                        libraryReader.reset()
                    }
                }
            }

            // Settings view (gear in the header). Third page of the same stack,
            // so Browse/Library keep their state while it is open.
            PanelSettings {
                showScroll: true
                active: root.settingsMode
                onCloseRequested: root.settingsMode = false
            }
        }

        // ── Status bar ────────────────────────────────────────────────────────
        // The same strip as the other two panels: connection, the count of the
        // list on screen, and the version with the shortcuts that work.
        StatusBar {
            Layout.fillWidth: true
            online: Novel.serverReady
            countText: StatusLine.barText({
                settingsMode: root.settingsMode,
                tabIndex: root.tabIndex,
                browseCount: Novel.novelList.length,
                libraryCount: Novel.libraryList.length,
                translate: I18n.tn
            })
            fontFamily: root.fontBody
        }
    }

    PanelDecor {
        title: I18n.t("panel.novel")
    }
}
