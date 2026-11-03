import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.app
import qs.Commons
import qs.services
import qs.components
import "../../../services/library_filter.js" as LibraryFilter
import "../../../services/list_metrics.js" as ListMetrics
import "../../../services/scroll_metrics.js" as ScrollMetrics

Item {
    id: libraryView

    // Owner §33.1: in Library the header's search filters the saved titles
    // locally, by title, as the text arrives (no debounce, no network). Esc or
    // clearing the field shows the whole shelf again.
    property string query: ""
    readonly property var shownList: LibraryFilter.filter(Anime.libraryList, query)

    readonly property string fontDisplay: Style.font.family
    readonly property string fontBody:    Style.font.family

    // Each panel remembers its own layout (owner, round 6).
    readonly property bool listMode: UiPrefs.viewModeFor("anime") === "list"

    signal animeSelected(var show)

    Rectangle { anchors.fill: parent; color: Colors.background }

    ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(0)

        // The heading row (title plus entry-count badge) is gone: the tab
        // names the section and the count lives in the status bar now, exactly
        // like the manga library after round 4 (owner, round 6).

        // Row 3 is gone (owner §32): the layout toggle lives in the tool bar the
        // panel owns, next to the search. This view starts at the content.

        // ── Empty state ───────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: Anime.libraryList.length === 0 && Anime.libraryLoaded

            EmptyState {
                title: I18n.t("empty.library")
                subtitle: I18n.t("anime.library.hint")
                displayFont: libraryView.fontDisplay
                bodyFont: libraryView.fontBody
            }
        }

        // ── Loading ───────────────────────────────────────────────────────────
        SkeletonGrid {
            Layout.fillWidth: true; Layout.fillHeight: true
            // The ghost stops where the cards stop: the lane is not for it.
            Layout.leftMargin: Gutter.left
            Layout.rightMargin: Gutter.right
            visible: !libraryView.listMode && !Anime.libraryLoaded
            active: !libraryView.listMode && !Anime.libraryLoaded
            padding: Style.space(0)
            cellHeight: CardMetrics.cellHeight(width / CardMetrics.columns, Style.space(28))
            footerHeight: 28
        }

        // ── Library grid ──────────────────────────────────────────────────────
        SkeletonList {
            Layout.fillWidth: true; Layout.fillHeight: true
            Layout.leftMargin: Gutter.left
            Layout.rightMargin: Gutter.right
            visible: libraryView.listMode && !Anime.libraryLoaded
            active: libraryView.listMode && !Anime.libraryLoaded
            rowHeight: Style.space(ListMetrics.ROW_HEIGHT_BASE)
            cover: true
            inset: Gutter.ink
        }

        GridView {
            id: libGrid
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: !libraryView.listMode && Anime.libraryList.length > 0
            topMargin: Style.spacing.xl; leftMargin: Gutter.left; bottomMargin: Style.spacing.xl
            // The bar's lane goes on top of the grid's own inset (owner §30).
            rightMargin: Gutter.right
            // No floor: the columns share the width exactly, so the last card
            // ends on the panel's right ink line (owner, 2026-11-02).
            cellWidth: (width - leftMargin - rightMargin) / CardMetrics.columns
            cellHeight: CardMetrics.cellHeight(cellWidth, Style.space(28))
            clip: true; boundsBehavior: Flickable.StopAtBounds
            model: libraryView.shownList


            delegate: Item {
                width: libGrid.cellWidth
                height: libGrid.cellHeight

                readonly property var entry: modelData

                CoverCard {
                    anchors.fill: parent
                    source: entry.thumbnail || ""
                    title: entry.englishName || entry.name || ""
                    bodyFont: libraryView.fontBody
                    footerHeight: 28
                    // The slots the anime panel needs, from data it already has.
                    cornerText: entry.score !== null && entry.score !== undefined
                        ? "★ " + Number(entry.score || 0).toFixed(1) : ""
                    cornerAccent: true
                    bookmarked: !!entry.bookmarked

                    CoverProgressBar {
                        height: 28
                        rowSpacing: Style.space(5)
                        bodyFont: libraryView.fontBody
                        started: entry.lastWatchedEpNum
                        label: entry.lastWatchedEpNum
                            ? I18n.t("ep", { 1: entry.lastWatchedEpNum })
                            : I18n.t("state.notStarted")
                    }

                    onClicked: {
                        // Reconstruct a minimal show object for fetchAnimeDetail
                        libraryView.animeSelected({
                            id:          entry.id,
                            name:        entry.name,
                            englishName: entry.englishName,
                            nativeName:  entry.nativeName  || "",
                            thumbnail:   entry.thumbnail,
                            score:       entry.score,
                            type:        entry.type        || "",
                            episodeCount: entry.episodeCount || "",
                            availableEpisodes: entry.availableEpisodes || { sub: 0, dub: 0, raw: 0 },
                            season:      entry.season      || null
                        })
                    }
                }
            }

        }

        // ── List ─────────────────────────────────────────────────────────────
        ListView {
            id: libRows
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: Anime.libraryList.length > 0 && libraryView.listMode
            topMargin: Style.spacing.xl
            bottomMargin: Style.spacing.xl
            // One gutter with the tool bar (owner §32.1).
            leftMargin: Gutter.left
            rightMargin: Gutter.right
            clip: true; boundsBehavior: Flickable.StopAtBounds
            model: libraryView.shownList


            delegate: ListRow {
                readonly property var entry: modelData

                // The list's margins are not part of a delegate's width.
                width: libRows.width - libRows.leftMargin - libRows.rightMargin
                height: implicitHeight
                source: entry.thumbnail || ""
                title: entry.englishName || entry.name || ""
                bodyFont: libraryView.fontBody
                inset: Gutter.ink
                score: {
                    var value = Number(entry.score)
                    return (entry.score !== null && entry.score !== undefined
                            && isFinite(value)) ? "★ " + value.toFixed(1) : ""
                }
                meta: ""
                progress: entry.lastWatchedEpNum ? I18n.t("ep", { 1: entry.lastWatchedEpNum }) : I18n.t("state.notStarted")
                progressActive: !!entry.lastWatchedEpNum

                onClicked: {
                    // Reconstruct a minimal show object for fetchAnimeDetail
                    libraryView.animeSelected({
                        id:          entry.id,
                        name:        entry.name,
                        englishName: entry.englishName,
                        nativeName:  entry.nativeName  || "",
                        thumbnail:   entry.thumbnail,
                        score:       entry.score,
                        type:        entry.type        || "",
                        episodeCount: entry.episodeCount || "",
                        availableEpisodes: entry.availableEpisodes || { sub: 0, dub: 0, raw: 0 },
                        season:      entry.season      || null
                    })
                }
            }
        }
    }
}
