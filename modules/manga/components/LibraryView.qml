import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.app
import qs.Commons
import qs.services
import qs.components
import "../../../services/library_filter.js" as LibraryFilter
import "../../../services/library_view.js" as LibraryViewJs
import "../../../services/folder_cards.js" as FolderCards
import "../../../services/manga_card.js" as MangaCard
import "../../../services/list_metrics.js" as ListMetrics

Item {
    id: libraryView

    // The header's local search. It crosses every visible title, whatever
    // folder it lives in, so it starts from the whole visible shelf.
    property string query: ""
    // "" is the root (folders + titles with no folder); anything else is the
    // open folder. Typing a query from inside a folder returns to the root,
    // because search is library-wide.
    property string activeFolder: ""

    readonly property var _allVisible: Manga.visibleEntries("")
    readonly property var _folders:
        LibraryViewJs.visibleFolders(Organizer.folders("manga"), Privacy.locked)
    readonly property var _split:
        FolderCards.partition(_allVisible, LibraryViewJs.folderIdOf)
    readonly property var _searchResults:
        FolderCards.searchTitles(_allVisible, query, LibraryFilter.fold,
            function(entry) { return entry.title || "" })
    readonly property var _rootItems:
        FolderCards.rootItems(_folders, _split.folderless, _split.byFolder,
            function(entry) { return Manga.serverReady ? (entry.coverUrl || "") : "" })
    readonly property var _folderEntries:
        (!libraryView.folderOpen) ? [] : (_split.byFolder[activeFolder] || [])
    readonly property bool _searching: query.trim() !== ""
    readonly property var _titleList:
        _searching ? _searchResults
            : (libraryView.folderOpen ? _folderEntries : _split.folderless)

    // Folders first, then titles with no folder, then the dashed create card.
    // A query or an open folder is a title-only view.
    readonly property var model: {
        if (_searching || libraryView.folderOpen) {
            var titles = []
            for (var i = 0; i < _titleList.length; i++)
                titles.push({ kind: "title", entry: _titleList[i] })
            return titles
        }
        var items = _rootItems.slice()
        items.push({ kind: "create" })
        return items
    }

    readonly property bool activeFolderHidden:
        activeFolder !== "" && Organizer.isHidden("manga", activeFolder)
    // Closed off only while locked and hidden or unresolved: a visible folder
    // opens while locked and without a secret, and an unresolved one fails
    // closed. The hidden folder itself is only reachable while unlocked.
    readonly property bool activeFolderLockedOut:
        LibraryViewJs.lockedOut(activeFolder, Organizer.folders("manga"),
            { loaded: Organizer.loaded, locked: Privacy.locked })
    readonly property string activeFolderName:
        (activeFolder === "" || activeFolderLockedOut) ? "" : ((Organizer.folder("manga", activeFolder) || {}).name || "")
    readonly property bool folderOpen: activeFolder !== "" && !_searching && !activeFolderLockedOut

    readonly property string fontDisplay: Style.font.family
    readonly property string fontBody: Style.font.family

    // metaLine composes "chapter · status"; the wording lives in
    // manga_card.js, so both views share one adapter instead of copying it.
    readonly property var cardTranslator: MangaCard.translator(I18n.t)

    // The layout the user picked (persisted in settings.json), shared with
    // Browse through UiPrefs: switching it in one view switches it in both.
    readonly property bool listMode: UiPrefs.viewModeFor("manga") === "list"

    // Emitted when the user taps an entry — parent handles navigation
    signal mangaSelected(string mangaId)
    // The panel answers by putting the search field away.
    signal secretEntered()

    // The secret hook (amendment 11): a query never typed into the folder
    // search, and the field collapses on a verified word.
    onQueryChanged: {
        if (query.trim() !== "" && libraryView.activeFolder !== "")
            libraryView.activeFolder = ""
        if (!Privacy.configured) return
        Privacy.consider(query, function(code) {
            if (code === 0) libraryView.secretEntered()
        })
    }

    // Which prompt is open, and for which folder. One dialog, three actions.
    property string _promptAction: ""
    property string _promptFolder: ""

    function _newFolder() {
        _promptAction = "create"
        _promptFolder = ""
        folderPrompt.openText(I18n.t("folder.create"), "")
    }

    function _renameFolder(folderId) {
        if (activeFolderLockedOut) return
        var folder = Organizer.folder("manga", folderId)
        _promptAction = "rename"
        _promptFolder = folderId
        folderPrompt.openText(I18n.t("folder.rename"), folder ? folder.name : "")
    }

    function _confirmDelete(folderId) {
        if (activeFolderLockedOut) return
        var folder = Organizer.folder("manga", folderId)
        if (!folder) return
        _promptAction = "delete"
        _promptFolder = folderId
        folderPrompt.openConfirm(I18n.t("folder.delete"),
            folder.hidden ? I18n.t("folder.deleteHidden") : I18n.t("folder.deleteMessage"))
    }

    function _acceptPrompt(value) {
        if (libraryView._promptAction === "create") {
            Organizer.addFolder("manga", value)
        } else if (libraryView._promptAction === "rename") {
            Organizer.renameFolder("manga", libraryView._promptFolder, value)
        } else if (libraryView._promptAction === "delete") {
            if (libraryView.activeFolder === libraryView._promptFolder)
                libraryView.activeFolder = ""
            Manga.deleteFolder(libraryView._promptFolder)
        }
        libraryView._promptAction = ""
        libraryView._promptFolder = ""
    }

    function _pruneFolder() {
        if (activeFolder !== "" && Organizer.folder("manga", activeFolder) === null)
            activeFolder = ""
    }

    // Hide at once and return to the root; while unlocked, turning the switch
    // off on a hidden folder un-hides it and keeps the folder open.
    function _toggleHideFolder() {
        if (!Privacy.configured || activeFolder === "") return
        var hidden = Organizer.isHidden("manga", activeFolder)
        if (Privacy.locked) {
            if (!hidden) Organizer.setHidden("manga", activeFolder, true)
            activeFolder = ""
            return
        }
        if (hidden) {
            Organizer.setHidden("manga", activeFolder, false)
            return
        }
        Organizer.setHidden("manga", activeFolder, true)
        Privacy.lock()
        activeFolder = ""
    }

    Rectangle { anchors.fill: parent; color: Colors.background }

    ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(0)

        // ── Open folder: back, name, count, and the folder's own actions ─────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(40)
            Layout.leftMargin: Gutter.left + Gutter.ink
            Layout.rightMargin: Gutter.right + Gutter.ink
            spacing: Style.spacing.sm
            visible: libraryView.folderOpen

            ClickableRect {
                Layout.preferredWidth: Style.space(28)
                Layout.preferredHeight: Style.space(28)
                color: hovered ? Colors.surface_container_high : "transparent"
                radius: Style.cornerRadius
                StyledText {
                    anchors.centerIn: parent
                    text: "←"
                    font.family: libraryView.fontBody
                    font.pixelSize: Style.font.iconLarge
                    color: Colors.on_surface_variant
                }
                onClicked: libraryView.activeFolder = ""
            }

            StyledText {
                Layout.fillWidth: true
                text: libraryView.activeFolderName
                font.family: libraryView.fontBody
                font.pixelSize: Style.font.body
                font.bold: true
                color: Colors.on_surface
                elide: Text.ElideRight
            }

            StyledText {
                text: I18n.tn("folder.count", libraryView._folderEntries.length)
                font.family: libraryView.fontBody
                font.pixelSize: Style.font.caption
                color: Colors.card_secondary
            }

            // The hidden state is named, not inferred from a dim glyph.
            Rectangle {
                visible: libraryView.activeFolderHidden
                Layout.preferredHeight: Style.space(18)
                Layout.preferredWidth: hiddenMark.implicitWidth + 2 * Style.spacing.controlPaddingX
                radius: Style.cornerRadius
                color: Colors.primary_container
                border.color: Colors.primary
                border.width: Style.spacing.hairline

                StyledText {
                    id: hiddenMark
                    anchors.centerIn: parent
                    text: I18n.t("folder.hiddenMark")
                    font.family: libraryView.fontBody
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    color: Colors.primary
                }
            }

            Item { Layout.fillWidth: true }

            // Hide/show keeps the private mode usable once the chip row is gone.
            HideSwitch {
                visible: Privacy.configured
                label: I18n.t("folder.hide")
                checked: !Privacy.locked && libraryView.activeFolderHidden
                bodyFont: libraryView.fontBody
                onClicked: libraryView._toggleHideFolder()
            }

            FolderAction {
                visible: !activeFolderLockedOut
                icon: "󰏫"
                label: I18n.t("folder.renameShort")
                bodyFont: libraryView.fontBody
                onClicked: libraryView._renameFolder(libraryView.activeFolder)
            }

            FolderAction {
                visible: !activeFolderLockedOut
                icon: "󰆴"
                label: I18n.t("folder.deleteShort")
                iconTone: Colors.error
                bodyFont: libraryView.fontBody
                onClicked: libraryView._confirmDelete(libraryView.activeFolder)
            }
        }

        // ── Loading (first open before file is read) ──────────────────────────
        SkeletonGrid {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: Gutter.left
            Layout.rightMargin: Gutter.right
            visible: !Manga.libraryLoaded && !libraryView.listMode
            active: !Manga.libraryLoaded && !libraryView.listMode
            columns: CardMetrics.columns
            padding: Style.space(0)
            cellHeight: CardMetrics.cellHeight(width / CardMetrics.columns, Style.space(30))
            footerHeight: 30
        }

        SkeletonList {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: Gutter.left
            Layout.rightMargin: Gutter.right
            rowHeight: Style.space(ListMetrics.ROW_HEIGHT_BASE)
            cover: true
            inset: Gutter.ink
            active: !Manga.libraryLoaded && libraryView.listMode
        }

        GridView {
            id: libGrid
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: Manga.libraryLoaded && !libraryView.listMode
            topMargin: Style.spacing.xl
            leftMargin: Gutter.left
            rightMargin: Gutter.right
            bottomMargin: Style.spacing.xl
            cellWidth: (width - leftMargin - rightMargin) / CardMetrics.columns
            cellHeight: CardMetrics.cellHeight(cellWidth, Style.space(30))
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: libraryView.model

            delegate: Item {
                width: libGrid.cellWidth
                height: libGrid.cellHeight

                readonly property var item: modelData
                readonly property var entry: item.kind === "title" ? item.entry : null
                readonly property var folderData: item.kind === "folder" ? item : null

                CoverCard {
                    visible: entry !== null
                    anchors.fill: parent
                    source: entry && Manga.serverReady ? (entry.coverUrl || "") : ""
                    title: entry ? (entry.title || "") : ""
                    bodyFont: libraryView.fontBody
                    footerHeight: 30
                    metaChapter: entry
                        ? MangaCard.metaLine(entry.chapter, "", libraryView.cardTranslator) : ""
                    metaStatus: entry ? I18n.tData(entry.status || "") : ""
                    metaTone: entry ? MangaCard.statusTone(entry.status || "") : "muted"

                    CoverProgressBar {
                        height: 30
                        rowSpacing: Style.spacing.md
                        bodyFont: libraryView.fontBody
                        started: entry ? entry.lastReadChapterNum : ""
                        label: entry && entry.lastReadChapterNum
                                ? I18n.t("ch", { 1: entry.lastReadChapterNum })
                                : I18n.t("state.notStarted")
                    }

                    onClicked: {
                        if (!entry) return
                        Manga.fetchMangaDetail(entry.id)
                        libraryView.mangaSelected(entry.id)
                    }
                }

                FolderCard {
                    visible: folderData !== null
                    anchors.fill: parent
                    covers: folderData ? folderData.covers : []
                    coversReady: Manga.serverReady
                    name: folderData ? folderData.name : ""
                    count: folderData ? folderData.count : 0
                    bodyFont: libraryView.fontBody
                    onClicked: {
                        if (folderData) libraryView.activeFolder = folderData.id
                    }
                }

                CreateFolderCard {
                    visible: item.kind === "create"
                    anchors.fill: parent
                    bodyFont: libraryView.fontBody
                    onClicked: libraryView._newFolder()
                }
            }
        }

        // ── List ───────────────────────────────────────────────────────────────
        ListView {
            id: libRows
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: Manga.libraryLoaded && libraryView.listMode
            topMargin: Style.spacing.xl
            bottomMargin: Style.spacing.xl
            leftMargin: Gutter.left
            rightMargin: Gutter.right
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: libraryView.model

            delegate: Item {
                readonly property var item: modelData
                readonly property var entry: item.kind === "title" ? item.entry : null
                readonly property var folderData: item.kind === "folder" ? item : null
                width: libRows.width - libRows.leftMargin - libRows.rightMargin
                height: Style.space(ListMetrics.ROW_HEIGHT_BASE)

                ListRow {
                    visible: entry !== null
                    anchors.fill: parent
                    inset: Gutter.ink
                    source: entry && Manga.serverReady ? (entry.coverUrl || "") : ""
                    title: entry ? (entry.title || "") : ""
                    bodyFont: libraryView.fontBody
                    meta: entry
                        ? MangaCard.metaLine(entry.chapter, I18n.tData(entry.status || ""),
                                             libraryView.cardTranslator) : ""
                    progress: entry && entry.lastReadChapterNum
                              ? I18n.t("ch", { 1: entry.lastReadChapterNum })
                              : I18n.t("state.notStarted")
                    progressActive: entry ? !!entry.lastReadChapterNum : false

                    onClicked: {
                        if (!entry) return
                        Manga.fetchMangaDetail(entry.id)
                        libraryView.mangaSelected(entry.id)
                    }
                }

                FolderListRow {
                    visible: folderData !== null
                    anchors.fill: parent
                    inset: Gutter.ink
                    covers: folderData ? folderData.covers : []
                    coversReady: Manga.serverReady
                    name: folderData ? folderData.name : ""
                    count: folderData ? folderData.count : 0
                    bodyFont: libraryView.fontBody
                    onClicked: {
                        if (folderData) libraryView.activeFolder = folderData.id
                    }
                }

                CreateFolderCard {
                    visible: item.kind === "create"
                    anchors.fill: parent
                    row: true
                    bodyFont: libraryView.fontBody
                    onClicked: libraryView._newFolder()
                }
            }
        }
    }

    FolderPrompt {
        id: folderPrompt
        anchors.fill: parent
        onAccepted: function(value) { libraryView._acceptPrompt(value) }
    }

    Connections {
        target: Privacy
        function onLockedChanged() {
            if (Privacy.locked && libraryView.activeFolderLockedOut)
                libraryView.activeFolder = ""
        }
    }

    Connections {
        target: Organizer
        function onDataChanged() { libraryView._pruneFolder() }
    }
}
