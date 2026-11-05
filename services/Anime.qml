pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "anime_links.js" as AnimeLinks
import "app_paths.js" as Paths
import "library_view.js" as LibraryViewJs

Singleton {
    id: root

    readonly property string apiUrl: "http://127.0.0.1:5050"

    property list<var> animeList: []
    property bool isFetchingAnime: false
    property string animeError: ""
    property bool hasMoreAnime: false
    property int popularPage: 1
    property int latestPage: 1
    property string currentSearchText: ""
    // The audio mode is a user preference now, not a per-launch default: it is
    // read from settings.json and written back by setMode (owner, round 6).
    property string currentMode: UiPrefs.animeMode
    property string currentCountry: "ALL"
    property string currentView: ""

    property var currentAnime: null
    property bool isFetchingDetail: false
    property string detailError: ""

    property list<var> streamLinks: []
    property var selectedLink: null
    property bool isFetchingLinks: false
    property string linksError: ""
    property string currentEpisode: ""
    property string currentSubtitleLabel: ""

    // ── Library ───────────────────────────────────────────────────────────────
    // Each entry: { id, name, englishName, thumbnail, score,
    //               lastWatchedEpId, lastWatchedEpNum,
    //               bookmarked, addedAt }
    property list<var> libraryList: []
    property bool libraryLoaded: false

    // The library lives under the project's name now; the inherited neutral
    // folder is read while it is the only one that exists (owner decision D6),
    // so the list never looks empty during the migration window.
    readonly property string _dataHome:
        Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")
    readonly property string _newLibraryPath: Paths.libraryPath(root._dataHome, "anime", false)
    readonly property string _oldLibraryPath: Paths.legacyLibraryPath(root._dataHome, "anime")
    property bool _newLibrarySeen: false
    property bool _oldLibrarySeen: false
    property bool _oldLibraryChecked: false
    readonly property string _libraryPath:
        Paths.resolvePath(root._newLibraryPath, root._oldLibraryPath,
                          root._newLibrarySeen, root._oldLibrarySeen)

    FileView {
        id: libraryFile
        path: root._libraryPath
        onLoaded: {
            root._newLibrarySeen = root._libraryPath === root._newLibraryPath
            try {
                var data = JSON.parse(libraryFile.text())
                root.libraryList = Array.isArray(data) ? data : []
            } catch (e) {
                console.warn("[ServiceAnime] library parse error:", e)
                root.libraryList = []
            }
            root.libraryLoaded = true
            console.log("[ServiceAnime] Library loaded —", root.libraryList.length, "entries")
        }
        onLoadFailed: {
            // Missing at the new path: the probe flips _libraryPath to the
            // inherited file and this read runs again there.
            if (root._oldLibrarySeen && root._libraryPath !== root._oldLibraryPath)
                return
            if (!root._oldLibraryChecked)
                return
            root.libraryList = []
            root.libraryLoaded = true
            console.log("[ServiceAnime] No library file found, starting fresh")
        }
    }

    // Does the inherited library file exist? Read-only, never written.
    FileView {
        id: oldLibraryProbe
        path: root._oldLibraryPath
        onLoaded: {
            root._oldLibrarySeen = true
            root._oldLibraryChecked = true
            root._finishWhenProbeFindsNothing()
        }
        onLoadFailed: {
            root._oldLibrarySeen = false
            root._oldLibraryChecked = true
            root._finishWhenProbeFindsNothing()
        }
    }

    // The main read can fail before the probe settles, and if the probe then
    // finds no inherited file the path does not change, so no second read ever
    // comes: this is what turns that race into the normal empty state instead
    // of a list that never finishes loading (review finding R3-ProbeRace).
    function _finishWhenProbeFindsNothing() {
        if (!root._oldLibraryChecked || root.libraryLoaded)
            return
        if (root._libraryPath !== root._newLibraryPath)
            return          // a reload against the inherited file is coming
        root.libraryList = []
        root.libraryLoaded = true
        console.log("[ServiceAnime] No library file found, starting fresh")
    }

    FileView {
        id: libraryWriter
        path: root._libraryPath
    }

    function _saveLibrary() {
        libraryWriter.setText(JSON.stringify(root.libraryList, null, 2))
    }

    // ── Folders and private mode ─────────────────────────────────────────────
    readonly property var _folders: Organizer.folders("anime")

    function _viewOptions(folderId) {
        return {
            loaded: Organizer.loaded,
            locked: Privacy.locked,
            folder: folderId || ""
        }
    }

    function visibleEntries(folderId) {
        return LibraryViewJs.visibleEntries(root.libraryList, root._folders,
                                            root._viewOptions(folderId))
    }

    function visibleCount() {
        return LibraryViewJs.visibleCount(root.libraryList, root._folders,
                                          root._viewOptions())
    }

    function isVisibleEntry(entry) {
        return LibraryViewJs.isVisible(entry, root._folders, root._viewOptions())
    }

    function visibleEntryId() {
        if (!currentAnime) return ""
        var id = currentAnime.id
        var entry = root.getLibraryEntry(id)
        return entry && root.isVisibleEntry(entry) ? id : ""
    }

    function visibleEntry() {
        var id = root.visibleEntryId()
        return id === "" ? null : root.getLibraryEntry(id)
    }

    function isHiddenLibraryEntry(entryId) {
        var entry = root.getLibraryEntry(entryId)
        return !!entry && Organizer.isHidden("anime", entry.folder || "")
    }

    function setFolder(entryId, folderId) {
        root.libraryList = root.libraryList.map(function(e) {
            if (e.id !== entryId) return e
            return Object.assign({}, e, { folder: folderId || "" })
        })
        _saveLibrary()
    }

    function deleteFolder(folderId) {
        if (!Organizer.deleteFolder("anime", folderId)) return false
        root.libraryList = LibraryViewJs.entriesWithoutFolder(root.libraryList, folderId)
        _saveLibrary()
        return true
    }

    function addToLibrary(anime) {
        if (isInLibrary(anime.id)) return
        var entry = {
            id:                 anime.id,
            name:               anime.name               || "",
            englishName:        anime.englishName         || anime.name || "",
            thumbnail:          anime.thumbnail           || "",
            score:              anime.score               || null,
            lastWatchedEpId:    "",
            lastWatchedEpNum:   "",
            bookmarked:         true,
            addedAt:            new Date().toISOString()
        }
        root.libraryList = [entry, ...root.libraryList]
        _saveLibrary()
        console.log("[ServiceAnime] Added to library")
    }

    function removeFromLibrary(animeId) {
        root.libraryList = root.libraryList.filter(function(e) { return e.id !== animeId })
        _saveLibrary()
        console.log("[ServiceAnime] Removed from library")
    }

    function isInLibrary(animeId) {
        return root.libraryList.some(function(e) { return e.id === animeId })
    }

    function isBookmarked(animeId) {
        var entry = getLibraryEntry(animeId)
        return entry ? entry.bookmarked : false
    }

    function toggleBookmark(anime) {
        if (!isInLibrary(anime.id)) {
            addToLibrary(anime)
            return
        }
        root.libraryList = root.libraryList.map(function(e) {
            if (e.id !== anime.id) return e
            return Object.assign({}, e, { bookmarked: !e.bookmarked })
        })
        _saveLibrary()
    }

    function updateLastWatched(animeId, episodeId, episodeNum) {
        if (!isInLibrary(animeId)) return
        // A hidden title must not write progress while the mode is locked.
        var current = getLibraryEntry(animeId)
        if (current && Privacy.locked && Organizer.isHidden("anime", current.folder || ""))
            return
        root.libraryList = root.libraryList.map(function(e) {
            if (e.id !== animeId) return e
            return Object.assign({}, e, {
                lastWatchedEpId:  episodeId,
                lastWatchedEpNum: String(episodeNum)
            })
        })
        _saveLibrary()
        console.log("[ServiceAnime] Last watched updated")
    }

    function getLibraryEntry(animeId) {
        for (var i = 0; i < root.libraryList.length; i++) {
            if (root.libraryList[i].id === animeId) return root.libraryList[i]
        }
        return null
    }

    function bookmarkedList() {
        return root.libraryList.filter(function(e) { return e.bookmarked })
    }

    Component.onCompleted: libraryFile.reload()

    property bool serverReady: false

    Process {
        id: serverProcess
        command: [ReaderEnv.animePython, ReaderEnv.scripts + "/anime_server.py"]
        running: true
        onExited: (code) => {
            console.warn("[ServiceAnime] Server exited with code", code, "— restarting")
            root.serverReady = false
            restartTimer.start()
        }
    }

    // A pause before restarting, so a server that can't start (port taken,
    // venv missing) isn't respawned in a tight loop.
    Timer {
        id: restartTimer
        interval: 3000
        onTriggered: serverProcess.running = true
    }

    HealthPoller {
        id: healthPoller
        url: root.apiUrl
        onReady: {
            root.serverReady = true
            console.log("[ServiceAnime] Backend ready at", root.apiUrl)
            fetchPopular()
        }
    }



    function fetchPopular(reset) {
        if (isFetchingAnime) return
        if (reset === undefined || reset) {
            animeList = []
            popularPage = 1
        }
        currentView = "popular"
        currentSearchText = ""
        isFetchingAnime = true
        animeError = ""

        const url = root.apiUrl + "/popular?size=20&page=" + popularPage + "&date_range=1"
        Http.get(url, function(err, body) {
            if (err) { animeError = I18n.t("error.request", { 1: err }); isFetchingAnime = false; return }
            _parsePopularResults(body)
        })
    }

    function _parsePopularResults(json) {
        try {
            const data = JSON.parse(json)
            if (data.error) { animeError = data.error; isFetchingAnime = false; return }

            const items = data.shows || []
            animeList = [...animeList, ...items.map(function(s) {
                return _normaliseShow(s)
            })]

            // popular endpoint has a fixed total of 500, paged by `size`
            const fetched = popularPage * 20
            hasMoreAnime = fetched < (data.total || 0)
            animeError = ""
        } catch (e) {
            animeError = I18n.t("error.parse", { 1: e })
            console.error("[ServiceAnime]", e)
        }
        isFetchingAnime = false
    }

    function fetchLatest(reset) {
        if (isFetchingAnime) return
        if (reset === undefined || reset) {
            animeList = []
            latestPage = 1
        }
        currentView = "latest"
        currentSearchText = ""
        isFetchingAnime = true
        animeError = ""

        const url = root.apiUrl + "/latest?limit=26&page=" + latestPage
            + "&mode=" + currentMode
            + "&country=" + currentCountry
        Http.get(url, function(err, body) {
            if (err) { animeError = I18n.t("error.request", { 1: err }); isFetchingAnime = false; return }
            _parseLatestResults(body)
        })
    }

    function _parseLatestResults(json) {
        try {
            const data = JSON.parse(json)
            if (data.error) { animeError = data.error; isFetchingAnime = false; return }

            const items = data.shows || []
            animeList = [...animeList, ...items.map(function(s) {
                return _normaliseShow(s)
            })]

            const fetched = latestPage * 26
            hasMoreAnime = fetched < (data.total || 0)
            animeError = ""
        } catch (e) {
            animeError = I18n.t("error.parse", { 1: e })
            console.error("[ServiceAnime]", e)
        }
        isFetchingAnime = false
    }

    function searchAnime(query, reset) {
        if (isFetchingAnime) return
        if (reset === undefined || reset) { animeList = [] }
        currentView = "search"
        currentSearchText = query
        isFetchingAnime = true
        animeError = ""

        const url = root.apiUrl + "/search?q=" + encodeURIComponent(query)
            + "&mode=" + currentMode
        Http.get(url, function(err, body) {
            if (err) { animeError = I18n.t("error.request", { 1: err }); isFetchingAnime = false; return }
            _parseSearchResults(body)
        })
    }

    function _parseSearchResults(json) {
        try {
            const data = JSON.parse(json)
            if (data.error) { animeError = data.error; isFetchingAnime = false; return }

            const items = data.results || []
            animeList = [...animeList, ...items.map(function(s) {
                return _normaliseShow(s)
            })]

            // search endpoint returns all matches at once
            hasMoreAnime = false
            animeError = ""
        } catch (e) {
            animeError = I18n.t("error.parse", { 1: e })
            console.error("[ServiceAnime]", e)
        }
        isFetchingAnime = false
    }

    function fetchNextPage() {
        if (!hasMoreAnime || isFetchingAnime) return
        if (currentView === "popular") {
            popularPage++
            fetchPopular(false)
        } else if (currentView === "latest") {
            latestPage++
            fetchLatest(false)
        }
    }

    function _normaliseShow(s) {
        var avail = s.available_episodes || {}
        return {
            id:          s.id          || "",
            name:        s.name        || "",
            englishName: s.english_name || s.englishName || s.name || "",
            nativeName:  s.native_name  || s.nativeName  || "",
            thumbnail:   s.thumbnail   || "",
            score:       s.score       !== undefined ? s.score : null,
            type:        s.type        || "",
            episodeCount: s.episode_count || "",
            availableEpisodes: {
                sub: avail.sub || 0,
                dub: avail.dub || 0,
                raw: avail.raw || 0
            },
            // /popular extras
            views:       s.views       || null,
            // /latest extras
            season:      s.season      || null,
            lastEpisode: s.last_episode || null
        }
    }

    function fetchAnimeDetail(show) {
        if (isFetchingDetail) return
        isFetchingDetail = true
        currentAnime = null
        detailError = ""

        // Seed what we already know from the list card immediately
        currentAnime = Object.assign({}, show, { episodes: [] })

        const url = root.apiUrl + "/episodes?id=" + encodeURIComponent(show.id)
            + "&mode=" + currentMode
        Http.get(url, function(err, body) {
            if (err) { detailError = I18n.t("error.request", { 1: err }); isFetchingDetail = false; return }
            _parseAnimeDetail(show, body)
        })
    }

    function _parseAnimeDetail(show, json) {
        try {
            const data = JSON.parse(json)
            if (data.error) { detailError = data.error; isFetchingDetail = false; return }

            const eps = (data.episodes || []).map(function(epNum, idx) {
                return {
                    id:     show.id + "-" + epNum,   // synthetic id: showId-epNumber
                    number: epNum,
                    index:  idx
                }
            })

            currentAnime = Object.assign({}, show, {
                episodes: eps,
                episodeCount: data.count || eps.length
            })
            detailError = ""
        } catch (e) {
            detailError = I18n.t("error.parse", { 1: e })
            console.error("[ServiceAnime]", e)
        }
        isFetchingDetail = false
    }

    function clearDetail() {
        currentAnime = null
        detailError = ""
        clearStreamLinks()
    }

    function fetchStreamLinks(showId, episodeNum, quality) {
        if (isFetchingLinks) return
        isFetchingLinks = true
        streamLinks = []
        selectedLink = null
        linksError = ""
        currentEpisode = String(episodeNum)
        currentSubtitleLabel = ""

        const q = quality || "best"
        const url = root.apiUrl + "/links?id=" + encodeURIComponent(showId)
            + "&ep=" + encodeURIComponent(episodeNum)
            + "&mode=" + currentMode
            + "&quality=" + encodeURIComponent(q)
        Http.get(url, function(err, body) {
            if (err) { linksError = I18n.t("error.request", { 1: err }); isFetchingLinks = false; return }
            _parseStreamLinks(body)
        })
    }

    function _parseStreamLinks(json) {
        try {
            const parsed = AnimeLinks.parseStreamLinks(json)
            streamLinks = parsed.streamLinks
            selectedLink = parsed.selectedLink
            currentSubtitleLabel = parsed.subtitleLabel
            linksError = parsed.empty ? I18n.t("anime.noStream") : (parsed.error || "")
        } catch (e) {
            linksError = I18n.t("error.parse", { 1: e })
            console.error("[ServiceAnime]", e)
        }
        isFetchingLinks = false
    }

    function selectLink(link) {
        selectedLink = link
    }

    function clearStreamLinks() {
        streamLinks = []
        selectedLink = null
        linksError = ""
        currentEpisode = ""
    }

    function clearAnimeList() {
        animeList = []
        hasMoreAnime = false
        popularPage = 1
        latestPage = 1
        animeError = ""
    }

    function setMode(mode) {
        if (mode === currentMode) return
        currentMode = mode
        UiPrefs.setAnimeMode(mode)
        if (currentView === "popular")      fetchPopular(true)
        else if (currentView === "latest")  fetchLatest(true)
        else if (currentView === "search" && currentSearchText.length > 0)
            searchAnime(currentSearchText, true)
    }

    function setCountry(country) {
        if (country === currentCountry) return
        currentCountry = country
        if (currentView === "latest") fetchLatest(true)
    }
}
