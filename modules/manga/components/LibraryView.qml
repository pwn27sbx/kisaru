import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.app
import qs.Commons
import qs.services
import qs.components
import qs.Ui
import "../../../services/manga_card.js" as MangaCard
import "../../../services/list_metrics.js" as ListMetrics

Item {
    id: libraryView

    readonly property string fontDisplay: Style.font.family
    readonly property string fontBody:    Style.font.family

    // metaLine composes "chapter · status"; the wording lives in
    // manga_card.js, so both views share one adapter instead of copying it.
    readonly property var cardTranslator: MangaCard.translator(I18n.t)

    // One number for the grid and its skeleton: they must not disagree.
    readonly property int columnCount: 3

    // The layout the user picked (persisted in settings.json), shared with
    // Browse through UiPrefs: switching it in one view switches it in both.
    readonly property bool listMode: UiPrefs.viewMode === "list"

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

        // ── Grid/list toggle, alone on its row ───────────────────────────────
        // The heading ("Library" plus its exact count) is gone: the tab already
        // names the section and the count moved to the status bar (owner, round
        // 4), so this row keeps the same shape as Browse's — the layout control
        // pinned at the right, nothing else.
        RowLayout {
            Layout.fillWidth: true
            Layout.rightMargin: Style.spacing.xl
            spacing: Style.spacing.sm

            // The stretch holds the toggle against the right edge, exactly
            // where Browse's filter row puts it.
            Item { Layout.fillWidth: true }

            // Grid/list toggle, inside one segmented box — the same surface,
            // hairline and radius as Browse's, so the two rows read as one
            // panel. Its twin lives in BrowseView.qml: the shared section
            // header is a bare Text in qs.Ui, and giving it children would
            // reach into a component every panel uses.
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                // Implicit (not width/height): a RowLayout sizes a child from
                // its implicitWidth, and an explicit width would be overridden
                // to zero.
                implicitWidth: cellsRow.implicitWidth + 2 * Style.spacing.xxs
                implicitHeight: cellsRow.implicitHeight + 2 * Style.spacing.xxs
                radius: Style.cornerRadius
                color: Colors.surface_container
                border.width: Style.spacing.hairline
                border.color: Colors.outline_variant

                Row {
                    id: cellsRow
                    x: Style.spacing.xxs
                    y: Style.spacing.xxs
                    spacing: Style.spacing.xxs

                    ViewModeChip {
                        glyph: "▦"
                        label: I18n.t("view.grid")
                        current: !libraryView.listMode
                        bodyFont: libraryView.fontBody
                        cellSize: Style.space(22)
                        onClicked: UiPrefs.setViewMode("grid")
                    }

                    ViewModeChip {
                        glyph: "☰"
                        label: I18n.t("view.list")
                        current: libraryView.listMode
                        bodyFont: libraryView.fontBody
                        cellSize: Style.space(22)
                        onClicked: UiPrefs.setViewMode("list")
                    }
                }
            }
        }

        // ── Empty state ───────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: Manga.libraryList.length === 0 && Manga.libraryLoaded

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
            visible: !Manga.libraryLoaded && !libraryView.listMode
            active: !Manga.libraryLoaded && !libraryView.listMode
            // Same columns and the same cell box as the grid below, from the
            // one source the six grids share.
            columns: CardMetrics.columns
            padding: Style.spacing.lg
            cellHeight: CardMetrics.cellHeight((width - 2 * Style.spacing.lg) / CardMetrics.columns, Style.space(30))
            footerHeight: 30
        }

        // The grid's ghost cards do not apply to a list of rows.
        SkeletonList {
            Layout.fillWidth: true
            Layout.fillHeight: true
            rowHeight: Style.space(ListMetrics.ROW_HEIGHT_BASE)
            dividerInset: Style.spacing.lg
            active: !Manga.libraryLoaded && libraryView.listMode
        }

        GridView {
            id: libGrid
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: Manga.libraryList.length > 0 && !libraryView.listMode
            topMargin: Style.spacing.xl
            leftMargin: Style.spacing.lg
            rightMargin: Style.spacing.lg
            bottomMargin: Style.spacing.xl
            cellWidth: Math.floor((width - leftMargin - rightMargin) / CardMetrics.columns)
            cellHeight: CardMetrics.cellHeight(cellWidth, Style.space(30))
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: Manga.libraryList

            ScrollBar.vertical: StyledScrollBar {
            }

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
            visible: Manga.libraryList.length > 0 && libraryView.listMode
            topMargin: Style.spacing.xl
            bottomMargin: Style.spacing.xl
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: Manga.libraryList

            ScrollBar.vertical: StyledScrollBar {
            }

            delegate: ListRow {
                width: libRows.width
                height: implicitHeight
                // The library grid and its header use `lg`; the rows follow.
                inset: Style.spacing.lg

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
}
