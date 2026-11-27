import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.app
import qs.Commons
import qs.services
import qs.components
import "../../../services/detail_hide.js" as DetailHide
import "../../../services/chapters.js" as Chapters
import "../../../services/list_badge.js" as ListBadge
import "../../../services/scroll_metrics.js" as ScrollMetrics

Item {
    id: detailView

    readonly property string fontDisplay: Style.font.family
    readonly property string fontBody:    Style.font.family

    signal backRequested()
    signal chapterSelected(string chapterId)
    signal searchOtherSourcesRequested()
    // Hiding from Detail returns to the Library and leaves no detail behind.
    signal hiddenRequested()

    // ── Library state ─────────────────────────────────────────────────────────
    // Display asks the visible accessor; the raw key stays for writes. While
    // locked, a hidden title reads as not saved and its save is simulated for
    // this session only (owner decision, 2026-11-05).
    property bool _simulatedSaved: false
    readonly property bool _inLibrary:
        Manga.currentManga ? (Manga.visibleEntryId() !== "" || _simulatedSaved) : false
    readonly property string _folderName: {
        if (_folderValue === "") return ""
        var folder = Organizer.folder("manga", _folderValue)
        return folder ? folder.name : ""
    }
    readonly property string _folderValue: {
        var entry = Manga.visibleEntry()
        return entry ? (entry.folder || "") : ""
    }

    readonly property var _rawEntry: Manga.currentManga ? Manga.getLibraryEntry(Manga.libraryEntryId()) : null

    // The folder that decides the hide switch is the raw entry's, never the
    // visible one: a title inside a hidden folder has no visible entry while
    // the word is locked, and that is exactly the case the switch explains.
    readonly property string _rawFolderValue: detailView._rawEntry !== null
        ? (detailView._rawEntry.folder || "") : ""
    readonly property string _rawFolderName: {
        if (detailView._rawFolderValue === "") return ""
        var folder = Organizer.folder("manga", detailView._rawFolderValue)
        return folder ? folder.name : ""
    }
    readonly property bool _folderHidden: Organizer.isHidden("manga", detailView._rawFolderValue)
    readonly property var _hideView: DetailHide.switchView({
        locked: Privacy.locked,
        hidden: detailView._rawEntry !== null && detailView._rawEntry.hidden === true,
        folderHidden: detailView._folderHidden,
        folderName: detailView._rawFolderName
    })
    readonly property string _hideNote: detailView._hideView.noteFolder === ""
        ? "" : KisaruI18n.t("folder.hiddenBy", { 1: detailView._hideView.noteFolder })


    // Hiding from the Detail keeps the Detail open (owner, 2026-11-05): the
    // title is marked hidden and stays usable so it can be filed into a hidden
    // folder right here. The lock waits for the leave, which is when the title
    // must be gone from the Library. The decision itself lives in
    // services/detail_hide.js so the three panels cannot drift apart.
    property bool _hiddenInDetail: false

    function _settleHiddenInDetail() {
        if (!detailView._hiddenInDetail) return
        detailView._hiddenInDetail = false
        Privacy.lock()
    }

    // Leaving the Detail — back, tab change, close, minimize, panel switch —
    // applies the deferred hide: the title is already marked hidden, so the
    // lock is what removes it from the Library.
    onVisibleChanged: if (!visible) detailView._settleHiddenInDetail()

    function _toggleHiddenTitle() {
        var entry = detailView._rawEntry
        if (entry === null) return
        var action = DetailHide.toggle({
            configured: Privacy.configured,
            locked: Privacy.locked,
            hidden: entry.hidden === true,
            folderHidden: detailView._folderHidden
        })
        if (action === DetailHide.ACTION.IGNORE) return
        var key = Manga.libraryEntryId()
        if (action === DetailHide.ACTION.HIDE_LEAVE) Manga.setHidden(key, true)
        if (action === DetailHide.ACTION.UNHIDE_STAY) {
            detailView._hiddenInDetail = false
            Manga.setHidden(key, false)
        }
        if (action === DetailHide.ACTION.HIDE_STAY) {
            Manga.setHidden(key, true)
            detailView._hiddenInDetail = true
        }
        if (action === DetailHide.ACTION.HIDE_LEAVE
                || action === DetailHide.ACTION.LEAVE)
            detailView.hiddenRequested()
    }

    // Human-readable list of the sources the ES chain tried (plan §F3).
    readonly property string _sourcesLabel: {
        const ids = Manga.sourcesTried || []
        return ids.map(function(id) { return KisaruI18n.tSource(id) }).join(", ")
    }

    // ── Filter / sort state ───────────────────────────────────────────────────
    property bool   _sortAscending:  false
    property string _chapterFilter:  ""

    function reset() {
        _chapterFilter  = ""
        _sortAscending  = false
        _pendingJumpNum = ""
        _simulatedSaved = false
    }

    // ── Helper ────────────────────────────────────────────────────────────────
    function formatChapter(ch) {
        return Chapters.formatChapter(ch)
    }

    // The badge text of one row. The list measures the same strings once
    // (chapterBadges) and the row draws its own, so both must come from here.
    function badgeLabel(ch) {
        return KisaruI18n.t("ch", { 1: detailView.formatChapter(ch) })
    }

    // Chapter dates arrive day-first ("09/04/2026"); Qt.formatDate alone would
    // be right, but `new Date("09/04/2026")` reads month first. The helper in
    // services/chapters.js parses both shapes and returns "" when unreadable.
    function formatDate(value) {
        const date = Chapters.parseChapterDate(value)
        return date === null ? "" : Qt.formatDate(date, "MMM d, yyyy")
    }

    // "Last: Ch. N" is the way back to where the reading stopped. The stored
    // chapter id belongs to whichever source answered last time, so the row is
    // matched by chapter number (services/chapters.js) and scrolled into view.
    //
    // A click can land while the chapter list is still loading (or while a
    // filter is being cleared): there is no row to scroll to yet, so the number
    // is remembered and the jump completes when the model fills.
    property string _pendingJumpNum: ""

    function jumpToLastRead() {
        if (!Manga.currentManga) return
        const entry = Manga.visibleEntry()
        if (!entry || !entry.lastReadChapterNum) return
        // An active filter could hide the very row we are looking for.
        detailView._chapterFilter = ""
        chapterSearch.text = ""
        detailView._pendingJumpNum = entry.lastReadChapterNum
        detailView._applyPendingJump()
        Qt.callLater(detailView._applyPendingJump)
    }

    function _applyPendingJump() {
        if (detailView._pendingJumpNum === "") return
        // A stored "2.1" belongs to the grouped "2" row.
        const number = Chapters.canonicalNumber(Manga.chapterGroups, detailView._pendingJumpNum)
        const index = Chapters.chapterIndex(detailView._processedGroups, number)
        if (index < 0) return          // still loading: onCountChanged retries
        detailView._pendingJumpNum = ""
        chapterList.positionViewAtIndex(index, ListView.Beginning)
    }

    // ── Processed (filtered + sorted) chapter list ────────────────────────────
    // One row per chapter, not per upload: a re-uploaded "1.1" lives inside
    // the "1" row behind the version picker (services/chapters.js).
    readonly property var _processedGroups: {
        if (!Manga.currentManga) return []
        let groups = Manga.chapterGroups.slice()

        if (detailView._chapterFilter.trim() !== "") {
            const f = detailView._chapterFilter.trim().toLowerCase()
            groups = groups.filter(group => {
                if (detailView.formatChapter(group.chapter).toLowerCase().includes(f)) return true
                return group.versions.some(v =>
                    detailView.formatChapter(v.chapter).toLowerCase().includes(f)
                    || (v.title || "").toLowerCase().includes(f)
                    || (v.group || "").toLowerCase().includes(f))
            })
        }

        groups.sort((a, b) => {
            const numA = parseFloat(detailView.formatChapter(a.chapter)) || 0
            const numB = parseFloat(detailView.formatChapter(b.chapter)) || 0
            return detailView._sortAscending ? numA - numB : numB - numA
        })

        return groups
    }

    // ── Version picker ────────────────────────────────────────────────────────
    property var _pickerGroup: null

    function openVersions(group) {
        if (!group || group.versions.length < 2) return
        detailView._pickerGroup = group
        versionPicker.rows = detailView.versionRows(group)
        versionPicker.currentId = group.primary.id
        versionPicker.wholeSeries = false
        versionPicker.opened = true
    }

    // The row masks a hidden title's download state; the picker must not become
    // a side channel for it, so the same gate covers every upload there.
    readonly property bool _pickerHidesDownloads:
        Privacy.locked && Manga.isHiddenLibraryEntry(Manga.libraryEntryId())

    // Rows the picker draws: the source number with its own date (owner,
    // 2026-11-27: "Capítulo 1.1 · 21/04/2026"), the group when the source
    // names one, and the state of that exact upload.
    function versionRows(group) {
        return Chapters.versionRows(group, function(versionId) {
            return Manga.chapterDownloadState(versionId)
        }, detailView._pickerHidesDownloads)
    }

    function chooseVersion(versionId) {
        const group = detailView._pickerGroup
        if (!group) return
        const version = Chapters.pickVersion(group, versionId)
        if (!version) return
        // "Use this version for the whole series" stores the upload batch; the
        // plain choice stays per chapter.
        if (versionPicker.wholeSeries) Manga.setSeriesVersion(group.chapter, version.id)
        else Manga.setChapterVersion(group.chapter, version.id)
        if (Manga.openChapter(version)) detailView.chapterSelected(version.id)
    }

    function downloadVersion(versionId) {
        const group = detailView._pickerGroup
        if (!group) return
        const version = Chapters.pickVersion(group, versionId)
        if (!version) return
        Manga.startDownload(version)
        versionPicker.rows = detailView.versionRows(group)
    }

    // ═════════════════════════════════════════════════════════════════════════
    ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(0)

        // ── Header ────────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 56
            color: Colors.surface_container_low
            z: 2

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1; color: Colors.outline_variant; opacity: 0.5
            }

            RowLayout {
                anchors { fill: parent; leftMargin: Style.spacing.md; rightMargin: Style.spacing.xl }
                spacing: Style.spacing.xxs

                // ── Back button ───────────────────────────────────────────────
                Item {
                    width: 44; height: 44

                    Rectangle {
                        anchors.centerIn: parent
                        width: 34; height: 34; radius: Style.cornerRadius
                        color: backArea.containsMouse ? Colors.surface_container : Colors.clear(Colors.surface_container)
                        Behavior on color { ColorAnimation { duration: Motion.base } }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "←"; font.pixelSize: Style.font.iconLarge; color: Colors.on_surface_variant
                    }
                    MouseArea {
                        id: backArea; anchors.fill: parent; hoverEnabled: true
                        onClicked: { Manga.clearChapterList(); detailView.backRequested() }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: Manga.currentManga ? Manga.currentManga.title : ""
                    font.family: detailView.fontDisplay
                    font.pixelSize: 15; color: Colors.on_surface; elide: Text.ElideRight // style-ignore — bespoke size
                }

                // ── Library toggle ────────────────────────────────────────────
                Item {
                    visible: Manga.currentManga !== null
                    width: libBtnLabel.implicitWidth + 28
                    height: 34

                    Rectangle {
                        anchors.fill: parent
                        radius: Style.cornerRadius
                        color: detailView._inLibrary ? Colors.primary_container : Colors.surface_container
                        border.color: detailView._inLibrary ? Colors.primary : Colors.outline_variant
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: Motion.base } }
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: Style.space(5)

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: detailView._inLibrary ? "✓" : "+"
                            font.pixelSize: Style.font.bodySmall; font.bold: true
                            color: detailView._inLibrary ? Colors.on_primary_container : Colors.on_surface_variant
                            Behavior on color { ColorAnimation { duration: Motion.base } }
                        }
                        StyledText {
                            id: libBtnLabel
                            anchors.verticalCenter: parent.verticalCenter
                            text: KisaruI18n.t("tab.library")
                            font.family: detailView.fontBody
                            font.pixelSize: Style.font.bodySmall; font.letterSpacing: 0.3
                            color: detailView._inLibrary ? Colors.on_primary_container : Colors.on_surface_variant
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
                                Manga.removeFromLibrary(Manga.libraryEntryId())
                                return
                            }
                            // A hidden title opened from Browse while locked:
                            // pretend for this session and write nothing.
                            if (Privacy.locked && Manga.isHiddenLibraryEntry(Manga.libraryEntryId())) {
                                detailView._simulatedSaved = true
                                return
                            }
                            Manga.addToLibrary({
                                id:       Manga.libraryWriteKey(),
                                title:    Manga.currentManga.title,
                                coverUrl: Manga.currentManga.coverUrl
                            })
                        }
                    }
                }
            }
        }

        // ── No-Spanish notice ─────────────────────────────────────────────────
        Rectangle {
            id: noSpanishNotice
            Layout.fillWidth: true
            visible: Manga.notice === "no_spanish"
            Layout.preferredHeight: noSpanishNotice.visible ? noSpanishColumn.implicitHeight + 22 : 0
            color: Colors.error_container
            z: 3

            Column {
                id: noSpanishColumn
                anchors {
                    left: parent.left; right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: Style.space(16); rightMargin: Style.space(16)
                }
                spacing: Style.spacing.sm

                StyledText {
                    id: noSpanishTitle
                    width: parent.width
                    text: "⚠  " + KisaruI18n.t("manga.noSpanishNotice")
                    font.family: detailView.fontBody
                    font.pixelSize: Style.font.bodySmall; font.bold: true
                    color: Colors.on_error_container
                    wrapMode: Text.Wrap
                }

                StyledText {
                    width: parent.width
                    visible: detailView._sourcesLabel.length > 0
                    text: KisaruI18n.t("manga.sourcesTried", { 1: detailView._sourcesLabel })
                    font.family: detailView.fontBody
                    font.pixelSize: Style.font.caption
                    color: Colors.on_error_container
                    opacity: 0.85
                    wrapMode: Text.Wrap
                }

                Rectangle {
                    id: otherSourcesButton
                    height: otherSourcesLabel.implicitHeight + Style.spacing.controlPaddingY * 2
                    width: otherSourcesLabel.implicitWidth + Style.spacing.controlPaddingX * 2
                    radius: Style.cornerRadius
                    color: otherSourcesArea.containsMouse
                        ? Colors.error
                        : Colors.withAlpha(Colors.error, 0.15)
                    border.color: Colors.error; border.width: 1
                    Behavior on color { ColorAnimation { duration: Motion.base } }

                    StyledText {
                        id: otherSourcesLabel
                        anchors.centerIn: parent
                        text: KisaruI18n.t("manga.searchOtherSources")
                        font.family: detailView.fontBody
                        font.pixelSize: Style.font.caption; font.bold: true
                        color: otherSourcesArea.containsMouse
                            ? Colors.on_error
                            : Colors.on_error_container
                    }

                    MouseArea {
                        id: otherSourcesArea
                        anchors.fill: parent; hoverEnabled: true
                        onClicked: detailView.searchOtherSourcesRequested()
                    }
                }
            }
        }

        // ── Hero banner ───────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Manga.currentManga !== null ? 160 : 0
            clip: true
            Behavior on Layout.preferredHeight { NumberAnimation { duration: Motion.slow; easing.type: Motion.easeOut } }

            // Blurred cover background
            Image {
                anchors.fill: parent
                source: Manga.currentManga ? Manga.currentManga.coverUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true; opacity: 0.2
            }

            // Gradient overlay
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Colors.withAlpha(Colors.surface_container_low, 0.8) }
                    GradientStop { position: 1.0; color: Colors.background }
                }
            }

            // Content row
            Row {
                anchors { fill: parent; margins: Style.spacing.xxxl }
                spacing: Style.spacing.xxxl

                // Cover thumbnail
                Rectangle {
                    width: 90; height: 130; radius: Style.cornerRadius
                    color: Colors.surface_container_high; clip: true
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        anchors.fill: parent
                        source: Manga.currentManga ? Manga.currentManga.coverUrl : ""
                        fillMode: Image.PreserveAspectCrop; asynchronous: true
                    }
                    Rectangle {
                        anchors.fill: parent; radius: Style.cornerRadius; color: "transparent"
                        border.color: Colors.outline_variant; border.width: 1
                    }
                }

                Column {
                    width: parent.width - 104
                    spacing: Style.spacing.md; anchors.verticalCenter: parent.verticalCenter

                    // Status badge
                    Rectangle {
                        visible: Manga.currentManga && Manga.currentManga.status.length > 0
                        height: 18; width: statusText.implicitWidth + 14; radius: Style.cornerRadius
                        color: Colors.withAlpha(Colors.tertiary, 0.15)
                        border.color: Colors.tertiary; border.width: 1

                        StyledText {
                            id: statusText; anchors.centerIn: parent
                            text: Manga.currentManga ? KisaruI18n.tData(Manga.currentManga.status || "").toUpperCase() : ""
                            font.family: detailView.fontBody
                            font.pixelSize: 9; font.letterSpacing: 1.2; font.bold: true // style-ignore — bespoke size
                            color: Colors.tertiary
                        }
                    }

                    // Author
                    StyledText {
                        width: parent.width
                        text: Manga.currentManga ? (Manga.currentManga.authors || []).join(", ") : ""
                        font.family: detailView.fontBody
                        font.pixelSize: Style.font.body; font.bold: true
                        color: Colors.on_surface; elide: Text.ElideRight
                    }

                    // Description
                    StyledText {
                        width: parent.width
                        text: Manga.currentManga ? Manga.currentManga.description : ""
                        font.family: detailView.fontBody; font.pixelSize: Style.font.bodySmall
                        color: Colors.on_surface_variant
                        wrapMode: Text.Wrap; maximumLineCount: 3
                        elide: Text.ElideRight; opacity: 0.8; lineHeight: 1.35
                    }
                }
            }

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1; color: Colors.outline_variant; opacity: 0.35
            }
        }

        // ── Chapter count + last-read strip ───────────────────────────────────
        Rectangle {
            Layout.fillWidth: true; height: 36
            color: Colors.surface_container
            visible: Manga.currentManga !== null

            RowLayout {
                anchors { fill: parent; leftMargin: Style.space(16); rightMargin: Style.space(16) }

                StyledText {
                    text: Manga.currentManga ? KisaruI18n.tn("count.chapter", Manga.chapterCount) : ""
                    font.family: detailView.fontBody
                    font.pixelSize: Style.font.bodySmall; font.letterSpacing: 1
                    color: Colors.on_surface_variant; opacity: 0.75
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    id: folderButton
                    visible: Manga.currentManga !== null && Manga.visibleEntryId() !== ""
                    width: folderLabel.implicitWidth + 2 * Style.spacing.controlPaddingX
                    height: Style.space(24)
                    radius: Style.cornerRadius
                    color: folderArea.containsMouse
                        ? Colors.surface_container_high : Colors.surface_container
                    border.color: Colors.outline_variant
                    border.width: Style.spacing.hairline

                    StyledText {
                        id: folderLabel
                        anchors.centerIn: parent
                        text: KisaruI18n.t("folder.current", { 1: detailView._folderValue === ""
                            ? KisaruI18n.t("folder.none") : detailView._folderName })
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

                HideSwitch {
                    visible: Privacy.configured && detailView._rawEntry !== null
                    checked: detailView._hideView.checked
                    note: detailView._hideNote
                    interactive: detailView._hideView.noteFolder === ""
                    bodyFont: detailView.fontBody
                    onClicked: detailView._toggleHiddenTitle()
                }

                // Last-read badge — click it to jump to that chapter
                Rectangle {
                    id: lastReadBadge
                    readonly property var _entry: Manga.visibleEntry()
                    visible: _entry !== null && _entry !== undefined
                        && _entry.lastReadChapterNum !== ""
                        && _entry.lastReadChapterNum !== undefined
                    height: 20; width: lastReadText.implicitWidth + 18; radius: Style.cornerRadius
                    color: lastReadArea.containsMouse
                        ? Colors.primary_container
                        : Style.selectedFillFor(Colors.primary)
                    border.color: Colors.primary; border.width: 1
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    Text {
                        id: lastReadText; anchors.centerIn: parent
                        text: {
                            var e = Manga.visibleEntry()
                            return e ? KisaruI18n.t("last.ch", { 1: detailView.formatChapter(e.lastReadChapterNum) }) : ""
                        }
                        font.family: detailView.fontBody
                        font.pixelSize: 9; font.letterSpacing: 0.8 // style-ignore — bespoke size
                        color: lastReadArea.containsMouse ? Colors.on_primary_container : Colors.primary
                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }

                    MouseArea {
                        id: lastReadArea
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: detailView.jumpToLastRead()
                    }
                }
            }

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1; color: Colors.outline_variant; opacity: 0.3
            }
        }

        // ── Search & Sort bar ─────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true; height: 56
            color: Colors.surface_container_low
            visible: Manga.currentManga !== null

            RowLayout {
                anchors { fill: parent; leftMargin: Style.spacing.xxl; rightMargin: Style.spacing.xxl }
                spacing: Style.spacing.lg

                // Search pill
                Rectangle {
                    Layout.fillWidth: true
                    height: 36; radius: Style.cornerRadius
                    color: Colors.surface_container
                    border.width: 1
                    border.color: chapterSearch.activeFocus ? Colors.primary : Colors.withAlpha(Colors.outline, 0.2)
                    Behavior on border.color { ColorAnimation { duration: Motion.base } }

                    RowLayout {
                        anchors { fill: parent; leftMargin: Style.spacing.xxl; rightMargin: Style.spacing.sm }
                        spacing: Style.spacing.md

                        StyledText {
                            text: "⌕"
                            font.pixelSize: Style.font.heading
                            color: Colors.primary; opacity: 0.7
                        }

                        TextInput {
                            id: chapterSearch
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            font.family: detailView.fontBody
                            font.pixelSize: Style.font.body
                            color: Colors.on_surface
                            selectionColor: Style.selectionFillFor(Colors.primary)
                            clip: true

                            // Placeholder text
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: KisaruI18n.t("filterChapters")
                                font.family: detailView.fontBody
                                font.pixelSize: Style.font.body
                                color: Colors.on_surface_variant
                                opacity: 0.45
                                visible: chapterSearch.text === "" && !chapterSearch.activeFocus
                            }

                            onTextChanged: detailView._chapterFilter = text
                        }

                        // Clear button — only shown when there is text
                        Item {
                            width: visible ? 28 : 0; height: 28
                            visible: detailView._chapterFilter !== ""

                            Rectangle {
                                anchors.centerIn: parent
                                width: 22; height: 22; radius: Style.cornerRadius
                                color: clearArea.containsMouse
                                    ? Style.hoverFillFor(Colors.on_surface)
                                    : Colors.clear(Style.hoverFillFor(Colors.on_surface))
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                            }
                            StyledText {
                                anchors.centerIn: parent
                                text: "✕"; font.pixelSize: Style.font.bodySmall
                                color: Colors.on_surface_variant
                            }
                            MouseArea {
                                id: clearArea; anchors.fill: parent; hoverEnabled: true
                                onClicked: {
                                    detailView._chapterFilter = ""
                                    chapterSearch.text = ""
                                }
                            }
                        }
                    }
                }

                // Sort toggle button
                Item {
                    width: 36; height: 36

                    Rectangle {
                        anchors.fill: parent; radius: Style.cornerRadius
                        color: sortArea.containsMouse
                            ? Colors.primary_container
                            : Colors.withAlpha(Colors.primary_container, 0.6)
                        border.color: Colors.primary; border.width: 1
                        Behavior on color { ColorAnimation { duration: Motion.base } }
                    }
                    StyledText {
                        anchors.centerIn: parent
                        text: detailView._sortAscending ? "↑" : "↓"
                        font.pixelSize: Style.font.heading; font.bold: true
                        color: Colors.on_primary_container
                    }
                    MouseArea {
                        id: sortArea; anchors.fill: parent; hoverEnabled: true
                        onClicked: detailView._sortAscending = !detailView._sortAscending

                        ToolTip.visible: containsMouse
                        ToolTip.delay: 600
                        ToolTip.text: detailView._sortAscending ? KisaruI18n.t("sort.ascending") : KisaruI18n.t("sort.descending")
                    }
                }
            }

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1; color: Colors.outline_variant; opacity: 0.3
            }
        }

        // ── Chapter list ──────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true
            Rectangle { anchors.fill: parent; color: Colors.background }

            // Loading overlay
            SkeletonList {
                anchors.fill: parent; z: 5
                anchors.rightMargin: Style.space(ScrollMetrics.LANE)
                active: Manga.isFetchingDetail
                rowHeight: 58
            }

            ListView {
                id: chapterList
                anchors.fill: parent; clip: true
                // One gutter with the top zone (§32.1).
                anchors.leftMargin: Gutter.left
                anchors.rightMargin: Gutter.right
                boundsBehavior: Flickable.StopAtBounds
                model: detailView._processedGroups   // ← filtered + sorted

                // The badge column's width: the widest pill this list can show,
                // so every title starts on the same x (2026-11-27).
                BadgeColumn {
                    id: chapterBadges
                    labels: detailView._processedGroups.map(function(group) {
                        return detailView.badgeLabel(group.chapter)
                    })
                    fontFamily: detailView.fontBody
                }

                // The model arrives after the click that asked for a jump.
                onCountChanged: detailView._applyPendingJump()


                delegate: ClickableRect {
                    id: chapterRowAreaRect
                    width: chapterList.width; height: 58

                    // One row per chapter: `_group` is the chapter and
                    // `_version` the upload it opens by default.
                    readonly property var _group: modelData
                    readonly property var _version: modelData.primary
                    readonly property bool _hasVersions: modelData.versions.length > 1
                    readonly property var _libEntry: Manga.visibleEntry()
                    readonly property bool isLastRead:
                        _libEntry !== null && _libEntry !== undefined
                        && (_libEntry.lastReadChapterId === _version.id
                            || Chapters.sameChapter(_group.chapter,
                                 Chapters.canonicalNumber(Manga.chapterGroups,
                                                          _libEntry.lastReadChapterNum)))
                    readonly property bool _hideDownloads:
                        Privacy.locked && Manga.isHiddenLibraryEntry(Manga.libraryEntryId())
                    readonly property var _dlState: _hideDownloads
                        ? ({ kind: "idle", done: 0, total: 0, error: "" })
                        : Manga.chapterGroupDownloadState(_group)

                    color: isLastRead
                        ? Style.selectedFillFor(Colors.primary)
                        : (chapterRowAreaRect.pressed
                            ? Colors.surface_container_high
                            : (chapterRowAreaRect.hovered ? Colors.surface_container : Colors.clear(Colors.surface_container)))
                    Behavior on color { ColorAnimation { duration: Motion.fast } }

                    Rectangle {
                        anchors {
                            bottom: parent.bottom
                            left: parent.left; right: parent.right
                            // Starts on the badge column's left edge and ends on
                            // the content's right edge: one inset with the fill's
                            // content (owner, 2026-11-27).
                            leftMargin: Style.space(ListBadge.ROW_INSET)
                            rightMargin: Style.space(ListBadge.ROW_INSET)
                        }
                        height: 1; color: Colors.outline_variant; opacity: 0.25
                    }

                    RowLayout {
                        anchors { fill: parent; leftMargin: Style.space(ListBadge.ROW_INSET); rightMargin: Style.space(ListBadge.ROW_INSET) }
                        spacing: Style.spacing.xxxl

                        // Chapter number pill, in the list's fixed badge column.
                        ListBadge {
                            label: detailView.badgeLabel(chapterRowAreaRect._group.chapter)
                            active: isLastRead
                            fontFamily: detailView.fontBody
                            columnWidth: chapterBadges.columnWidth
                        }

                        Column {
                            Layout.fillWidth: true; spacing: Style.spacing.xs

                            Text {
                                width: parent.width
                                text: chapterRowAreaRect._version.title
                                    || KisaruI18n.t("chapter", { 1: detailView.formatChapter(chapterRowAreaRect._version.chapter) })
                                font.family: detailView.fontBody
                                font.pixelSize: Style.font.body; color: Colors.on_surface; elide: Text.ElideRight
                            }
                            // With versions the line names the upload that will
                            // open: its own number and its day-first date.
                            Text {
                                text: chapterRowAreaRect._hasVersions
                                    ? KisaruI18n.t("chapter", { 1: detailView.formatChapter(chapterRowAreaRect._version.chapter) })
                                      + (Chapters.chapterDateLabel(chapterRowAreaRect._version.publishAt) !== ""
                                          ? " · " + Chapters.chapterDateLabel(chapterRowAreaRect._version.publishAt)
                                          : "")
                                    : detailView.formatDate(chapterRowAreaRect._version.publishAt)
                                font.family: detailView.fontBody
                                font.pixelSize: Style.font.caption; color: Colors.on_surface_variant
                                opacity: 0.55; font.letterSpacing: 0.3
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }

                        // Versions chip: only when the source listed the same
                        // chapter twice. It is a button (owner, 2026-11-27: it
                        // read as a static label) in the same box as the meta
                        // bar's Folder button, with the chevron that says it
                        // opens something. Behaviour is unchanged: same picker.
                        ClickableRect {
                            id: versionsChip
                            visible: chapterRowAreaRect._hasVersions
                            implicitWidth: versionChipLabel.implicitWidth + 2 * Style.spacing.controlPaddingX
                            height: Style.space(24)
                            radius: Style.cornerRadius
                            color: versionsChip.hovered
                                ? Colors.surface_container_high
                                : Colors.clear(Colors.surface_container)
                            border.color: Colors.outline_variant
                            border.width: Style.spacing.hairline
                            cursorShape: Qt.PointingHandCursor
                            Behavior on color { ColorAnimation { duration: Motion.fast } }

                            StyledText {
                                id: versionChipLabel
                                anchors.centerIn: parent
                                text: KisaruI18n.tn("versions.count", chapterRowAreaRect._group.versions.length) + " ▾"
                                font.family: detailView.fontBody
                                font.pixelSize: Style.font.caption
                                color: Colors.on_surface
                            }
                            onClicked: detailView.openVersions(chapterRowAreaRect._group)
                        }

                        // Download button / progress / downloaded mark
                        Item {
                            id: dlControl
                            visible: !chapterRowAreaRect._hideDownloads
                            readonly property string kind: chapterRowAreaRect._dlState.kind
                            readonly property bool busyOther: kind === "idle" && Manga.isDownloadBusy
                            readonly property string glyph: kind === "downloaded"
                                ? "✓"
                                : (kind === "error" ? "!" : "↓")
                            implicitWidth: kind === "downloading" && chapterRowAreaRect._dlState.total > 0
                                ? Math.max(Style.space(34), dlProgressLabel.implicitWidth + Style.space(12))
                                : Style.space(32)
                            implicitHeight: Style.space(32)

                            Rectangle {
                                anchors.fill: parent
                                radius: Style.cornerRadius
                                color: dlControl.kind === "downloaded"
                                    ? Colors.withAlpha(Colors.primary, 0.14)
                                    : (dlControl.kind === "error"
                                        ? Colors.withAlpha(Colors.error, 0.14)
                                        : (dlArea.containsMouse && !dlControl.busyOther
                                            ? Colors.surface_container_high : Colors.clear(Colors.surface_container_high)))
                                Behavior on color { ColorAnimation { duration: Motion.fast } }
                            }

                            Spinner {
                                anchors.centerIn: parent
                                visible: dlControl.kind === "downloading" && chapterRowAreaRect._dlState.total === 0
                                width: Style.space(16)
                                border.width: 2
                                border.color: Colors.withAlpha(Colors.primary, 0.2)
                                arcColor: Colors.primary
                                duration: Motion.loop
                            }

                            StyledText {
                                id: dlProgressLabel
                                anchors.centerIn: parent
                                visible: dlControl.kind === "downloading" && chapterRowAreaRect._dlState.total > 0
                                text: chapterRowAreaRect._dlState.done + "/" + chapterRowAreaRect._dlState.total
                                font.family: detailView.fontBody
                                font.pixelSize: Style.font.caption
                                font.bold: true
                                color: Colors.primary
                            }

                            StyledText {
                                anchors.centerIn: parent
                                visible: dlControl.kind !== "downloading"
                                text: dlControl.glyph
                                font.family: detailView.fontBody
                                font.pixelSize: Style.font.body
                                font.bold: true
                                color: dlControl.kind === "downloaded"
                                    ? Colors.primary
                                    : (dlControl.kind === "error"
                                        ? Colors.error
                                        : Colors.on_surface_variant)
                                opacity: dlControl.busyOther ? 0.35 : 0.9
                            }

                            MouseArea {
                                id: dlArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: (dlControl.kind === "idle" || dlControl.kind === "error") && !dlControl.busyOther
                                    ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: function(mouse) {
                                    mouse.accepted = true
                                    if ((dlControl.kind === "idle" || dlControl.kind === "error") && !dlControl.busyOther)
                                        Manga.startDownload(chapterRowAreaRect._version)
                                }

                                ToolTip.visible: containsMouse
                                ToolTip.delay: 500
                                ToolTip.text: {
                                    if (dlControl.kind === "downloaded") return KisaruI18n.t("manga.downloaded")
                                    if (dlControl.kind === "downloading") {
                                        return chapterRowAreaRect._dlState.total > 0
                                            ? KisaruI18n.t("manga.downloading", {
                                                1: chapterRowAreaRect._dlState.done,
                                                2: chapterRowAreaRect._dlState.total
                                            })
                                            : KisaruI18n.t("manga.download")
                                    }
                                    if (dlControl.kind === "error") return KisaruI18n.t("manga.downloadError")
                                    if (dlControl.busyOther) return KisaruI18n.t("manga.downloadBusy")
                                    return KisaruI18n.t("manga.download")
                                }
                            }
                        }

                        Text {
                            text: "›"; font.pixelSize: 20; color: Colors.outline // style-ignore — bespoke size
                            opacity: chapterRowAreaRect.hovered ? 0.9 : 0.4
                            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                        }
                    }

                    onClicked: {
                        if (Manga.openChapter(chapterRowAreaRect._version))
                            detailView.chapterSelected(chapterRowAreaRect._version.id)
                    }
                }
            }
        }
    }

    Connections {
        target: Manga
        function onCurrentMangaChanged() { detailView._simulatedSaved = false }
    }

    FolderPicker {
        id: folderPicker
        anchors.fill: parent
        // A hidden title may be filed into a hidden folder at once, with no
        // word; a visible one keeps the old rule. See services/detail_hide.js.
        folders: DetailHide.pickerShowsHidden({
                locked: Privacy.locked,
                hidden: detailView._rawEntry !== null && detailView._rawEntry.hidden === true
            })
            ? Organizer.folders("manga")
            : Organizer.folders("manga").filter(function(folder) { return !folder.hidden })
        current: detailView._folderValue
        bodyFont: detailView.fontBody
        onChosen: function(folderId) { Manga.setFolder(Manga.libraryEntryId(), folderId) }
        onCreateRequested: folderPrompt.openText(KisaruI18n.t("folder.create"), "")
    }

    VersionPicker {
        id: versionPicker
        anchors.fill: parent
        bodyFont: detailView.fontBody
        onChosen: function(versionId) { detailView.chooseVersion(versionId) }
        onDownloadRequested: function(versionId) { detailView.downloadVersion(versionId) }
        onClosed: {
            versionPicker.rows = []
            detailView._pickerGroup = null
        }
    }

    FolderPrompt {
        id: folderPrompt
        anchors.fill: parent
        onAccepted: function(value) {
            var folderId = Organizer.addFolder("manga", value)
            if (folderId !== "") {
                Manga.setFolder(Manga.libraryEntryId(), folderId)
            }
        }
    }
}
