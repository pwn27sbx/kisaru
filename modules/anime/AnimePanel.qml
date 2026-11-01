import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.app
import qs.Commons
import qs.services
import qs.modules.anime.components
import qs.components
import qs.Ui
import "../../services/status_line.js" as StatusLine
import "../../services/prefs.js" as Prefs

Item {
    id: root

    // El panel se atenúa cuando el puntero no está encima (pintado sobre la
    // pantalla, ver shell.qml). HoverHandler escucha el área completa del panel,
    // no solo sus hijos.
    HoverHandler { id: pointer }

    readonly property bool pointerInside: pointer.hovered
    anchors {
        left:   parent.left
        bottom:  parent.bottom
        top: parent.top
    }
    implicitWidth: 540
    visible: false

    readonly property string fontBody: Style.font.family

    // ── Tab state ─────────────────────────────────────────────────────────────
    property int tabIndex: 0       // 0 = Browse, 1 = Library

    // Gear in the header: the settings view replaces the content stack.
    property bool settingsMode: false
    readonly property int settingsPageIndex: 2   // third page of the content stack

    // ── Navigation stacks (0 = list, 1 = detail) ──────────────────────────────
    // No "reader" stack — MPV handles playback externally
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
        PanelBrand { title: I18n.t("brand.anime"); fontFamily: root.fontBody }
    }

    // ── Background ────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Colors.background
        // Top edge shadow / divider
        Divider {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            opacity: 0.5
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(0)

        // ── Header (brand · tabs · settings · minimize) ───────────────────────
        PanelHeader {
            Layout.fillWidth: true
            z: 2
            tabs: [I18n.t("tab.browse"), I18n.t("tab.library")]
            tabIndex: root.tabIndex
            tabCounts: [Anime.animeList.length, Anime.libraryList.length]
            brand: brandComponent
            fontFamily: root.fontBody
            settingsMode: root.settingsMode
            onTabActivated: function(index) {
                root.settingsMode = false
                root.tabIndex = index
            }
            onSettingsClicked: root.settingsMode = !root.settingsMode
            onMinimizeClicked: root.minimize()
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
            placeholder: I18n.t("anime.search")
            fontFamily: root.fontBody
            onEdited: searchDebounce.restart()
            onCleared: root.closeSearch()
        }

        // The one debounce the field goes through. It sits at the panel's root
        // so the query survives the field being hidden on the library tab.
        Timer {
            id: searchDebounce
            interval: 350
            onTriggered: {
                if (searchField.text.trim().length > 0)
                    Anime.searchAnime(searchField.text.trim(), true)
                else
                    browseView.resetList()
            }
        }

        // ── Main content (Browse / Library stacks) ────────────────────────────
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.settingsMode ? root.settingsPageIndex : root.tabIndex


            // ── Browse tab ────────────────────────────────────────────────────
            Item {
                BrowseView {
                    id: browseView
                    anchors.fill: parent
                    visible: root.browseStack === 0
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.slow; easing.type: Motion.easeOut } }

                    onSearchCleared: root.clearSearch()

                    onAnimeSelected: function(show) {
                        Anime.fetchAnimeDetail(show)
                        root.browseStack = 1
                    }
                }

                DetailView {
                    anchors.fill: parent
                    visible: root.browseStack === 1
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.slow; easing.type: Motion.easeOut } }

                    onBackRequested: {
                        root.browseStack = 0
                        Anime.clearDetail()
                    }
                }
            }

            // ── Library tab ───────────────────────────────────────────────────
            Item {
                LibraryView {
                    anchors.fill: parent
                    visible: root.libraryStack === 0
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.slow; easing.type: Motion.easeOut } }

                    onAnimeSelected: function(show) {
                        Anime.fetchAnimeDetail(show)
                        root.libraryStack = 1
                    }
                }

                DetailView {
                    anchors.fill: parent
                    visible: root.libraryStack === 1
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.slow; easing.type: Motion.easeOut } }

                    onBackRequested: {
                        root.libraryStack = 0
                        Anime.clearDetail()
                    }
                }
            }

            // Settings view (gear in the header). Third page of the same stack,
            // so Browse/Library keep their state while it is open.
            PanelSettings {
                showScroll: false
                active: root.settingsMode
                // SUB/DUB lives here now (owner, round 6): a preference like the
                // language, persisted with the rest. The rows come from
                // services/prefs.js, the same table that validates the value.
                modes: Prefs.ANIME_MODE_OPTIONS
                mode: Anime.currentMode
                onModeSelected: function(id) { Anime.setMode(id) }
                onCloseRequested: root.settingsMode = false
            }
        }

        // ── Status bar ────────────────────────────────────────────────────────
        // Online, the loaded count and the active audio mode: "● Online ·
        // 32 loaded · SUB" (owner, round 6). The count uses the wording the
        // manga panel already had, and the mode is a key name, not UI copy.
        StatusBar {
            Layout.fillWidth: true
            online: Anime.serverReady
            // Same rule as the manga bar: the loaded count on Browse, the
            // library's own size on Library, nothing on the settings page.
            countText: StatusLine.barText({
                settingsMode: root.settingsMode,
                tabIndex: root.tabIndex,
                browseCount: Anime.animeList.length,
                libraryCount: Anime.libraryList.length,
                translate: I18n.tn
            })
            modeText: Anime.currentMode.toUpperCase()
            fontFamily: root.fontBody
        }
    }

    PanelDecor {
        title: I18n.t("panel.anime")
    }
}
