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
import "../../../services/manga_card.js" as MangaCard

Item {
    id: browseView

    readonly property string fontBody: Style.font.family

    // Each panel remembers its own layout (owner, round 6): anime and novel
    // stop sharing manga's choice.
    readonly property bool listMode: UiPrefs.viewModeFor("novel") === "list"

    signal novelSelected(string novelId)

    property string currentFilter: "hot"

    // Emitted when an in-panel filter change invalidates the current search;
    // the panel clears its search bar in response.
    signal searchCleared()

    function resetList() {
        currentFilter = "hot"
        Novel.fetchHot()
    }

    // The tool bar's filter menu (owner §32): same two entries, same call.
    readonly property var filterOptions: [
        { value: "hot", label: I18n.t("novel.filter.hot") },
        { value: "latest", label: I18n.t("novel.filter.latest") }
    ]
    readonly property string filterValue: browseView.currentFilter
    // A search puts the list in "search": the menu dims and keeps naming the
    // last real filter instead of pretending the filter is in force.
    readonly property bool filterDimmed: browseView.currentFilter === "search"
    readonly property string filterFallbackLabel: I18n.t("novel.filter.hot")

    function chooseFilter(value) {
        browseView._switchFilter(value)
    }

    function _switchFilter(f) {
        if (currentFilter === f) return
        currentFilter = f
        browseView.searchCleared()
        Novel.clearNovelList()
        if (f === "hot") Novel.fetchHot()
        else             Novel.fetchLatest(true)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(0)

        // Row 3 is gone (owner §32): the filters live in the tool bar the panel
        // owns, with the layout toggle. This view starts at the covers.

        Item {
            Layout.fillWidth: true; Layout.fillHeight: true

            // Loading overlay: ghost cards where the first page will land
            SkeletonGrid {
                anchors.fill: parent; z: 10
                anchors.leftMargin: Gutter.left
                anchors.rightMargin: Gutter.right
                active: (Novel.isFetchingNovel || Novel.isSwitchingProvider)
                    && Novel.novelList.length === 0
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
                active: browseView.listMode && Novel.isFetchingNovel && Novel.novelList.length === 0
            }

            // More pages on the way
            LoadingBar {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                z: 11
                active: Novel.isFetchingNovel && Novel.novelList.length > 0
            }

            // Error overlay
            Rectangle {
                anchors.fill: parent; color: Colors.background; z: 9
                visible: Novel.novelError.length > 0 && !Novel.isFetchingNovel

                Column {
                    anchors.centerIn: parent; spacing: Style.spacing.xl
                    Text { text: "⚠"; font.pixelSize: 32; color: Colors.error; anchors.horizontalCenter: parent.horizontalCenter; opacity: 0.8 } // style-ignore — bespoke size
                    Text {
                        text: Novel.novelError; color: Colors.on_surface_variant
                        font.pixelSize: Style.font.body; font.family: browseView.fontBody
                        wrapMode: Text.Wrap; width: 260; horizontalAlignment: Text.AlignHCenter; lineHeight: 1.4
                    }
                }
            }

            GridView {
                id: novelGrid
                visible: !browseView.listMode
                anchors.fill: parent
                anchors.topMargin: Style.spacing.xl
                anchors.bottomMargin: Style.spacing.xl
                // One gutter with the tool bar (owner §32.1).
                anchors.leftMargin: Gutter.left
                anchors.rightMargin: Gutter.right
                cellWidth: Math.floor(width / CardMetrics.columns)
                cellHeight: CardMetrics.cellHeight(cellWidth)
                clip: true; boundsBehavior: Flickable.StopAtBounds
                // A ScriptModel diffs each new array against the last, so appending a
                // page inserts rows instead of resetting the view (and its scroll).
                model: ScriptModel { values: Novel.novelList }

                // The shared bar, like every other view: this grid had its own
                // copy and could not follow the lane or the auto-hide.
                ScrollBar.vertical: StyledScrollBar {
                }

                onContentYChanged: {
                    if (contentY + height > contentHeight - cellHeight * 2)
                        Novel.fetchNextPage()
                }

                delegate: Item {
                    width: novelGrid.cellWidth; height: novelGrid.cellHeight

                    CoverCard {
                        anchors.fill: parent
                        source: modelData.coverUrl || ""
                        title: modelData.title || ""
                        author: modelData.author || ""
                        bodyFont: browseView.fontBody
                        // The novel's state, trailing corner, with the same
                        // tones the manga cards use for the same words.
                        cornerText: modelData.status
                            ? I18n.tData(modelData.status).toUpperCase() : ""
                        cornerTone: MangaCard.statusTone(modelData.status || "")

                        onClicked: {
                            Novel.fetchNovelDetail(modelData.id)
                            browseView.novelSelected(modelData.id)
                        }
                    }
                }
            }

            // ── List ─────────────────────────────────────────────────────────
            // Same model as the grid; the row keeps the author where the card
            // keeps it.
            ListView {
                id: novelRows
                anchors.fill: parent
                anchors.topMargin: Style.spacing.xl
                anchors.bottomMargin: Style.spacing.xl
                // One gutter with the tool bar (owner §32.1).
                anchors.leftMargin: Gutter.left
                anchors.rightMargin: Gutter.right
                visible: browseView.listMode
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: ScriptModel { values: Novel.novelList }

                ScrollBar.vertical: StyledScrollBar {
                }

                onContentYChanged: {
                    if (ListMetrics.shouldFetchMore(contentY, height, contentHeight))
                        Novel.fetchNextPage()
                }

                delegate: ListRow {
                    width: novelRows.width
                    height: implicitHeight
                    inset: Style.space(0)
                    source: modelData.coverUrl || ""
                    title: modelData.title || ""
                    bodyFont: browseView.fontBody
                    meta: modelData.author || ""

                    onClicked: {
                        Novel.fetchNovelDetail(modelData.id)
                        browseView.novelSelected(modelData.id)
                    }
                }
            }
        }
    }
}
