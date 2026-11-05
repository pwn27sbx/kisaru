import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.app
import qs.Commons
import qs.services
import qs.components
import "../../../services/library_filter.js" as LibraryFilter
import "../../../services/library_view.js" as LibraryViewJs
import "../../../services/folder_cards.js" as FolderCards
import "../../../services/list_metrics.js" as ListMetrics

Item {
    id: libraryView

    // The header's local search. It crosses every visible title, whatever
    // folder it lives in, so it starts from the whole visible shelf.
    property string query: ""
    property string activeFolder: ""

    readonly property var _allVisible: Anime.visibleEntries("")
    readonly property var _folders:
        LibraryViewJs.visibleFolders(Organizer.folders("anime"), Privacy.locked)
    readonly property var _split:
        FolderCards.partition(_allVisible, LibraryViewJs.folderIdOf)
    readonly property var _searchResults:
        FolderCards.searchTitles(_allVisible, query, LibraryFilter.fold,
            function(entry) { return entry.englishName || entry.name || "" })
    readonly property var _rootItems:
        FolderCards.rootItems(_folders, _split.folderless, _split.byFolder,
            function(entry) { return entry.thumbnail || "" })
    readonly property var _folderEntries:
        (!libraryView.folderOpen) ? [] : (_split.byFolder[activeFolder] || [])
    readonly property bool _searching: query.trim() !== ""
    readonly property var _titleList:
        _searching ? _searchResults
            : (libraryView.folderOpen ? _folderEntries : _split.folderless)

    readonly property var model: {
        if (_searching || libraryView.folderOpen) {
            var titles = []
            for (var i = 0; i < _titleList.length; i++)
                titles.push({ kind: "title", entry: _titleList[i] })
            return titles
        }
        var items = _rootItems.slice()
        items.push({ kind: "create" })
        return items
    }

    readonly property bool activeFolderHidden:
        activeFolder !== "" && Organizer.isHidden("anime", activeFolder)
    // Closed off only while locked and hidden or unresolved: a visible folder
    // opens while locked and without a secret, and an unresolved one fails
    // closed. The hidden folder itself is only reachable while unlocked.
    readonly property bool activeFolderLockedOut:
        LibraryViewJs.lockedOut(activeFolder, Organizer.folders("anime"),
            { loaded: Organizer.loaded, locked: Privacy.locked })
    readonly property string activeFolderName:
        (activeFolder === "" || activeFolderLockedOut) ? "" : ((Organizer.folder("anime", activeFolder) || {}).name || "")
    readonly property bool folderOpen: activeFolder !== "" && !_searching && !activeFolderLockedOut

    readonly property string fontDisplay: Style.font.family
    readonly property string fontBody:    Style.font.family

    // Each panel remembers its own layout (owner, round 6).
    readonly property bool listMode: UiPrefs.viewModeFor("anime") === "list"

    signal animeSelected(var show)
    signal secretEntered()

    onQueryChanged: {
        if (query.trim() !== "" && libraryView.activeFolder !== "")
            libraryView.activeFolder = ""
        if (!Privacy.configured) return
        Privacy.consider(query, function(code) {
            if (code === 0) libraryView.secretEntered()
        })
    }

    property string _promptAction: ""
    property string _promptFolder: ""

    function _newFolder() {
        _promptAction = "create"
        _promptFolder = ""
        folderPrompt.openText(I18n.t("folder.create"), "")
    }

    function _renameFolder(folderId) {
        if (activeFolderLockedOut) return
        var folder = Organizer.folder("anime", folderId)
        _promptAction = "rename"
        _promptFolder = folderId
        folderPrompt.openText(I18n.t("folder.rename"), folder ? folder.name : "")
    }

    function _confirmDelete(folderId) {
        if (activeFolderLockedOut) return
        var folder = Organizer.folder("anime", folderId)
        if (!folder) return
        _promptAction = "delete"
        _promptFolder = folderId
        folderPrompt.openConfirm(I18n.t("folder.delete"),
            folder.hidden ? I18n.t("folder.deleteHidden") : I18n.t("folder.deleteMessage"))
    }

    function _acceptPrompt(value) {
        if (libraryView._promptAction === "create") {
            Organizer.addFolder("anime", value)
        } else if (libraryView._promptAction === "rename") {
            Organizer.renameFolder("anime", libraryView._promptFolder, value)
        } else if (libraryView._promptAction === "delete") {
            if (libraryView.activeFolder === libraryView._promptFolder)
                libraryView.activeFolder = ""
            Anime.deleteFolder(libraryView._promptFolder)
        }
        libraryView._promptAction = ""
        libraryView._promptFolder = ""
    }

    function _pruneFolder() {
        if (activeFolder !== "" && Organizer.folder("anime", activeFolder) === null)
            activeFolder = ""
    }

    function _toggleHidden() {
        if (activeFolder === "" || Privacy.locked || !Privacy.configured) return
        Organizer.setHidden("anime", activeFolder, !activeFolderHidden)
    }

    function _showFor(entry) {
        return {
            id:          entry.id,
            name:        entry.name,
            englishName: entry.englishName,
            nativeName:  entry.nativeName  || "",
            thumbnail:   entry.thumbnail,
            score:       entry.score,
            type:        entry.type        || "",
            episodeCount: entry.episodeCount || "",
            availableEpisodes: entry.availableEpisodes || { sub: 0, dub: 0, raw: 0 },
            season:      entry.season      || null
        }
    }

    Rectangle { anchors.fill: parent; color: Colors.background }

    ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(0)

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(40)
            Layout.leftMargin: Gutter.left + Gutter.ink
            Layout.rightMargin: Gutter.right + Gutter.ink
            spacing: Style.spacing.sm
            visible: libraryView.folderOpen

            ClickableRect {
                Layout.preferredWidth: Style.space(28)
                Layout.preferredHeight: Style.space(28)
                color: hovered ? Colors.surface_container_high : "transparent"
                radius: Style.cornerRadius
                StyledText {
                    anchors.centerIn: parent
                    text: "←"
                    font.family: libraryView.fontBody
                    font.pixelSize: Style.font.iconLarge
                    color: Colors.on_surface_variant
                }
                onClicked: libraryView.activeFolder = ""
            }

            StyledText {
                Layout.fillWidth: true
                text: libraryView.activeFolderName
                font.family: libraryView.fontBody
                font.pixelSize: Style.font.body
                font.bold: true
                color: Colors.on_surface
                elide: Text.ElideRight
            }

            StyledText {
                text: I18n.tn("folder.count", libraryView._folderEntries.length)
                font.family: libraryView.fontBody
                font.pixelSize: Style.font.caption
                color: Colors.on_surface_variant
            }

            Item { Layout.fillWidth: true }

            ClickableRect {
                visible: Privacy.configured && !Privacy.locked
                Layout.preferredWidth: Style.space(28)
                Layout.preferredHeight: Style.space(28)
                color: hovered ? Colors.surface_container_high : "transparent"
                radius: Style.cornerRadius
                MaterialIcon {
                    anchors.centerIn: parent
                    text: libraryView.activeFolderHidden ? "󰈈" : "󰈉"
                    font.pixelSize: Style.font.bodySmall
                    color: libraryView.activeFolderHidden ? Colors.primary : Colors.on_surface_variant
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: libraryView._toggleHidden()
                    ToolTip.visible: containsMouse
                    ToolTip.delay: 600
                    ToolTip.text: libraryView.activeFolderHidden
                        ? I18n.t("folder.show") : I18n.t("folder.hide")
                }
            }

            ClickableRect {
                visible: !activeFolderLockedOut
                Layout.preferredWidth: Style.space(28)
                Layout.preferredHeight: Style.space(28)
                color: hovered ? Colors.surface_container_high : "transparent"
                radius: Style.cornerRadius
                MaterialIcon {
                    anchors.centerIn: parent
                    text: "󰏫"
                    font.pixelSize: Style.font.bodySmall
                    color: Colors.on_surface_variant
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: libraryView._renameFolder(libraryView.activeFolder)
                    ToolTip.visible: containsMouse
                    ToolTip.delay: 600
                    ToolTip.text: I18n.t("folder.rename")
                }
            }

            ClickableRect {
                visible: !activeFolderLockedOut
                Layout.preferredWidth: Style.space(28)
                Layout.preferredHeight: Style.space(28)
                color: hovered ? Colors.surface_container_high : "transparent"
                radius: Style.cornerRadius
                MaterialIcon {
                    anchors.centerIn: parent
                    text: "󰆴"
                    font.pixelSize: Style.font.bodySmall
                    color: Colors.error
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: libraryView._confirmDelete(libraryView.activeFolder)
                    ToolTip.visible: containsMouse
                    ToolTip.delay: 600
                    ToolTip.text: I18n.t("folder.delete")
                }
            }
        }

        SkeletonGrid {
            Layout.fillWidth: true; Layout.fillHeight: true
            Layout.leftMargin: Gutter.left
            Layout.rightMargin: Gutter.right
            visible: !libraryView.listMode && !Anime.libraryLoaded
            active: !libraryView.listMode && !Anime.libraryLoaded
            padding: Style.space(0)
            cellHeight: CardMetrics.cellHeight(width / CardMetrics.columns, Style.space(28))
            footerHeight: 28
        }

        SkeletonList {
            Layout.fillWidth: true; Layout.fillHeight: true
            Layout.leftMargin: Gutter.left
            Layout.rightMargin: Gutter.right
            visible: libraryView.listMode && !Anime.libraryLoaded
            active: libraryView.listMode && !Anime.libraryLoaded
            rowHeight: Style.space(ListMetrics.ROW_HEIGHT_BASE)
            cover: true
            inset: Gutter.ink
        }

        GridView {
            id: libGrid
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: Anime.libraryLoaded && !libraryView.listMode
            topMargin: Style.spacing.xl; leftMargin: Gutter.left; bottomMargin: Style.spacing.xl
            rightMargin: Gutter.right
            cellWidth: (width - leftMargin - rightMargin) / CardMetrics.columns
            cellHeight: CardMetrics.cellHeight(cellWidth, Style.space(28))
            clip: true; boundsBehavior: Flickable.StopAtBounds
            model: libraryView.model

            delegate: Item {
                width: libGrid.cellWidth
                height: libGrid.cellHeight

                readonly property var item: modelData
                readonly property var entry: item.kind === "title" ? item.entry : null
                readonly property var folderData: item.kind === "folder" ? item : null

                CoverCard {
                    visible: entry !== null
                    anchors.fill: parent
                    source: entry ? (entry.thumbnail || "") : ""
                    title: entry ? (entry.englishName || entry.name || "") : ""
                    bodyFont: libraryView.fontBody
                    footerHeight: 28
                    cornerText: entry && entry.score !== null && entry.score !== undefined
                        ? "★ " + Number(entry.score || 0).toFixed(1) : ""
                    cornerAccent: true
                    bookmarked: entry ? !!entry.bookmarked : false

                    CoverProgressBar {
                        height: 28
                        rowSpacing: Style.space(5)
                        bodyFont: libraryView.fontBody
                        started: entry ? entry.lastWatchedEpNum : ""
                        label: entry && entry.lastWatchedEpNum
                            ? I18n.t("ep", { 1: entry.lastWatchedEpNum })
                            : I18n.t("state.notStarted")
                    }

                    onClicked: {
                        if (!entry) return
                        libraryView.animeSelected(libraryView._showFor(entry))
                    }
                }

                FolderCard {
                    visible: folderData !== null
                    anchors.fill: parent
                    covers: folderData ? folderData.covers : []
                    name: folderData ? folderData.name : ""
                    count: folderData ? folderData.count : 0
                    hidden: folderData ? folderData.hidden : false
                    bodyFont: libraryView.fontBody
                    onClicked: {
                        if (folderData) libraryView.activeFolder = folderData.id
                    }
                }

                CreateFolderCard {
                    visible: item.kind === "create"
                    anchors.fill: parent
                    bodyFont: libraryView.fontBody
                    onClicked: libraryView._newFolder()
                }
            }
        }

        ListView {
            id: libRows
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: Anime.libraryLoaded && libraryView.listMode
            topMargin: Style.spacing.xl
            bottomMargin: Style.spacing.xl
            leftMargin: Gutter.left
            rightMargin: Gutter.right
            clip: true; boundsBehavior: Flickable.StopAtBounds
            model: libraryView.model

            delegate: Item {
                readonly property var item: modelData
                readonly property var entry: item.kind === "title" ? item.entry : null
                readonly property var folderData: item.kind === "folder" ? item : null
                width: libRows.width - libRows.leftMargin - libRows.rightMargin
                height: Style.space(ListMetrics.ROW_HEIGHT_BASE)

                ListRow {
                    visible: entry !== null
                    anchors.fill: parent
                    source: entry ? (entry.thumbnail || "") : ""
                    title: entry ? (entry.englishName || entry.name || "") : ""
                    bodyFont: libraryView.fontBody
                    inset: Gutter.ink
                    score: {
                        if (!entry) return ""
                        var value = Number(entry.score)
                        return (entry.score !== null && entry.score !== undefined
                                && isFinite(value)) ? "★ " + value.toFixed(1) : ""
                    }
                    meta: ""
                    progress: entry && entry.lastWatchedEpNum
                        ? I18n.t("ep", { 1: entry.lastWatchedEpNum })
                        : I18n.t("state.notStarted")
                    progressActive: entry ? !!entry.lastWatchedEpNum : false

                    onClicked: {
                        if (!entry) return
                        libraryView.animeSelected(libraryView._showFor(entry))
                    }
                }

                FolderListRow {
                    visible: folderData !== null
                    anchors.fill: parent
                    covers: folderData ? folderData.covers : []
                    name: folderData ? folderData.name : ""
                    count: folderData ? folderData.count : 0
                    hidden: folderData ? folderData.hidden : false
                    bodyFont: libraryView.fontBody
                    inset: Gutter.ink
                    onClicked: {
                        if (folderData) libraryView.activeFolder = folderData.id
                    }
                }

                CreateFolderCard {
                    visible: item.kind === "create"
                    anchors.fill: parent
                    row: true
                    bodyFont: libraryView.fontBody
                    onClicked: libraryView._newFolder()
                }
            }
        }
    }

    FolderPrompt {
        id: folderPrompt
        anchors.fill: parent
        onAccepted: function(value) { libraryView._acceptPrompt(value) }
    }

    Connections {
        target: Privacy
        function onLockedChanged() {
            if (Privacy.locked && libraryView.activeFolderLockedOut)
                libraryView.activeFolder = ""
        }
    }

    Connections {
        target: Organizer
        function onDataChanged() { libraryView._pruneFolder() }
    }
}
