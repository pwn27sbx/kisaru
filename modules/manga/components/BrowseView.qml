import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.app
import qs.Commons
import qs.services
import qs.components
import qs.Ui
import "../../../services/manga_card.js" as MangaCard
import "../../../services/list_metrics.js" as ListMetrics

Item {
    id: browseView

    // ── Exposed API ──────────────────────────────────────────────────────────
    readonly property string fontBody: Style.font.family

    // metaLine composes "chapter · status"; the wording lives in
    // manga_card.js, so both views share one adapter instead of copying it.
    readonly property var cardTranslator: MangaCard.translator(I18n.t)

    // One number for the grid and its skeleton: they must not disagree. Both
    // come from services/CardMetrics.qml now, the single source the six grids
    // share (owner, round 6).
    readonly property int columnCount: CardMetrics.columns

    // The card's box, from the constants in services/manga_card.js: the cover
    // ratio plus the info band under it. The GridView and the SkeletonGrid
    // that stands in for it both read these, so the ghosts sit exactly where
    // the covers land and the panel does not jump on load.
    readonly property real cardWidth:
        Math.max(0, (width - 2 * Style.spacing.xl) / columnCount)
    readonly property real cardHeight: CardMetrics.cellHeight(cardWidth)

    // The layout the user picked (persisted in settings.json). Both branches
    // below read this one value, so the toggle in the section header and the
    // model wiring can never disagree about which one is showing.
    readonly property bool listMode: UiPrefs.viewModeFor("manga") === "list"

    // Emitted when the user taps a manga card
    signal mangaSelected(string mangaId)

    property string currentTagId: ""

    // Emitted when an in-panel filter change invalidates the current search;
    // the panel clears its search bar in response.
    signal searchCleared()

    function resetList() {
        Manga.fetchByOrigin(currentTagId, true)
    }

    // One segment of the grid/list toggle: a square glyph chip that shows
    // whether its layout is the one on screen. The hover tooltip carries the
    // name, so the header stays compact.

    ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(0)

        // ── Row 3: filter chips + grid/list toggle ───────────────────────────
        // One row, as the owner drew it (round 4): the chips at the left and
        // scroll horizontally when they do not fit, the two-cell layout toggle
        // pinned at the right. The results heading that used to sit under it is
        // gone — its count now lives in the status bar.
        RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.sm

            FilterBar {
                Layout.fillWidth: true
                fontFamily: browseView.fontBody
                options: [
                    { label: I18n.t("manga.filter.hot") },
                    { label: I18n.t("manga.filter.latest") },
                    // Origin tags are data values, identical in both languages.
                    { label: "Manga" }, // i18n-ignore — origin tag
                    { label: "Manhwa" }, // i18n-ignore — origin tag
                    { label: "Manhua" } // i18n-ignore — origin tag
                ]
                currentIndex: {
                    if (browseView.currentTagId === "") return 0
                    if (browseView.currentTagId === "latest") return 1
                    if (browseView.currentTagId === "ja") return 2
                    if (browseView.currentTagId === "ko") return 3
                    if (browseView.currentTagId === "zh") return 4
                    return -1
                }
                onActivated: function(index) {
                    var tagId = ["", "latest", "ja", "ko", "zh"][index]
                    browseView.currentTagId = tagId
                    browseView.searchCleared()
                    Manga.fetchByOrigin(tagId, true)
                }
            }

            // Grid/list toggle, inside one segmented box: a faint surface with a
            // hairline and the theme radius around both cells. Its twin lives in
            // LibraryView.qml: the shared section header is a bare Text in
            // qs.Ui, and giving it children would reach into a component every
            // panel uses.
            ViewModeToggle {
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: Style.spacing.xl
                panel: "manga"
                listMode: browseView.listMode
                fontFamily: browseView.fontBody
            }
        }

        // ── Main content area ────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Loading state: ghost cards where the first page will land. The
            // cell width comes from SkeletonGrid's own padding, which matches
            // the grid's margins below; the cell HEIGHT is the card's real one
            // (browseView.cardHeight), so the rows do not shrink when the
            // covers arrive. In list mode the grid shape does not apply, so the
            // row skeleton takes over.
            SkeletonGrid {
                anchors.fill: parent
                z: 10
                active: !browseView.listMode && Manga.isFetchingManga && Manga.mangaList.length === 0
                columns: browseView.columnCount
                cellHeight: browseView.cardHeight
            }

            SkeletonList {
                anchors.fill: parent
                z: 10
                rowHeight: Style.space(ListMetrics.ROW_HEIGHT_BASE)
                dividerInset: Style.spacing.xl
                active: browseView.listMode && Manga.isFetchingManga && Manga.mangaList.length === 0
            }

            // More pages on the way
            LoadingBar {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                z: 11
                active: Manga.isFetchingManga && Manga.mangaList.length > 0
            }

            // Error state
            Rectangle {
                anchors.fill: parent
                color: Colors.background
                visible: Manga.mangaError.length > 0 && !Manga.isFetchingManga
                z: 9

                Column {
                    anchors.centerIn: parent
                    spacing: Style.spacing.xl
                    StyledText {
                        text: "⚠"
                        font.pixelSize: 32 // style-ignore — bespoke size
                        color: Colors.error
                        anchors.horizontalCenter: parent.horizontalCenter
                        opacity: 0.8
                    }
                    StyledText {
                        text: Manga.mangaError
                        color: Colors.on_surface_variant
                        font.pixelSize: Style.font.body
                        font.family: browseView.fontBody
                        wrapMode: Text.Wrap
                        width: 260
                        horizontalAlignment: Text.AlignHCenter
                        lineHeight: 1.4
                    }
                }
            }

            // ── Manga grid ───────────────────────────────────────────────────
            GridView {
                id: mangaGrid
                anchors.fill: parent
                anchors.margins: Style.spacing.xl
                visible: !browseView.listMode
                // `width` already excludes the margins above, so the three
                // columns share it whole (the old `(width - 10) / 4` left a
                // stray 10 px on the right). Both numbers come from
                // browseView.cardWidth / cardHeight, which the skeleton above
                // reads too.
                cellWidth: browseView.cardWidth
                cellHeight: browseView.cardHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                // A ScriptModel diffs each new array against the last, so appending a
                // page inserts rows instead of resetting the view (and its scroll).
                model: ScriptModel { values: Manga.mangaList }

                ScrollBar.vertical: StyledScrollBar {
                }

                onContentYChanged: {
                    if (contentY + height > contentHeight - cellHeight * 2)
                        Manga.fetchNextMangaPage()
                }

                delegate: Item {
                    width: mangaGrid.cellWidth
                    height: mangaGrid.cellHeight

                    CoverCard {
                        anchors.fill: parent
                        source: modelData.thumbUrl || ""
                        title: modelData.title || ""
                        bodyFont: browseView.fontBody
                        // The work's format, leading corner. The tint comes
                        // from the type DATA, not from the badge text: tData()
                        // may localize it and the casing is a display choice.
                        typeBadge: I18n.tData(modelData.type || "").toUpperCase()
                        // The badge tint comes from the type DATA, not from the
                        // badge text above: tData() may localize it and the
                        // casing is a display choice. Manhwa/manhua are the
                        // long-form formats Stitch tints with the accent.
                        badgeTone: {
                            const type = String(modelData.type || "").toLowerCase()
                            return (type === "manhwa" || type === "manhua") ? "accent" : ""
                        }
                        // The work's chapter · state, split into the row Stitch
                        // draws. metaLine with an empty status gives just the
                        // chapter ("Cap. 179"), so an absent chapter leaves the
                        // left slot empty instead of a bare "Cap.".
                        metaChapter: MangaCard.metaLine(modelData.chapter, "",
                                                        browseView.cardTranslator)
                        metaStatus: I18n.tData(modelData.status || "")
                        metaTone: MangaCard.statusTone(modelData.status || "")

                        onClicked: {
                            Manga.fetchMangaDetail(modelData.id)
                            browseView.mangaSelected(modelData.id)
                        }
                    }
                }
            }

            // ── Manga list ───────────────────────────────────────────────────
            // Same model and same fetch contract as the grid; only the row
            // shape changes. A ScriptModel is kept so appending a page inserts
            // rows instead of resetting the view (and its scroll).
            ListView {
                id: mangaRows
                anchors.fill: parent
                anchors.topMargin: Style.spacing.xl
                anchors.bottomMargin: Style.spacing.xl
                visible: browseView.listMode
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: ScriptModel { values: Manga.mangaList }

                ScrollBar.vertical: StyledScrollBar {
                }

                onContentYChanged: {
                    if (ListMetrics.shouldFetchMore(contentY, height, contentHeight))
                        Manga.fetchNextMangaPage()
                }

                delegate: ListRow {
                    width: mangaRows.width
                    height: implicitHeight
                    source: modelData.thumbUrl || ""
                    title: modelData.title || ""
                    bodyFont: browseView.fontBody
                    meta: MangaCard.metaLine(modelData.chapter,
                                             I18n.tData(modelData.status || ""),
                                             browseView.cardTranslator)

                    onClicked: {
                        Manga.fetchMangaDetail(modelData.id)
                        browseView.mangaSelected(modelData.id)
                    }
                }
            }
        }
    }
}
