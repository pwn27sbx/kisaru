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
    // Owner §33: the search is a header icon that grows a field over the brand.
    property bool searchOpen: false
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
        // Both tabs: Browse queries the source, Library filters what is saved
        // (owner §33.1).
        enabled: root.visible && !root.settingsMode
                 && !(header && header.searchActiveFocus)
        onActivated: root.focusSearch()
    }

    function toggleSearch() {
        if (root.searchOpen) {
            root.closeSearch()
            return
        }
        if (root.settingsMode) return
        root.focusSearch()
    }

    function focusSearch() {
        if (header) {
            root.searchOpen = true
            header.forceFocus()
        }
    }

    // Puts the field away without touching the list.
    function collapseSearch() {
        if (!header) return
        // A query typed a moment before closing must not fire afterwards: stop
        // the timer and drop the text (review R3-search-debounce-after-close).
        searchDebounce.stop()
        header.clear()
        header.blur()
        root.searchOpen = false
    }

    // Clears the text only: Browse calls this when a filter invalidates the
    // query, and the field stays where the user was typing.
    function clearSearch() {
        if (header) header.clear()
    }

    // Esc: empty the field, hand the focus back and show the unfiltered list.
    function closeSearch() {
        if (!header) return
        root.collapseSearch()
        if (root.tabIndex === 0) browseView.resetList()
    }

    function _sendBrowseQuery(text) {
        browseView.currentFilter = "search"
        Novel.searchNovels(text, "", "All", true)
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
            id: header
            Layout.fillWidth: true; z: 2
            tabs: [I18n.t("tab.browse"), I18n.t("tab.library")]
            tabIndex: root.tabIndex
            // Browse carries no number; Library shows a badge, hidden at 0 (A-8).
            tabCounts: [-1, Novel.visibleCount()]
            brand: brandComponent
            fontFamily: root.fontBody
            settingsMode: root.settingsMode
            filters: root.tabIndex === 0 && !root.settingsMode ? browseView.filterOptions : []
            filterValue: browseView.filterValue
            filterFallbackLabel: browseView.filterFallbackLabel
            filterDimmed: browseView.filterDimmed
            searchOpen: root.searchOpen
            searchPlaceholder: I18n.t("novel.search")
            onFilterChosen: function(value) { browseView.chooseFilter(value) }
            onSearchClicked: root.toggleSearch()
            onSearchEdited: searchDebounce.restart()
            onSearchCleared: root.closeSearch()
            onTabActivated: function(index) {
                root.settingsMode = false
                root.tabIndex = index
                root.collapseSearch()
            }
            onSettingsClicked: {
                root.settingsMode = !root.settingsMode
                root.collapseSearch()
            }
            onMinimizeClicked: root.minimize()

            // The provider picker stays in the header (owner, round 6: it is
            // used all the time to switch sources). It is the same MenuSelect as
            // the tool bar's filter menu (owner, §32: never a second copy), so it
            // also gains the keyboard it never had: Enter/Space opens, ↑/↓ move,
            // Enter picks, Esc closes.
            extraCell: MenuSelect {
                controlHeight: Style.space(48)
                options: Novel.availableProviders.map(function(provider) {
                    return { label: provider.label, value: provider.name }
                })
                currentValue: Novel.activeProvider
                busy: Novel.isSwitchingProvider
                dimmed: Novel.isSwitchingProvider
                fontFamily: root.fontBody
                onChosen: function(value) { Novel.setProvider(value) }
            }
        }

        // No second row (owner §33): the header carries the filter, the search
        // and the icons; the layout switch lives in the settings page.

        // The one debounce the field goes through.
        Timer {
            id: searchDebounce
            interval: 350
        onTriggered: {
            // Library filters locally (owner §33.1): no network here.
            if (root.tabIndex !== 0) return
            var text = header.searchText.trim()
            if (text.length === 0) {
                browseView.resetList()
                return
            }
            // A tag miss searches at once. On a hit the query is held
            // while the helper decides; only "no match" sends it.
            var started = Privacy.consider(text, function(code) {
                if (code === 1) root._sendBrowseQuery(text)
                else if (code === 0) root.collapseSearch()
            })
            if (started === "miss") root._sendBrowseQuery(text)
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
                    id: libraryView
                    query: root.searchOpen && root.tabIndex === 1 ? header.searchText : ""
                    onSecretEntered: root.collapseSearch()
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
                    onHiddenRequested: {
                        root.tabIndex = 1
                        root.browseStack = 0
                        root.libraryStack = 0
                        Novel.clearDetail()
                    }

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
                layouts: [ { id: "grid", label: I18n.t("view.grid") },
                           { id: "list", label: I18n.t("view.list") } ]
                layout: UiPrefs.viewModeFor("novel")
                onLayoutSelected: function(id) { UiPrefs.setViewMode("novel", id) }
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
                libraryCount: Novel.visibleCount(),
                folderName: libraryView.activeFolderName,
                translate: I18n.tn
            })
            fontFamily: root.fontBody
        }
    }

    PanelDecor {
        title: I18n.t("panel.novel")
    }

    // One hook: when the mode locks, a hidden title leaves no reader behind.
    Connections {
        target: Privacy
        function onLockedChanged() {
            if (!Privacy.locked) return
            root.collapseSearch()
            if (Novel.currentNovel && Novel.isHiddenLibraryEntry(Novel.currentNovel.id)) {
                root.tabIndex = 1
                root.browseStack = 0
                root.libraryStack = 0
                browseDetail.reset()
                libraryDetail.reset()
                Novel.clearDetail()
            }
        }
    }
}
