import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.app
import qs.Commons
import qs.services
import qs.components
import "../../../services/list_metrics.js" as ListMetrics
import "../../../services/scroll_metrics.js" as ScrollMetrics

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

        // Row 3 is gone (owner §32): the layout toggle lives in the tool bar the
        // panel owns, next to the search. This view starts at the content.

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
            Layout.leftMargin: Gutter.left
            Layout.rightMargin: Gutter.right
            visible: !libraryView.listMode && !Novel.libraryLoaded
            active: !libraryView.listMode && !Novel.libraryLoaded
            padding: Style.space(0)
            cellHeight: CardMetrics.cellHeight(width / CardMetrics.columns, Style.space(30))
            footerHeight: 30
        }

        SkeletonList {
            Layout.fillWidth: true; Layout.fillHeight: true
            Layout.leftMargin: Gutter.left
            Layout.rightMargin: Gutter.right
            visible: libraryView.listMode && !Novel.libraryLoaded
            active: libraryView.listMode && !Novel.libraryLoaded
            rowHeight: Style.space(ListMetrics.ROW_HEIGHT_BASE)
            cover: true
            inset: Gutter.ink
        }

        GridView {
            id: libGrid
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: !libraryView.listMode && Novel.libraryList.length > 0
            topMargin: Style.spacing.xl; leftMargin: Gutter.left
            // The bar's lane goes on top of the grid's own inset (owner §30).
            rightMargin: Gutter.right
            bottomMargin: Style.spacing.xl
            // No floor: the columns share the width exactly, so the last card
            // ends on the panel's right ink line (owner, 2026-11-02).
            cellWidth: (width - leftMargin - rightMargin) / CardMetrics.columns
            cellHeight: CardMetrics.cellHeight(cellWidth, Style.space(30))
            clip: true; boundsBehavior: Flickable.StopAtBounds
            model: Novel.libraryList

            // The shared bar, like every other view.
            ScrollBar.vertical: StyledScrollBar {
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
            // One gutter with the tool bar (owner §32.1).
            leftMargin: Gutter.left
            rightMargin: Gutter.right
            clip: true; boundsBehavior: Flickable.StopAtBounds
            model: Novel.libraryList

            ScrollBar.vertical: StyledScrollBar {
            }

            delegate: ListRow {
                // The list's margins are not part of a delegate's width.
                width: libRows.width - libRows.leftMargin - libRows.rightMargin
                height: implicitHeight
                source: modelData.coverUrl || ""
                title: modelData.title || ""
                bodyFont: libraryView.fontBody
                inset: Gutter.ink
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
