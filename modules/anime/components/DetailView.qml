import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.app
import qs.Commons
import qs.services
import Quickshell.Io
import qs.components
import "../../../services/scroll_metrics.js" as ScrollMetrics

Item {
    id: detailView

    readonly property string fontDisplay: Style.font.family
    readonly property string fontBody:    Style.font.family

    signal backRequested()

    // Display asks the visible accessor; writes keep the raw id. While locked,
    // a hidden title reads as not saved and its save is simulated.
    property bool _simulatedSaved: false
    readonly property bool _inLibrary:
        Anime.currentAnime ? (Anime.visibleEntryId() !== "" || _simulatedSaved) : false
    readonly property string _folderName: {
        if (_folderValue === "") return ""
        var folder = Organizer.folder("anime", _folderValue)
        return folder ? folder.name : ""
    }
    readonly property string _folderValue: {
        var entry = Anime.visibleEntry()
        return entry ? (entry.folder || "") : ""
    }

    // ── MPV launcher ──────────────────────────────────────────────────────────
    Process {
        id: mpvProcess
    }

    function _playWithMpv(url, referer, subtitle, title) {
        if (!url || url.length === 0) {
            console.warn("[AnimeDetail] _playWithMpv called with empty URL, aborting")
            return
        }

        mpvProcess.running = false

        var args = [
            "mpv",
            "--fs",
            "--force-window=yes",
            "--title=" + (title || I18n.t("anime.mpvTitle")),
            "--no-terminal"
        ]

        if (referer && referer.length > 0)
            args.push("--referrer=" + referer)
        if (subtitle && subtitle.length > 0)
            args.push("--sub-file=" + subtitle)

        args.push(url)
        mpvProcess.command = args
        mpvProcess.running = true
    }

    Rectangle { anchors.fill: parent; color: Colors.background }

    ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(0)

        Rectangle {
            Layout.fillWidth: true
            height: 52
            color: Colors.surface_container_low
            z: 2

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1; color: Colors.outline_variant; opacity: 0.5
            }

            RowLayout {
                anchors { fill: parent; leftMargin: Style.spacing.md; rightMargin: Style.spacing.xl }
                spacing: Style.spacing.xxs

                // Back
                Item {
                    width: 44; height: 44

                    Rectangle {
                        anchors.centerIn: parent; width: 34; height: 34; radius: Style.cornerRadius
                        color: backArea.containsMouse ? Colors.surface_container : "transparent"
                        Behavior on color { ColorAnimation { duration: Motion.base } }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "←"; font.pixelSize: Style.font.iconLarge; color: Colors.on_surface_variant
                    }
                    MouseArea {
                        id: backArea; anchors.fill: parent; hoverEnabled: true
                        onClicked: detailView.backRequested()
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: Anime.currentAnime
                        ? (Anime.currentAnime.englishName || Anime.currentAnime.name || "")
                        : ""
                    font.family: detailView.fontDisplay
                    font.pixelSize: Style.font.title; color: Colors.on_surface; elide: Text.ElideRight
                }

                Item {
                    visible: Anime.currentAnime !== null
                    width: libBtnLabel.implicitWidth + 28; height: 32

                    Rectangle {
                        anchors.fill: parent; radius: Style.cornerRadius
                        color: detailView._inLibrary ? Colors.primary_container : Colors.surface_container
                        border.color: detailView._inLibrary ? Colors.primary : Colors.outline_variant
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: Motion.base } }
                    }
                    Row {
                        anchors.centerIn: parent; spacing: Style.space(5)

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: detailView._inLibrary ? "✓" : "+"
                            font.pixelSize: Style.font.bodySmall; font.bold: true
                            color: detailView._inLibrary
                                ? Colors.on_primary_container : Colors.on_surface_variant
                            Behavior on color { ColorAnimation { duration: Motion.base } }
                        }
                        StyledText {
                            id: libBtnLabel
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.t("tab.library")
                            font.family: detailView.fontBody
                            font.pixelSize: Style.font.bodySmall; font.letterSpacing: 0.3
                            color: detailView._inLibrary
                                ? Colors.on_primary_container : Colors.on_surface_variant
                            Behavior on color { ColorAnimation { duration: Motion.base } }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true
                        onClicked: {
                            if (detailView._simulatedSaved) {
                                detailView._simulatedSaved = false
                                return
                            }
                            if (detailView._inLibrary) {
                                Anime.removeFromLibrary(Anime.currentAnime.id)
                                return
                            }
                            if (Privacy.locked && Anime.isHiddenLibraryEntry(Anime.currentAnime.id)) {
                                detailView._simulatedSaved = true
                                return
                            }
                            Anime.addToLibrary(Anime.currentAnime)
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true; height: 34
            color: Colors.surface_container
            visible: Anime.currentAnime !== null

            RowLayout {
                anchors { fill: parent; leftMargin: Style.space(16); rightMargin: Style.space(16) }

                StyledText {
                    text: Anime.currentAnime
                        ? I18n.tn("count.episode", Anime.currentAnime.episodes
                            ? Anime.currentAnime.episodes.length : 0)
                        : ""
                    font.family: detailView.fontBody
                    font.pixelSize: Style.font.bodySmall; font.letterSpacing: 1
                    color: Colors.on_surface_variant; opacity: 0.75
                }

                // Which subtitle track was picked (from the resolved stream)
                StyledText {
                    visible: Anime.currentSubtitleLabel.length > 0
                    text: I18n.t("anime.subtitles", { 1: Anime.currentSubtitleLabel })
                    font.family: detailView.fontBody
                    font.pixelSize: Style.font.caption; font.letterSpacing: 0.3
                    color: Colors.tertiary
                    elide: Text.ElideRight
                    Layout.maximumWidth: 220
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    id: folderButton
                    visible: Anime.currentAnime !== null && Anime.visibleEntryId() !== ""
                    width: folderLabel.implicitWidth + 2 * Style.spacing.controlPaddingX
                    height: Style.space(22)
                    radius: Style.cornerRadius
                    color: folderArea.containsMouse
                        ? Colors.surface_container_high : Colors.surface_container
                    border.color: Colors.outline_variant
                    border.width: Style.spacing.hairline

                    StyledText {
                        id: folderLabel
                        anchors.centerIn: parent
                        text: I18n.t("folder.current", { 1: detailView._folderValue === ""
                            ? I18n.t("folder.none") : detailView._folderName })
                        font.family: detailView.fontBody
                        font.pixelSize: Style.font.caption
                        color: Colors.on_surface
                    }
                    MouseArea {
                        id: folderArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: folderPicker.opened = true
                    }
                }

                // Last-watched badge
                Rectangle {
                    readonly property var _entry: Anime.visibleEntry()
                    visible: _entry !== null && _entry !== undefined
                        && _entry.lastWatchedEpNum !== ""
                        && _entry.lastWatchedEpNum !== undefined
                    height: 20; width: lastWatchedText.implicitWidth + 18; radius: Style.cornerRadius
                    color: Style.selectedFillFor(Colors.primary)
                    border.color: Colors.primary; border.width: 1

                    Text {
                        id: lastWatchedText; anchors.centerIn: parent
                        text: {
                            var e = Anime.visibleEntry()
                            return e ? I18n.t("last.ep", { 1: e.lastWatchedEpNum }) : ""
                        }
                        font.family: detailView.fontBody
                        font.pixelSize: 9; font.letterSpacing: 0.8; color: Colors.primary // style-ignore — bespoke size
                    }
                }
            }

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1; color: Colors.outline_variant; opacity: 0.3
            }
        }

        Item {
            Layout.fillWidth: true; Layout.fillHeight: true

            SkeletonList {
                anchors.fill: parent; z: 5
                active: Anime.isFetchingDetail
                rowHeight: 52
                subtitle: false
                dividerInset: 64
            }

            LoadingState {
                anchors.fill: parent; z: 6
                active: Anime.isFetchingLinks
                color: Colors.withAlpha(Colors.background, 0.88)
                label: I18n.t("anime.fetching")
                detail: Anime.currentEpisode ? I18n.t("episode", { 1: Anime.currentEpisode }) : ""
                bodyFont: detailView.fontBody
            }

            // Links error toast
            Rectangle {
                id: linksErrorToast
                anchors {
                    bottom: parent.bottom; horizontalCenter: parent.horizontalCenter
                    bottomMargin: Style.spacing.xxl
                }
                height: 36; radius: Style.cornerRadius
                width: linksErrText.implicitWidth + 28
                color: Colors.error_container
                visible: Anime.linksError.length > 0 && !Anime.isFetchingLinks
                z: 7

                Text {
                    id: linksErrText; anchors.centerIn: parent
                    text: Anime.linksError
                    font.family: detailView.fontBody
                    font.pixelSize: Style.font.bodySmall; color: Colors.on_error_container; elide: Text.ElideRight
                }
            }

            ListView {
                id: epList
                anchors.fill: parent; clip: true
                // One gutter with the top zone (§32.1): the rows line up with
                // the cards' box and the bar keeps its lane.
                anchors.leftMargin: Gutter.left
                anchors.rightMargin: Gutter.right
                boundsBehavior: Flickable.StopAtBounds
                model: Anime.currentAnime ? Anime.currentAnime.episodes : []


                delegate: ClickableRect {
                    id: epRowAreaRect
                    width: epList.width; height: 52

                    readonly property var _libEntry: Anime.visibleEntry()
                    readonly property bool isLastWatched:
                        _libEntry !== null && _libEntry !== undefined
                        && _libEntry.lastWatchedEpNum === String(modelData.number)

                    color: isLastWatched
                        ? Style.selectedFillFor(Colors.primary)
                        : (epRowAreaRect.pressed
                            ? Colors.surface_container_high
                            : (epRowAreaRect.hovered ? Colors.surface_container : "transparent"))
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    Rectangle {
                        anchors {
                            bottom: parent.bottom
                            left: parent.left; right: parent.right
                            leftMargin: Style.space(64); rightMargin: Style.space(16)
                        }
                        height: 1; color: Colors.outline_variant; opacity: 0.22
                    }

                    RowLayout {
                        anchors { fill: parent; leftMargin: Style.space(16); rightMargin: Style.space(16) }
                        spacing: Style.spacing.xxxl

                        Rectangle {
                            width: epPillText.implicitWidth + 16; height: 26; radius: Style.cornerRadius
                            color: isLastWatched ? Colors.primary : Colors.primary_container

                            StyledText {
                                id: epPillText; anchors.centerIn: parent
                                text: I18n.t("ep", { 1: modelData.number || "?" })
                                font.family: detailView.fontBody
                                font.pixelSize: 9; font.bold: true; font.letterSpacing: 0.5 // style-ignore — bespoke size
                                color: isLastWatched ? Colors.on_primary : Colors.on_primary_container
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: I18n.t("episode", { 1: modelData.number || "" })
                            font.family: detailView.fontBody
                            font.pixelSize: Style.font.body; color: Colors.on_surface; elide: Text.ElideRight
                        }

                        // Play icon
                        StyledText {
                            text: "▶"; font.pixelSize: Style.font.subtitle
                            color: epRowAreaRect.hovered ? Colors.primary : Colors.outline
                            opacity: epRowAreaRect.hovered ? 0.9 : 0.35
                            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                            Behavior on color   { ColorAnimation  { duration: Motion.fast } }
                        }
                    }

                    onClicked: {
                            if (!Anime.currentAnime) return

                            Anime.fetchStreamLinks(
                                Anime.currentAnime.id,
                                modelData.number,
                                "best"
                            )

                            if (Anime.isInLibrary(Anime.currentAnime.id)) {
                                Anime.updateLastWatched(
                                    Anime.currentAnime.id,
                                    modelData.id,
                                    modelData.number
                                )
                            }
                        }
                }
            }
        }
    }

    Connections {
        target: Anime
        function onSelectedLinkChanged() {
            if (!Anime.selectedLink) return
            var lnk = Anime.selectedLink
            if (lnk.error) {
                console.warn("[AnimeDetail] selectedLink has error:", lnk.error)
                Anime.clearStreamLinks()
                return
            }
            if (!lnk.url || lnk.url.length === 0) {
                console.warn("[AnimeDetail] selectedLink has no URL, aborting playback")
                Anime.clearStreamLinks()
                return
            }

            var title = Anime.currentAnime
                ? (Anime.currentAnime.englishName || Anime.currentAnime.name)
                + " — " + I18n.t("ep", { 1: Anime.currentEpisode })
                : ""
            detailView._playWithMpv(lnk.url, lnk.referer, lnk.subtitle, title)
            Anime.clearStreamLinks()
        }
    }

    Connections {
        target: Anime
        function onCurrentAnimeChanged() { detailView._simulatedSaved = false }
    }

    FolderPicker {
        id: folderPicker
        anchors.fill: parent
        folders: Privacy.locked
            ? Organizer.folders("anime").filter(function(folder) { return !folder.hidden })
            : Organizer.folders("anime")
        current: detailView._folderValue
        bodyFont: detailView.fontBody
        onChosen: function(folderId) { Anime.setFolder(Anime.currentAnime.id, folderId) }
        onCreateRequested: folderPrompt.openText(I18n.t("folder.create"), "")
    }

    FolderPrompt {
        id: folderPrompt
        anchors.fill: parent
        onAccepted: function(value) {
            var folderId = Organizer.addFolder("anime", value)
            if (folderId !== "") {
                Anime.setFolder(Anime.currentAnime.id, folderId)
            }
        }
    }
}
