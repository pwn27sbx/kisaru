import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.app
import qs.Commons
import qs.services
import qs.components
import qs.Ui
import "../../../services/list_metrics.js" as ListMetrics
import "../../../services/scroll_metrics.js" as ScrollMetrics

Item {
    id: browseView

    readonly property string fontBody: Style.font.family

    // Each panel remembers its own layout (owner, round 6): anime and novel
    // stop sharing manga's choice.
    readonly property bool listMode: UiPrefs.viewModeFor("anime") === "list"

    // The tool bar's filter menu (owner §32). The same five entries the chips
    // had; one value stands for the (view, country) pair the old chips set in
    // two steps.
    readonly property var filterOptions: [
        { value: "popular", label: I18n.t("anime.filter.popular") },
        { value: "latest", label: I18n.t("anime.filter.latest") },
        { value: "JP", label: I18n.t("anime.filter.japan") },
        { value: "CN", label: I18n.t("anime.filter.china") },
        { value: "KR", label: I18n.t("anime.filter.korea") }
    ]
    readonly property string filterValue:
        Anime.currentView === "popular" ? "popular"
        : Anime.currentCountry === "JP" ? "JP"
        : Anime.currentCountry === "CN" ? "CN"
        : Anime.currentCountry === "KR" ? "KR" : "latest"
    // A search replaces the list the filter describes, so the menu steps back
    // instead of claiming a filter that is not in force.
    readonly property bool filterDimmed: Anime.currentView === "search"
    readonly property string filterFallbackLabel: I18n.t("anime.filter.latest")

    // The body of the old chip handler, unchanged.
    function chooseFilter(value) {
        browseView.searchCleared()
        Anime.currentCountry = value === "JP" ? "JP" : value === "CN" ? "CN" : value === "KR" ? "KR" : "ALL"
        if (value === "popular") Anime.fetchPopular(true)
        else Anime.fetchLatest(true)
    }

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

        // Row 3 is gone (owner §32): the filters live in the tool bar the panel
        // owns, and the layout toggle lives there too.

        // ── Content area ──────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Loading: ghost cards where the first page will land
            SkeletonGrid {
                anchors.fill: parent; z: 10
                anchors.leftMargin: Gutter.left
                anchors.rightMargin: Gutter.right
                active: !browseView.listMode && Anime.isFetchingAnime && Anime.animeList.length === 0
                columns: CardMetrics.columns
                padding: Style.space(0)
                cellHeight: CardMetrics.cellHeight(width / CardMetrics.columns)
            }

            // Rows take over the same area in list mode.
            SkeletonList {
                anchors.fill: parent
                anchors.leftMargin: Gutter.left
                anchors.rightMargin: Gutter.right
                z: 10
                rowHeight: Style.space(ListMetrics.ROW_HEIGHT_BASE)
                cover: true
                inset: Style.space(0)
                active: browseView.listMode && Anime.isFetchingAnime && Anime.animeList.length === 0
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
                visible: !browseView.listMode
                anchors.fill: parent
                anchors.topMargin: Style.spacing.xl
                anchors.bottomMargin: Style.spacing.xl
                // One gutter with the tool bar (owner §32.1).
                anchors.leftMargin: Gutter.left
                anchors.rightMargin: Gutter.right
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
                        cornerAccent: true
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

            // ── List ─────────────────────────────────────────────────────────
            // Same model and fetch contract as the grid; only the row shape
            // changes. Each panel keeps its own layout preference.
            ListView {
                id: animeRows
                anchors.fill: parent
                anchors.topMargin: Style.spacing.xl
                anchors.bottomMargin: Style.spacing.xl
                // One gutter with the tool bar (owner §32.1); the row's own
                // inset is gone, the box already is the gutter.
                anchors.leftMargin: Gutter.left
                anchors.rightMargin: Gutter.right
                visible: browseView.listMode
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: ScriptModel { values: Anime.animeList }

                ScrollBar.vertical: StyledScrollBar {
                }

                onContentYChanged: {
                    if (ListMetrics.shouldFetchMore(contentY, height, contentHeight))
                        Anime.fetchNextPage()
                }

                delegate: ListRow {
                    width: animeRows.width
                    height: implicitHeight
                    inset: Style.space(0)
                    source: modelData.thumbnail || ""
                    title: modelData.englishName || modelData.name || ""
                    bodyFont: browseView.fontBody
                    // The score goes in its own accent run, like the grid's
                    // chip; the meta keeps the format and the episode count.
                    score: {
                        var value = Number(modelData.score)
                        return (modelData.score !== null && modelData.score !== undefined
                                && isFinite(value)) ? "★ " + value.toFixed(1) : ""
                    }
                    meta: {
                        var parts = []
                        if (modelData.type) parts.push(I18n.tData(modelData.type))
                        var avail = modelData.availableEpisodes
                        if (avail) {
                            var n = Anime.currentMode === "dub" ? avail.dub : avail.sub
                            if (n > 0) parts.push(I18n.t("anime.epCount", { 1: n }))
                        }
                        return parts.join(" · ")
                    }

                    onClicked: browseView.animeSelected(modelData)
                }
            }
        }
    }
}
