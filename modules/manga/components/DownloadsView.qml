import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.app
import qs.Commons
import qs.services
import qs.components
import "../../../services/downloads.js" as DownloadsJs
import "../../../services/chapters.js" as Chapters
import "../../../services/header_cell.js" as HeaderCell

Item {
    id: downloadsView

    readonly property string fontDisplay: Style.font.family
    readonly property string fontBody:    Style.font.family

    readonly property var _seriesList: Manga.visibleDownloadsList
    readonly property var _summary: Manga.visibleDownloadsSummary

    // Series ids the user has unfolded. In-memory only: it survives list
    // refreshes and resets when the view is rebuilt.
    property var _expanded: ({})

    signal backRequested()
    signal chapterSelected(var series, var chapter)

    Rectangle { anchors.fill: parent; color: Colors.background }

    ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(0)

        // ── Header ────────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: Style.space(56)
            color: Colors.surface_container_low
            z: 2

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1; color: Colors.outline_variant; opacity: 0.5
            }

            RowLayout {
                anchors { fill: parent; leftMargin: Style.spacing.md; rightMargin: Style.spacing.xl }
                spacing: Style.spacing.xxs

                // Back button
                Item {
                    width: Style.space(44); height: Style.space(44)

                    Rectangle {
                        anchors.centerIn: parent
                        width: Style.space(34); height: Style.space(34); radius: Style.cornerRadius
                        color: backArea.containsMouse ? Colors.surface_container : "transparent"
                        Behavior on color { ColorAnimation { duration: Motion.base } }
                    }
                    StyledText {
                        anchors.centerIn: parent
                        text: "←"
                        font.pixelSize: Style.font.iconLarge
                        color: Colors.on_surface_variant
                    }
                    MouseArea {
                        id: backArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: downloadsView.backRequested()
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: I18n.t("manga.downloads")
                    font.family: downloadsView.fontDisplay
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                    color: Colors.on_surface
                    elide: Text.ElideRight
                }

                // Visible total disk space badge
                Rectangle {
                    visible: downloadsView._summary.chapterCount > 0
                    height: Style.space(24)
                    width: totalSizeText.implicitWidth + Style.space(16)
                    radius: Style.cornerRadius
                    color: Colors.surface_container_high

                    StyledText {
                        id: totalSizeText
                        anchors.centerIn: parent
                        text: DownloadsJs.formatBytes(downloadsView._summary.totalBytes)
                        font.family: downloadsView.fontBody
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        color: Colors.on_surface_variant
                    }
                }
            }
        }

        // ── Body ──────────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            EmptyState {
                visible: downloadsView._seriesList.length === 0
                glyph: "↓"
                title: I18n.t("manga.downloads.empty")
                subtitle: I18n.t("manga.downloads.hint")
                displayFont: downloadsView.fontDisplay
                bodyFont: downloadsView.fontBody
            }

            ListView {
                id: seriesListView
                anchors {
                    fill: parent
                    leftMargin: Gutter.left
                    rightMargin: Gutter.right
                }
                visible: downloadsView._seriesList.length > 0
                topMargin: Style.spacing.xl
                bottomMargin: Style.spacing.xl
                spacing: Style.spacing.xxl
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: downloadsView._seriesList

                delegate: Column {
                    id: seriesBlock
                    required property var modelData
                    width: seriesListView.width
                    spacing: Style.spacing.xs

                    readonly property bool expanded: DownloadsJs.isExpanded(downloadsView._expanded, seriesBlock.modelData.id)

                    // Series header: click folds or unfolds its chapters
                    ClickableRect {
                        id: seriesHeader
                        width: parent.width
                        height: Style.space(62)
                        radius: Style.cornerRadius
                        cursorShape: Qt.PointingHandCursor
                        readonly property var _cell: HeaderCell.cellStyle({
                            current: false,
                            hovered: seriesHeader.hovered,
                            pressed: seriesHeader.pressed
                        })
                        color: seriesHeader._cell.fill === HeaderCell.FILL.PRESSED
                            ? Style.pressedFillFor(Colors.surface_container, Colors.primary)
                            : seriesHeader._cell.fill === HeaderCell.FILL.HOVER
                                ? Style.hoverFillFor(Colors.surface_container, Colors.primary)
                                : Colors.surface_container
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        onClicked: downloadsView._expanded = DownloadsJs.toggleExpanded(downloadsView._expanded, seriesBlock.modelData.id)

                        RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: Style.spacing.md
                                rightMargin: Style.spacing.lg
                            }
                            spacing: Style.spacing.lg

                            Rectangle {
                                Layout.preferredWidth: Style.space(34)
                                Layout.preferredHeight: Style.space(48)
                                radius: Style.cornerRadius
                                color: Colors.surface_container_high
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    source: seriesBlock.modelData.image || ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                            }

                            Column {
                                Layout.fillWidth: true
                                spacing: Style.spacing.xxs

                                StyledText {
                                    width: parent.width
                                    text: seriesBlock.modelData.title || seriesBlock.modelData.id
                                    font.family: downloadsView.fontBody
                                    font.pixelSize: Style.font.body
                                    font.bold: true
                                    color: Colors.on_surface
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    width: parent.width
                                    text: I18n.tn("count.chapter", (seriesBlock.modelData.chapters || []).length)
                                        + "  ·  " + DownloadsJs.formatBytes(seriesBlock.modelData.sizeBytes)
                                    font.family: downloadsView.fontBody
                                    font.pixelSize: Style.font.caption
                                    color: Colors.on_surface_variant
                                    elide: Text.ElideRight
                                }
                            }

                            StyledText {
                                text: "›"
                                font.pixelSize: Style.font.iconLarge
                                color: Colors.on_surface_variant
                                rotation: seriesBlock.expanded ? 90 : 0
                                Behavior on rotation { NumberAnimation { duration: Motion.fast } }
                            }
                        }
                    }

                    // Downloaded chapters for this series (rows exist only while unfolded)
                    Repeater {
                        model: seriesBlock.expanded ? (seriesBlock.modelData.chapters || []) : []

                        delegate: ClickableRect {
                            id: dlChapterRow
                            required property var modelData
                            width: seriesBlock.width
                            height: Style.space(52)
                            radius: Style.cornerRadius
                            color: dlChapterRow.pressed
                                ? Colors.surface_container_high
                                : (dlChapterRow.hovered ? Colors.surface_container_low : "transparent")
                            Behavior on color { ColorAnimation { duration: Motion.fast } }

                            RowLayout {
                                anchors {
                                    fill: parent
                                    leftMargin: Style.spacing.lg
                                    rightMargin: Style.spacing.md
                                }
                                spacing: Style.spacing.lg

                                Rectangle {
                                    width: chPill.implicitWidth + Style.space(14)
                                    height: Style.space(24)
                                    radius: Style.cornerRadius
                                    color: Colors.primary_container

                                    StyledText {
                                        id: chPill
                                        anchors.centerIn: parent
                                        text: I18n.t("ch", { 1: Chapters.formatChapter(dlChapterRow.modelData.chapterNum) })
                                        font.family: downloadsView.fontBody
                                        font.pixelSize: Style.font.caption
                                        font.bold: true
                                        color: Colors.on_primary_container
                                    }
                                }

                                Column {
                                    Layout.fillWidth: true
                                    spacing: Style.spacing.xxs

                                    StyledText {
                                        width: parent.width
                                        text: dlChapterRow.modelData.title
                                            || I18n.t("chapter", { 1: Chapters.formatChapter(dlChapterRow.modelData.chapterNum) })
                                        font.family: downloadsView.fontBody
                                        font.pixelSize: Style.font.bodySmall
                                        color: Colors.on_surface
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        width: parent.width
                                        text: DownloadsJs.formatBytes(dlChapterRow.modelData.sizeBytes)
                                        font.family: downloadsView.fontBody
                                        font.pixelSize: Style.font.caption
                                        color: Colors.on_surface_variant
                                        opacity: 0.7
                                    }
                                }

                                // Delete button
                                Item {
                                    width: Style.space(32)
                                    height: Style.space(32)

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Style.cornerRadius
                                        color: delArea.containsMouse
                                            ? Colors.withAlpha(Colors.error, 0.15)
                                            : "transparent"
                                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                                    }

                                    StyledText {
                                        anchors.centerIn: parent
                                        text: "✕"
                                        font.family: downloadsView.fontBody
                                        font.pixelSize: Style.font.bodySmall
                                        color: delArea.containsMouse ? Colors.error : Colors.on_surface_variant
                                    }

                                    MouseArea {
                                        id: delArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: function(mouse) {
                                            mouse.accepted = true
                                            Manga.deleteDownload(dlChapterRow.modelData.chapterId)
                                        }

                                        ToolTip.visible: containsMouse
                                        ToolTip.delay: 500
                                        ToolTip.text: I18n.t("manga.downloadDelete")
                                    }
                                }
                            }

                            onClicked: downloadsView.chapterSelected(seriesBlock.modelData, dlChapterRow.modelData)
                        }
                    }
                }
            }
        }
    }
}
