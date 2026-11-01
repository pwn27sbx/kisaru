import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.app
import qs.Commons
import qs.services
import qs.components
import "../../../services/list_metrics.js" as ListMetrics

Item {
    id: libraryView

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

        // ── Grid/list toggle, alone on its row ───────────────────────────────
        // The same segmented box the other two panels use; each panel keeps its
        // own layout preference (owner, round 6).
        RowLayout {
            Layout.fillWidth: true
            Layout.rightMargin: Style.spacing.xl
            spacing: Style.spacing.sm

            Item { Layout.fillWidth: true }

            ViewModeToggle {
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: Style.spacing.xl
                panel: "anime"
                listMode: libraryView.listMode
                fontFamily: libraryView.fontBody
            }
        }

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
            visible: !libraryView.listMode && !Anime.libraryLoaded
            active: !libraryView.listMode && !Anime.libraryLoaded
            padding: Style.spacing.lg
            cellHeight: CardMetrics.cellHeight((width - 2 * Style.spacing.lg) / CardMetrics.columns, Style.space(28))
            footerHeight: 28
        }

        // ── Library grid ──────────────────────────────────────────────────────
        SkeletonList {
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: libraryView.listMode && !Anime.libraryLoaded
            active: libraryView.listMode && !Anime.libraryLoaded
            rowHeight: Style.space(ListMetrics.ROW_HEIGHT_BASE)
            cover: true
            inset: Style.spacing.lg
            dividerInset: Style.spacing.lg
        }

        GridView {
            id: libGrid
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: !libraryView.listMode && Anime.libraryList.length > 0
            topMargin: Style.spacing.xl; leftMargin: Style.spacing.lg; rightMargin: Style.spacing.lg; bottomMargin: Style.spacing.xl
            cellWidth: Math.floor((width - leftMargin - rightMargin) / CardMetrics.columns)
            cellHeight: CardMetrics.cellHeight(cellWidth, Style.space(28))
            clip: true; boundsBehavior: Flickable.StopAtBounds
            model: Anime.libraryList

            ScrollBar.vertical: StyledScrollBar {
            }

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
            clip: true; boundsBehavior: Flickable.StopAtBounds
            model: Anime.libraryList

            ScrollBar.vertical: StyledScrollBar {
            }

            delegate: ListRow {
                readonly property var entry: modelData

                width: libRows.width
                height: implicitHeight
                source: entry.thumbnail || ""
                title: entry.englishName || entry.name || ""
                bodyFont: libraryView.fontBody
                inset: Style.spacing.lg
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
