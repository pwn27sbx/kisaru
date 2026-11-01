import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.app
import qs.Commons
import qs.services
import qs.components
import qs.Ui

Item {
    id: browseView

    readonly property string fontBody: Style.font.family

    // Passes the full show object so DetailView can seed itself immediately
    signal animeSelected(var show)

    // Emitted when an in-panel filter change invalidates the current search;
    // the panel clears its search bar in response.
    signal searchCleared()

    function resetList() {
        Anime.fetchPopular(true)
    }

    // ── Background ────────────────────────────────────────────────────────────
    Rectangle { anchors.fill: parent; color: Colors.background }

    ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(0)

        // ── Filter bar (tinted chips, scroll-x) ───────────────────────────────
        FilterBar {
            Layout.fillWidth: true
            fontFamily: browseView.fontBody
            options: [
                { label: I18n.t("anime.filter.popular") },
                { label: I18n.t("anime.filter.latest") },
                { label: I18n.t("anime.filter.japan") },
                { label: I18n.t("anime.filter.china") },
                { label: I18n.t("anime.filter.korea") }
            ]
            currentIndex: {
                if (Anime.currentView === "popular") return 0
                if (Anime.currentCountry === "JP") return 2
                if (Anime.currentCountry === "CN") return 3
                if (Anime.currentCountry === "KR") return 4
                return 1
            }
            onActivated: function(index) {
                browseView.searchCleared()
                Anime.currentCountry = index === 2 ? "JP" : index === 3 ? "CN" : index === 4 ? "KR" : "ALL"
                if (index === 0) Anime.fetchPopular(true)
                else Anime.fetchLatest(true)
            }
        }

        // ── Content area ──────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Loading: ghost cards where the first page will land
            SkeletonGrid {
                anchors.fill: parent; z: 10
                active: Anime.isFetchingAnime && Anime.animeList.length === 0
                columns: CardMetrics.columns
                padding: Style.spacing.xl
                cellHeight: CardMetrics.cellHeight((width - 2 * Style.spacing.xl) / CardMetrics.columns)
            }

            // More pages on the way
            LoadingBar {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                z: 11
                active: Anime.isFetchingAnime && Anime.animeList.length > 0
            }

            // Error
            Rectangle {
                anchors.fill: parent; color: Colors.background
                visible: Anime.animeError.length > 0 && !Anime.isFetchingAnime
                z: 9

                Column {
                    anchors.centerIn: parent; spacing: Style.spacing.xl

                    Text {
                        text: "⚠"; font.pixelSize: 30; color: Colors.error // style-ignore — bespoke size
                        anchors.horizontalCenter: parent.horizontalCenter; opacity: 0.8
                    }
                    StyledText {
                        text: Anime.animeError
                        color: Colors.on_surface_variant; font.pixelSize: Style.font.body
                        font.family: browseView.fontBody
                        wrapMode: Text.Wrap; width: 260
                        horizontalAlignment: Text.AlignHCenter; lineHeight: 1.4
                    }
                }
            }

            // Grid
            GridView {
                id: animeGrid
                anchors.fill: parent; anchors.margins: Style.spacing.xl
                cellWidth: Math.floor(width / CardMetrics.columns)
                cellHeight: CardMetrics.cellHeight(cellWidth)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                // A ScriptModel diffs each new array against the last, so appending a
                // page inserts rows instead of resetting the view (and its scroll).
                model: ScriptModel { values: Anime.animeList }

                ScrollBar.vertical: StyledScrollBar {
                }

                onContentYChanged: {
                    if (contentY + height > contentHeight - cellHeight * 2)
                        Anime.fetchNextPage()
                }

                delegate: Item {
                    width: animeGrid.cellWidth
                    height: animeGrid.cellHeight

                    CoverCard {
                        anchors.fill: parent
                        source: modelData.thumbnail || ""
                        title: modelData.englishName || modelData.name || ""
                        bodyFont: browseView.fontBody
                        typeBadge: modelData.type
                            ? I18n.tData(modelData.type).toUpperCase() : ""
                        // The score lives in the trailing corner, where the
                        // state sits on the other cards.
                        cornerText: modelData.score !== null && modelData.score !== undefined
                            ? "★ " + Number(modelData.score || 0).toFixed(1) : ""
                        // What the source actually has, in the user's mode.
                        episodesText: {
                            var avail = modelData.availableEpisodes
                            if (!avail) return ""
                            var n = Anime.currentMode === "dub" ? avail.dub : avail.sub
                            return n > 0 ? I18n.t("anime.epCount", { 1: n }) : ""
                        }
                        bookmarked: Anime.isInLibrary(modelData.id)

                        onClicked: browseView.animeSelected(modelData)
                    }
                }
            }
        }
    }
}
