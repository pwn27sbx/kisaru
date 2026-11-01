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

    // ── Search ────────────────────────────────────────────────────────────────
    // The field is always on screen under the header (Stitch's sub-bar), so
    // there is no open/closed state any more: "/" focuses it, Esc clears it and
    // leaves, and the one debounce below stays the only path to
    // Manga.searchManga.
    function focusSearch() {
        if (searchField) searchField.forceFocus()
    }

    // Clears the text only: Browse calls this when a filter invalidates the
    // query, and the field must stay where the user is typing.
    function clearSearch() {
        if (searchField) searchField.clear()
    }

    // Esc: empty the field, hand the focus back and show the unfiltered list
    // again — the end state the closed overlay used to leave.
    function closeSearch() {
        if (!searchField) return
        searchField.blur()
        browseView.resetList()
    }

    // "Search other sources" from the no-Spanish notice: go back to Browse and
    // re-run the search for the current title across every source (plan §F3).
    function searchOtherSources() {
        const title = Manga.detailTitle || ""
        root.tabIndex = 0
        root.browseStack = 0
        if (searchField) {
            searchField.text = title
            searchField.forceActiveFocus()
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
        enabled: root.visible && !root.settingsMode && root.tabIndex === 0
                 && !(searchField && searchField.activeFocus)
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
            if (searchField.text.trim().length > 0)
                Manga.searchManga(searchField.text.trim(), true)
            else
                browseView.resetList()
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
            Layout.fillWidth: true
            z: 2
            tabs: [I18n.t("tab.browse"), I18n.t("tab.library")]
            tabIndex: root.tabIndex
            brand: brandComponent
            // Browse carries no number (the bar counts it); Library shows a badge,
            // and hides it at 0 (owner, A-8).
            tabCounts: [-1, Manga.libraryList.length]
            fontFamily: root.fontBody
            settingsMode: root.settingsMode
            onTabActivated: function(index) {
                root.settingsMode = false
                root.tabIndex = index
            }
            onSettingsClicked: root.settingsMode = !root.settingsMode
            onMinimizeClicked: root.minimize()
        }

        // ── Search field (always on screen, under the header) ─────────────────
        // The shared pill (components/SearchField.qml): the panel keeps the
        // debounce and the service call, nothing else.
        SearchField {
            id: searchField
            visible: root.tabIndex === 0 && !root.settingsMode
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(30)
            Layout.leftMargin: Style.spacing.md
            Layout.rightMargin: Style.spacing.md
            Layout.topMargin: Style.spacing.sm
            Layout.bottomMargin: Style.spacing.sm
            placeholder: I18n.t("manga.search")
            fontFamily: root.fontBody
            onEdited: searchDebounce.restart()
            onCleared: root.closeSearch()
        }

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
                libraryCount: Manga.libraryList.length,
                translate: I18n.tn
            })
            fontFamily: root.fontBody
        }
    }

    PanelDecor {
        title: I18n.t("panel.manga")
    }
}
