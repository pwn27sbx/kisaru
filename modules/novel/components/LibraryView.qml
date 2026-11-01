import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.app
import qs.Commons
import qs.services
import qs.components

Item {
    id: libraryView

    readonly property string fontDisplay: Style.font.family
    readonly property string fontBody:    Style.font.family

    signal novelSelected(string novelId)

    Rectangle { anchors.fill: parent; color: Colors.background }

    ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(0)

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
            visible: !Novel.libraryLoaded
            active: !Novel.libraryLoaded
            padding: Style.spacing.lg
            cellHeight: CardMetrics.cellHeight((width - 2 * Style.spacing.lg) / CardMetrics.columns, Style.space(30))
            footerHeight: 30
        }

        GridView {
            id: libGrid
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: Novel.libraryList.length > 0
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
    }
}
