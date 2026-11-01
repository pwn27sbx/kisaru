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
    readonly property bool listMode: UiPrefs.viewModeFor("novel") === "list"

    signal novelSelected(string novelId)

    Rectangle { anchors.fill: parent; color: Colors.background }

    ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(0)

        // ── Grid/list toggle, alone on its row ───────────────────────────────
        // The same segmented box the other two panels use; the novel panel
        // keeps its own layout preference (owner, round 6).
        RowLayout {
            Layout.fillWidth: true
            Layout.rightMargin: Style.spacing.xl
            spacing: Style.spacing.sm

            Item { Layout.fillWidth: true }

            ViewModeToggle {
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: Style.spacing.xl
                panel: "novel"
                listMode: libraryView.listMode
                fontFamily: libraryView.fontBody
            }
        }

        Item {
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: Novel.libraryList.length === 0 && Novel.libraryLoaded

            EmptyState {
                title: I18n.t("empty.library")
                subtitle: I18n.t("novel.library.hint")
                displayFont: libraryView.fontDisplay
                bodyFont: libraryView.fontBody
            }
        }


        SkeletonGrid {
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: !libraryView.listMode && !Novel.libraryLoaded
            active: !libraryView.listMode && !Novel.libraryLoaded
            padding: Style.spacing.lg
            cellHeight: CardMetrics.cellHeight((width - 2 * Style.spacing.lg) / CardMetrics.columns, Style.space(30))
            footerHeight: 30
        }

        SkeletonList {
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: libraryView.listMode && !Novel.libraryLoaded
            active: libraryView.listMode && !Novel.libraryLoaded
            rowHeight: Style.space(ListMetrics.ROW_HEIGHT_BASE)
            dividerInset: Style.spacing.lg
        }

        GridView {
            id: libGrid
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: !libraryView.listMode && Novel.libraryList.length > 0
            topMargin: Style.spacing.xl; leftMargin: Style.spacing.lg
            rightMargin: Style.spacing.lg; bottomMargin: Style.spacing.xl
            cellWidth: Math.floor((width - leftMargin - rightMargin) / CardMetrics.columns)
            cellHeight: CardMetrics.cellHeight(cellWidth, Style.space(30))
            clip: true; boundsBehavior: Flickable.StopAtBounds
            model: Novel.libraryList

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle { implicitWidth: 3; color: Colors.primary; opacity: 0.45; radius: Style.cornerRadius }
            }

            delegate: Item {
                width: libGrid.cellWidth
                height: libGrid.cellHeight

                CoverCard {
                    anchors.fill: parent
                    source: modelData.coverUrl || ""
                    title: modelData.title || ""
                    bodyFont: libraryView.fontBody
                    footerHeight: 30

                    CoverProgressBar {
                        height: 30
                        rowSpacing: Style.spacing.md
                        bodyFont: libraryView.fontBody
                        started: modelData.lastReadChapterNum
                        label: modelData.lastReadChapterNum
                                ? I18n.t("ch", { 1: modelData.lastReadChapterNum })
                                : I18n.t("state.notStarted")
                    }

                    onClicked: {
                        Novel.fetchNovelDetail(modelData.id)
                        libraryView.novelSelected(modelData.id)
                    }
                }
            }

        }

        // ── List ─────────────────────────────────────────────────────────────
        ListView {
            id: libRows
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: Novel.libraryList.length > 0 && libraryView.listMode
            topMargin: Style.spacing.xl
            bottomMargin: Style.spacing.xl
            clip: true; boundsBehavior: Flickable.StopAtBounds
            model: Novel.libraryList

            ScrollBar.vertical: StyledScrollBar {
            }

            delegate: ListRow {
                width: libRows.width
                height: implicitHeight
                source: modelData.coverUrl || ""
                title: modelData.title || ""
                bodyFont: libraryView.fontBody
                inset: Style.spacing.lg
                meta: ""
                progress: modelData.lastReadChapterNum ? I18n.t("ch", { 1: modelData.lastReadChapterNum }) : I18n.t("state.notStarted")
                progressActive: !!modelData.lastReadChapterNum

                onClicked: {
                    Novel.fetchNovelDetail(modelData.id)
                    libraryView.novelSelected(modelData.id)
                }
            }
        }
    }
}
