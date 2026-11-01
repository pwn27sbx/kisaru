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

Item {
    id: browseView

    readonly property string fontBody: Style.font.family

    signal novelSelected(string novelId)

    property string currentFilter: "hot"

    // Emitted when an in-panel filter change invalidates the current search;
    // the panel clears its search bar in response.
    signal searchCleared()

    function resetList() {
        currentFilter = "hot"
        Novel.fetchHot()
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

        // ── Filter bar (tinted chips, scroll-x) ───────────────────────────────
        FilterBar {
            Layout.fillWidth: true
            fontFamily: browseView.fontBody
            options: [
                { label: I18n.t("novel.filter.hot") },
                { label: I18n.t("novel.filter.latest") }
            ]
            currentIndex: browseView.currentFilter === "hot" ? 0 : browseView.currentFilter === "latest" ? 1 : -1
            onActivated: function(index) { browseView._switchFilter(index === 0 ? "hot" : "latest") }
        }

        // ── Novel grid ────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true

            // Loading overlay: ghost cards where the first page will land
            SkeletonGrid {
                anchors.fill: parent; z: 10
                active: (Novel.isFetchingNovel || Novel.isSwitchingProvider)
                    && Novel.novelList.length === 0
                columns: CardMetrics.columns
                padding: Style.spacing.xl
                cellHeight: CardMetrics.cellHeight((width - 2 * Style.spacing.xl) / CardMetrics.columns)
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
                anchors.fill: parent; anchors.margins: Style.spacing.xl
                cellWidth: Math.floor(width / CardMetrics.columns)
                cellHeight: CardMetrics.cellHeight(cellWidth)
                clip: true; boundsBehavior: Flickable.StopAtBounds
                // A ScriptModel diffs each new array against the last, so appending a
                // page inserts rows instead of resetting the view (and its scroll).
                model: ScriptModel { values: Novel.novelList }

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle { implicitWidth: 3; color: Colors.primary; opacity: 0.45; radius: Style.cornerRadius }
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
        }
    }
}
