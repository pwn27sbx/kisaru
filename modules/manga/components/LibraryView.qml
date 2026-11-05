import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.app
import qs.Commons
import qs.services
import qs.components
import "../../../services/library_filter.js" as LibraryFilter
import "../../../services/library_view.js" as LibraryViewJs
import qs.Ui
import "../../../services/manga_card.js" as MangaCard
import "../../../services/list_metrics.js" as ListMetrics
import "../../../services/scroll_metrics.js" as ScrollMetrics

Item {
    id: libraryView

    // Owner §33.1: in Library the header's search filters the saved titles
    // locally, by title, as the text arrives (no debounce, no network). Esc or
    // clearing the field shows the whole shelf again.
    property string query: ""

    // Folders and private mode: display reads the visible list, never the raw
    // one. `activeFolder` is "" for Todas.
    property string activeFolder: ""
    readonly property var visibleList: Manga.visibleEntries(libraryView.activeFolder)
    readonly property var shownList: LibraryFilter.filter(visibleList, query)
    readonly property string activeFolderName:
        activeFolder === "" ? "" : ((Organizer.folder("manga", activeFolder) || {}).name || "")

    // The panel answers by putting the search field away.
    signal secretEntered()

    // Unlock hook (amendment 11): onQueryChanged, never onSearchEdited.
    onQueryChanged: {
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
        folderPrompt.openText(I18n.t("folder.new"), "")
    }

    function _renameFolder(folderId) {
        var folder = Organizer.folder("manga", folderId)
        _promptAction = "rename"
        _promptFolder = folderId
        folderPrompt.openText(I18n.t("folder.rename"), folder ? folder.name : "")
    }

    function _confirmDelete(folderId) {
        var folder = Organizer.folder("manga", folderId)
        if (!folder) return
        _promptAction = "delete"
        _promptFolder = folderId
        folderPrompt.openConfirm(I18n.t("folder.delete"),
            folder.hidden ? I18n.t("folder.deleteHidden") : I18n.t("folder.deleteMessage"))
    }

    function _pruneFolder() {
        if (activeFolder !== "" && Organizer.folder("manga", activeFolder) === null)
            activeFolder = ""
    }

    readonly property string fontDisplay: Style.font.family
    readonly property string fontBody:    Style.font.family

    // metaLine composes "chapter · status"; the wording lives in
    // manga_card.js, so both views share one adapter instead of copying it.
    readonly property var cardTranslator: MangaCard.translator(I18n.t)

    // One number for the grid and its skeleton: they must not disagree.
    readonly property int columnCount: 3

    // The layout the user picked (persisted in settings.json), shared with
    // Browse through UiPrefs: switching it in one view switches it in both.
    readonly property bool listMode: UiPrefs.viewModeFor("manga") === "list"

    // Emitted when the user taps an entry — parent handles navigation
    signal mangaSelected(string mangaId)

    // One segment of the grid/list toggle: a square glyph chip that shows
    // whether its layout is the one on screen. The hover tooltip carries the
    // name, so the header stays compact.

    // ── Background ────────────────────────────────────────────────────────────
    Rectangle { anchors.fill: parent; color: Colors.background }

    ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(0)

        // Row 3 is gone (owner §32): the layout toggle lives in the tool bar
        // the panel owns. This view starts at the shelf.

        FolderRow {
            Layout.fillWidth: true
            kind: "manga"
            activeFolder: libraryView.activeFolder
            onFolderSelected: function(folderId) { libraryView.activeFolder = folderId }
            onCreateRequested: libraryView._newFolder()
            onRenameRequested: function(folderId) { libraryView._renameFolder(folderId) }
            onHideRequested: function(folderId, hidden) { Organizer.setHidden("manga", folderId, hidden) }
            onDeleteRequested: function(folderId) { libraryView._confirmDelete(folderId) }
            onLockRequested: Privacy.lock()
        }

        // ── Empty state ───────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: libraryView.visibleList.length === 0 && Manga.libraryLoaded

            EmptyState {
                title: I18n.t("empty.library")
                subtitle: I18n.t("manga.library.hint")
                displayFont: libraryView.fontDisplay
                bodyFont: libraryView.fontBody
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
            // Same columns and the same cell box as the grid below, from the
            // one source the six grids share.
            columns: CardMetrics.columns
            padding: Style.space(0)
            cellHeight: CardMetrics.cellHeight(width / CardMetrics.columns, Style.space(30))
            footerHeight: 30
        }

        // The grid's ghost cards do not apply to a list of rows.
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
            visible: libraryView.visibleList.length > 0 && !libraryView.listMode
            topMargin: Style.spacing.xl
            // One gutter with the tool bar (owner §32.1).
            leftMargin: Gutter.left
            rightMargin: Gutter.right
            bottomMargin: Style.spacing.xl
            // No floor: the columns share the width exactly, so the last card
            // ends on the panel's right ink line (owner, 2026-11-02).
            cellWidth: (width - leftMargin - rightMargin) / CardMetrics.columns
            cellHeight: CardMetrics.cellHeight(cellWidth, Style.space(30))
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: libraryView.shownList


            delegate: Item {
                width: libGrid.cellWidth
                height: libGrid.cellHeight

                readonly property var libEntry: modelData

                CoverCard {
                    anchors.fill: parent
                    // Covers go through the local backend; requesting them
                    // before it is ready fails and Qt keeps that failure for
                    // the session, so wait for the health check.
                    source: Manga.serverReady ? (libEntry.coverUrl || "") : ""
                    title: libEntry.title || ""
                    bodyFont: libraryView.fontBody
                    footerHeight: 30
                    // The work's own chapter and state, NOT this reader's
                    // progress: the progress bar below keeps "Cap. N" for the
                    // user. Today's entries store no work metadata, so the row
                    // stays hidden rather than inventing it; an entry that
                    // carries either field shows it here.
                    metaChapter: MangaCard.metaLine(libEntry.chapter, "",
                                                    libraryView.cardTranslator)
                    metaStatus: I18n.tData(libEntry.status || "")
                    metaTone: MangaCard.statusTone(libEntry.status || "")

                    CoverProgressBar {
                        height: 30
                        rowSpacing: Style.spacing.md
                        bodyFont: libraryView.fontBody
                        started: libEntry.lastReadChapterNum
                        label: libEntry.lastReadChapterNum
                                ? I18n.t("ch", { 1: libEntry.lastReadChapterNum })
                                : I18n.t("state.notStarted")
                    }

                    onClicked: {
                        Manga.fetchMangaDetail(libEntry.id)
                        libraryView.mangaSelected(libEntry.id)
                    }
                }
            }
        }

        // ── List ───────────────────────────────────────────────────────────────
        // Same entries, same click path; the reader's progress that the grid
        // pins to the card's footer becomes the row's trailing label.
        ListView {
            id: libRows
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: libraryView.visibleList.length > 0 && libraryView.listMode
            topMargin: Style.spacing.xl
            bottomMargin: Style.spacing.xl
            // One gutter with the top zone, lane included (owner §32.1).
            leftMargin: Gutter.left
            rightMargin: Gutter.right
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: libraryView.shownList


            delegate: ListRow {
                width: libRows.width - libRows.leftMargin - libRows.rightMargin
                height: implicitHeight
                inset: Gutter.ink
                // The rows' box is already the gutter's; no inner padding.

                readonly property var libEntry: modelData

                // Same gate as the grid: the local backend must be up before
                // any cover URL is requested.
                source: Manga.serverReady ? (libEntry.coverUrl || "") : ""
                title: libEntry.title || ""
                bodyFont: libraryView.fontBody
                meta: MangaCard.metaLine(libEntry.chapter,
                                         I18n.tData(libEntry.status || ""),
                                         libraryView.cardTranslator)
                progress: libEntry.lastReadChapterNum
                          ? I18n.t("ch", { 1: libEntry.lastReadChapterNum })
                          : I18n.t("state.notStarted")
                progressActive: !!libEntry.lastReadChapterNum

                onClicked: {
                    Manga.fetchMangaDetail(libEntry.id)
                    libraryView.mangaSelected(libEntry.id)
                }
            }
        }
    }

    FolderPrompt {
        id: folderPrompt
        anchors.fill: parent
        onAccepted: function(value) {
            if (libraryView._promptAction === "create")
                Organizer.addFolder("manga", value)
            else if (libraryView._promptAction === "rename")
                Organizer.renameFolder("manga", libraryView._promptFolder, value)
            else if (libraryView._promptAction === "delete")
                Manga.deleteFolder(libraryView._promptFolder)
            libraryView._promptAction = ""
            libraryView._promptFolder = ""
        }
    }

    Connections {
        target: Privacy
        function onLockedChanged() {
            if (Privacy.locked) libraryView.activeFolder = ""
        }
    }

    Connections {
        target: Organizer
        function onDataChanged() { libraryView._pruneFolder() }
    }
}
