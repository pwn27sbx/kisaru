import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.app
import qs.Commons
import qs.services
import qs.modules.manga.components
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
        left: parent.left
    }
    // The owner's width for this panel (round 4): 550 with three columns puts a
    // card at (550 - 2 * 10) / 3 = 176.7 px. 430 was good for browsing and too
    // narrow for reading, and the reader opens in this same panel; 550 trades
    // some of Stitch's card proportion for a readable page. The anime and novel
    // panels keep their own widths; nothing here is shared.
    implicitWidth: 550
    visible: false

    readonly property string fontBody: Style.font.family

    property int tabIndex: 0

    // Gear in the header: the settings view replaces the content stack.
    property bool settingsMode: false
    // Owner §33: the search is a header icon that grows a field over the brand.
    property bool searchOpen: false
    readonly property int settingsPageIndex: 2   // third page of the content stack

    property int browseStack: 0
    property int libraryStack: 0

    property string selectedMangaId: ""

    // Hidden but kept loaded: shell.qml skips the unload while this is set,
    // so the toggle brings the panel back exactly as it was left.
    property bool minimized: false

    function minimize() {
        minimized = true
        visible = false
    }

    // ── Search (owner §33: an icon in the header, not a bar under it) ────────
    // The icon opens the field that grows leftwards over the brand and the tabs;
    // Esc or clearing it puts it away. The one debounce below stays the only
    // path to Manga.searchManga.
    function toggleSearch() {
        if (root.searchOpen) {
            root.closeSearch()
            return
        }
        if (root.settingsMode) return
        root.focusSearch()
    }

    function focusSearch() {
        if (!header) return
        root.searchOpen = true
        header.forceFocus()
    }

    // Puts the field away without touching the list (a tab change must not
    // refetch Browse just because the search was open).
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
    // query, and the field stays where the user is typing.
    function clearSearch() {
        if (header) header.clear()
    }

    // Esc: put the field away and show the unfiltered list again.
    function closeSearch() {
        if (!header) return
        root.collapseSearch()
        if (root.tabIndex === 0) browseView.resetList()
    }

    function _sendBrowseQuery(text) {
        Manga.searchManga(text, true)
    }

    // "Search other sources" from the no-Spanish notice: go back to Browse and
    // re-run the search for the current title across every source (plan §F3).
    function searchOtherSources() {
        const title = Manga.detailTitle || ""
        root.tabIndex = 0
        root.browseStack = 0
        if (header) {
            root.searchOpen = true
            header.setText(title)
            header.forceFocus()
        }
        if (title.length > 0)
            Manga.searchManga(title, true)
        else
            browseView.resetList()
    }

    // "/" focuses the search field. The panel stays loaded while minimized, so
    // the visibility guard is what keeps it from firing over another panel; the
    // focus guard is what keeps a "/" TYPED IN the field (or the settings page
    // showing) from being swallowed by the shortcut.
    Shortcut {
        sequence: "/"
        context: Qt.WindowShortcut
        // Both tabs: Browse queries the source, Library filters what is saved
        // (owner §33.1).
        enabled: root.visible && !root.settingsMode
                 && !(header && header.searchActiveFocus)
        onActivated: root.focusSearch()
    }

    // The one debounce the field goes through. It sits at the panel's root, not
    // inside a layout: it is not an Item, and the query must survive the search
    // bar being hidden on the library tab. `Manga.searchManga` (reset) and
    // `browseView.resetList` are the same calls the header overlay made.
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
            // A tag miss searches at once. On a hit the query is held while
            // the helper decides; only "no match" sends it.
            var started = Privacy.consider(text, function(code) {
                if (code === 1) root._sendBrowseQuery(text)
                else if (code === 0) root.collapseSearch()
            })
            if (started === "miss") root._sendBrowseQuery(text)
        }
    }

    // Header brand: the panel's name; PanelBrand sets it in caps without a
    // glyph for all three panels now (owner, round 6).
    Component {
        id: brandComponent
        PanelBrand {
            title: I18n.t("brand.manga")
            fontFamily: root.fontBody
        }
    }

    Rectangle { anchors.fill: parent; color: Colors.background }

    ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(0)

        // ── Header (brand · tabs · settings · minimize) ───────────────────────
        // The search field moved out of the header: it is always visible below
        // it now, so the header's own expanding search would only duplicate it.
        PanelHeader {
            id: header
            Layout.fillWidth: true
            z: 2
            tabs: [I18n.t("tab.browse"), I18n.t("tab.library")]
            tabIndex: root.tabIndex
            brand: brandComponent
            // Browse carries no number (the bar counts it); Library shows a badge,
            // and hides it at 0 (owner, A-8).
            tabCounts: [-1, Manga.visibleCount()]
            fontFamily: root.fontBody
            settingsMode: root.settingsMode
            filters: root.tabIndex === 0 && !root.settingsMode ? browseView.filterOptions : []
            filterValue: browseView.filterValue
            filterFallbackLabel: ""
            filterDimmed: false
            searchOpen: root.searchOpen
            searchPlaceholder: I18n.t("manga.search")
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
            lockVisible: Privacy.configured && !Privacy.locked
            onLockClicked: Privacy.lock()
            onMinimizeClicked: root.minimize()
        }

        // No second row (owner §33): the header carries the filter, the search
        // and the icons; the layout switch lives in the settings page.

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.settingsMode ? root.settingsPageIndex : root.tabIndex


            Item {

                BrowseView {
                    id: browseView
                    anchors.fill: parent
                    visible: root.browseStack === 0
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.slow; easing.type: Motion.easeOut } }

                    onSearchCleared: root.clearSearch()

                    onMangaSelected: function(mangaId) {
                        root.selectedMangaId = mangaId
                        root.browseStack = 1
                    }
                }

                DetailView {
                    id: browseDetail
                    anchors.fill: parent
                    visible: root.browseStack === 1
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.slow; easing.type: Motion.easeOut } }

                    onBackRequested:   { root.browseStack = 0 }
                    onChapterSelected: { root.browseStack = 2 }
                    onSearchOtherSourcesRequested: root.searchOtherSources()
                }

                ReaderView {
                    id: browseReader
                    anchors.fill: parent
                    visible: root.browseStack === 2
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.slow; easing.type: Motion.easeOut } }

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

                    onMangaSelected: function(mangaId) {
                        root.selectedMangaId = mangaId
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
                    onSearchOtherSourcesRequested: root.searchOtherSources()
                }

                ReaderView {
                    id: libraryReader
                    anchors.fill: parent
                    visible: root.libraryStack === 2
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.slow; easing.type: Motion.easeOut } }

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
                layout: UiPrefs.viewModeFor("manga")
                onLayoutSelected: function(id) { UiPrefs.setViewMode("manga", id) }
                onCloseRequested: root.settingsMode = false
            }
        }

        // ── Status bar ────────────────────────────────────────────────────────
        // Online state, the installed version and the shortcuts that work.
        // No cache size and no tracker (owner decision 3).
        StatusBar {
            Layout.fillWidth: true
            online: Manga.serverReady
            // The count moved out of the grid's heading (owner, round 4): the
            // rules live in services/status_line.js, where they are tested.
            countText: StatusLine.barText({
                settingsMode: root.settingsMode,
                tabIndex: root.tabIndex,
                browseCount: Manga.mangaList.length,
                libraryCount: Manga.visibleCount(),
                folderName: libraryView.activeFolderName,
                translate: I18n.tn
            })
            fontFamily: root.fontBody
        }
    }

    PanelDecor {
        title: I18n.t("panel.manga")
    }

    // One hook: when the mode locks, a hidden title leaves no reader behind.
    Connections {
        target: Privacy
        function onLockedChanged() {
            if (!Privacy.locked) return
            root.collapseSearch()
            if (Manga.isHiddenLibraryEntry(Manga.currentLibraryId)) {
                root.tabIndex = 1
                root.browseStack = 0
                root.libraryStack = 0
                browseDetail.reset()
                libraryDetail.reset()
                Manga.clearDetail()
            }
        }
    }
}
