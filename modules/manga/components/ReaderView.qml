import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.app
import qs.Commons
import qs.services
import qs.components
import "../../../components/wheel_scroll.js" as WheelScroll
import "../../../components/reader_scroll.js" as ReaderScroll
import "../../../services/scroll_metrics.js" as ScrollMetrics

Item {
    id: readerView

    // ── Exposed API ──────────────────────────────────────────────────────────
    readonly property string fontDisplay: Style.font.family
    readonly property string fontBody:    Style.font.family

    // Emitted when the user navigates back
    signal backRequested()

    // ── Internal state ───────────────────────────────────────────────────────
    property bool headerVisible: true


    // Called by the parent to reset state when re-entering this view
    function reset() {
        headerVisible = true
        _lastPage = 0
    }

    // A new chapter starts at page 1, whatever the previous one left behind.
    // It learns its own placeholder ratio (the last one stays as the first
    // guess) and its pages get a fresh automatic retry.
    Connections {
        target: Manga
        function onChapterPagesChanged() {
            readerView._lastPage = 0
            readerView._ratioLearned = false
            readerView._attempts = ({})
        }
    }

    // Tapping hides the header (tap again to bring it back). Leaving the reader
    // with it hidden and opening another chapter used to leave the chrome gone,
    // because the same instance is reused: any entry shows it again.
    onVisibleChanged: if (visible) headerVisible = true

    // ── Reading mat ──────────────────────────────────────────────────────────
    // The mat under the pages is the theme's ground, like the rest of Kisaru:
    // switching the Omarchy theme repaints the reader too.
    Rectangle { anchors.fill: parent; color: Colors.background }

    // ── Reader header ────────────────────────────────────────────────────────
    Rectangle {
        id: readerHeader
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 54
        color: Util.alpha(Colors.surface_container_low, 0.96)
        z: 10
        opacity: readerView.headerVisible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.slow; easing.type: Motion.easeOut } }

        // Bottom hairline
        Rectangle {
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 1
            color: Util.alpha(Colors.text, 0.07)
        }

        RowLayout {
            anchors { fill: parent; leftMargin: Style.spacing.md; rightMargin: Style.space(16) }
            spacing: Style.spacing.xxs

            // Back button
            Item {
                width: 44; height: 44

                Rectangle {
                    anchors.centerIn: parent
                    width: 34; height: 34; radius: Style.cornerRadius
                    color: readerBackArea.containsMouse
                        ? Util.alpha(Colors.text, 0.1)
                        : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.base } }
                }
                StyledText {
                    anchors.centerIn: parent
                    text: "←"
                    font.pixelSize: Style.font.iconLarge
                    color: Util.alpha(Colors.text, 0.7)
                }
                MouseArea {
                    id: readerBackArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        Manga.clearChapterPages()
                        readerView.backRequested()
                    }
                }
            }

            // Title
            StyledText {
                Layout.fillWidth: true
                text: Manga.currentManga ? Manga.currentManga.title : ""
                font.family: readerView.fontDisplay
                font.pixelSize: Style.font.subtitle
                color: Util.alpha(Colors.text, 0.85)
                elide: Text.ElideRight
            }

            // Page counter badge
            Rectangle {
                visible: Manga.chapterPages.length > 0
                height: 24
                width: pageCountText.implicitWidth + 18
                radius: Style.cornerRadius
                color: Util.alpha(Colors.text, 0.09)
                border.color: Util.alpha(Colors.text, 0.12)
                border.width: 1

                StyledText {
                    id: pageCountText
                    anchors.centerIn: parent
                    text: (readerView.visiblePage + 1) + " / " + Manga.chapterPages.length
                    font.family: readerView.fontBody
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 0.5
                    color: Util.alpha(Colors.text, 0.65)
                }
            }
        }
    }

    // ── Fetching pages overlay ───────────────────────────────────────────────
    LoadingState {
        anchors.fill: parent
        z: 8
        active: Manga.isFetchingPages
        color: Colors.background
        textColor: Colors.text
        spinnerSize: 40
        label: I18n.t("manga.loadingPages")
        detail: Manga.currentManga ? Manga.currentManga.title : ""
        bodyFont: readerView.fontBody
    }

    // ── Pages error overlay ──────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Colors.background
        visible: Manga.pagesError.length > 0 && !Manga.isFetchingPages
        z: 7

        Column {
            anchors.centerIn: parent
            spacing: Style.spacing.xl

            StyledText {
                text: "⚠"
                font.pixelSize: 32 // style-ignore — bespoke size
                color: Colors.error
                anchors.horizontalCenter: parent.horizontalCenter
                opacity: 0.85
            }
            StyledText {
                text: Manga.pagesError
                color: Util.alpha(Colors.text, 0.45)
                font.pixelSize: Style.font.bodySmall
                font.family: readerView.fontBody
                wrapMode: Text.Wrap
                width: 260
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 1.4
            }
        }
    }

    // ── Page list ────────────────────────────────────────────────────────────
    // Which page the viewport is on. `currentIndex` is no use here: the wheel
    // handler moves `contentY` directly, and a programmatic scroll does NOT
    // update it (measured: contentY 2100 -> currentIndex 0 while indexAt said
    // 3), so the indicator used to sit on "1" forever.
    // indexAt answers -1 in an area the list has not laid out (its height
    // estimate can fall short while pages are recycled). Keep the last answer
    // instead of dropping to currentIndex, which never moves with a wheel.
    property int _lastPage: 0

    // Placeholder height ratio (height / width). The old fixed 1.42 was eight
    // times smaller than a real long-strip page (852 vs 6667 px), so every
    // page grew hugely when it loaded and the list's height estimate kept
    // collapsing. The first loaded page of a chapter teaches the real value,
    // ONCE: learning on every load resized every placeholder each time, and
    // the list's contentHeight and originY swung by tens of thousands of
    // pixels under the reader.
    property real _ratio: 1.42
    property bool _ratioLearned: false
    function _learnRatio(value) {
        if (ReaderScroll.shouldLearnRatio(readerView._ratioLearned, value)) {
            readerView._ratio = value
            readerView._ratioLearned = true
        }
    }

    // Retries per page index of this chapter. It lives here, not in the
    // delegate, because delegates outside cacheBuffer are destroyed and would
    // forget that a page already had its one automatic retry.
    property var _attempts: ({})
    function _retryPage(index) {
        readerView._attempts = ReaderScroll.bumpAttempt(readerView._attempts, index)
    }

    // Clamped to the current chapter: the remembered page survives a chapter
    // change, and a shorter chapter would otherwise report an out-of-range
    // number and look like it is already at the end.
    readonly property int visiblePage: ReaderScroll.pageAt(
        pageListView.indexAt(pageListView.width / 2, pageListView.contentY + 1),
        readerView._lastPage, pageListView.count)
    onVisiblePageChanged: if (visiblePage !== _lastPage) _lastPage = visiblePage

    ListView {
        id: pageListView
        anchors {
            fill: parent
            topMargin: readerView.headerVisible ? Style.space(54) : 0
            // One gutter with the top zone (§32.1); the bar keeps its lane.
            rightMargin: Gutter.right
        }
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: Manga.chapterPages
        // Pages load asynchronously and their real height differs from the
        // placeholder ratio, so a page above the viewport can change height
        // after you scrolled past it. Qt already keeps the view still: it
        // moves the pages above and changes originY, and contentY stays put.
        // Do NOT shift contentY by hand on a height change; that moved the
        // view twice and could leave it below every laid-out page. The bigger
        // cache only preloads pages so fewer of them resize near the eye.
        cacheBuffer: Math.max(0, height * 2)
        spacing: Style.spacing.xs
        Behavior on anchors.topMargin { NumberAnimation { duration: Motion.slow; easing.type: Motion.easeOut } }

        // Wheel speed is a preference, not a constant: Qt's default notch is a
        // few dozen pixels, which crawls through a full page. `scrollFactor`
        // (settings.json, default 2) multiplies it.
        WheelHandler {
            blocking: true
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            // The range is [originY, originY + contentHeight - height], and
            // a wheel at the estimated end with pages left steps by page:
            // components/reader_scroll.js explains both.
            onWheel: function(event) {
                const plan = ReaderScroll.wheelPlan(WheelScroll, pageListView,
                    event.angleDelta.y, event.pixelDelta.y, UiPrefs.scrollFactor, readerView.visiblePage)
                if (plan.kind === "page") {
                    pageListView.positionViewAtIndex(plan.index, ListView.Beginning)
                } else if (plan.kind === "move") {
                    if (plan.settling)
                        console.warn("[reader] no scrollable height yet (count=" + pageListView.count
                            + " contentH=" + pageListView.contentHeight + " h=" + pageListView.height + ")")
                    pageListView.contentY = plan.y
                }
                event.accepted = true
            }
        }

        // Tap anywhere to toggle header
        MouseArea {
            anchors.fill: parent
            propagateComposedEvents: true
            onClicked: {
                readerView.headerVisible = !readerView.headerVisible
                mouse.accepted = false
            }
        }

        delegate: Item {
            id: pageItem
            readonly property int attempt: ReaderScroll.attemptOf(readerView._attempts, index)
            readonly property bool failed: pageImg.status === Image.Error
            // A click on an offline file keeps the same source: blank it for
            // one turn so the Image loads it again.
            property bool _reloading: false
            width: pageListView.width
            height: pageImg.status === Image.Ready && pageImg.implicitWidth > 0
                ? pageImg.implicitHeight * (Math.max(1, pageListView.width) / pageImg.implicitWidth)
                : Math.max(1, pageListView.width) * readerView._ratio

            function retry() {
                const before = pageImg.source.toString()
                readerView._retryPage(index)
                if (ReaderScroll.pageSource(modelData.url || "", pageItem.attempt) === before) {
                    pageItem._reloading = true
                    Qt.callLater(function() { pageItem._reloading = false })
                }
            }

            // A failed page tries once more by itself (a slow or flaky CDN
            // often answers the second time); after that it waits for a click.
            Timer {
                id: autoRetry
                interval: ReaderScroll.AUTO_RETRY_DELAY_MS
                onTriggered: readerView._retryPage(index)
            }

            Image {
                id: pageImg
                anchors.fill: parent
                source: pageItem._reloading ? "" : ReaderScroll.pageSource(modelData.url || "", pageItem.attempt)
                // A page is often 1080x3000; decoding it at full size costs
                // ~12 MB each and several per screen with the preload, which
                // is what made fast scrolling stutter. Scaling during decode
                // keeps the aspect ratio and returns the same implicit size.
                sourceSize.width: Math.max(1, pageListView.width)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                opacity: status === Image.Ready ? 1 : 0
                onStatusChanged: {
                    if (status === Image.Ready && implicitWidth > 0)
                        readerView._learnRatio(implicitHeight / implicitWidth)
                    else if (status === Image.Error && ReaderScroll.canAutoRetry(modelData.url || "", pageItem.attempt))
                        autoRetry.restart()
                }
                Behavior on opacity { NumberAnimation { duration: Motion.slow } }

            }

            // Loading placeholder. Beside the page, not inside it: the page
            // sits at opacity 0 until it's ready, which would hide a child.
            Rectangle {
                anchors.fill: parent
                z: -1
                color: Colors.surface_container_low
                visible: pageImg.status !== Image.Ready

                Column {
                    anchors.centerIn: parent
                    spacing: Style.spacing.xxl

                    Spinner {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: !pageItem.failed || autoRetry.running
                        width: 22
                        border.width: 2
                        border.color: Util.alpha(Colors.text, 0.08)
                        arcColor: Util.alpha(Colors.text, 0.45)
                        duration: Motion.loop
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: pageItem.failed && !autoRetry.running
                        text: "⊘"
                        font.pixelSize: 22 // style-ignore — bespoke size
                        color: Util.alpha(Colors.text, 0.3)
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: I18n.t("page", { 1: modelData.index + 1 })
                            + (pageItem.failed && !autoRetry.running
                                ? "  ·  " + I18n.t("manga.pageFailed") + "  ·  " + I18n.t("manga.pageRetry")
                                : "")
                        color: Util.alpha(Colors.text, 0.3)
                        font.pixelSize: Style.font.caption
                        font.family: readerView.fontBody
                        font.letterSpacing: 1.5
                    }

                    // Download progress, once the image reports any
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: pageImg.status === Image.Loading && pageImg.progress > 0
                        width: 96; height: 2; radius: height / 2 // style-ignore — progress
                        color: Util.alpha(Colors.text, 0.08)

                        Rectangle {
                            width: parent.width * pageImg.progress
                            height: parent.height; radius: height / 2 // style-ignore — progress
                            color: Colors.primary
                            Behavior on width { NumberAnimation { duration: Motion.base } }
                        }
                    }
                }

                // «failed to load · click to retry». Accept the click so the
                // header toggle under the list does not fire too.
                MouseArea {
                    anchors.fill: parent
                    enabled: pageItem.failed && !autoRetry.running
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: function(mouse) {
                        mouse.accepted = true
                        pageItem.retry()
                    }
                }
            }
        }

    }

    // ── Reading progress bar (bottom) ─────────────────────────────────────────
    Item {
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        height: 3
        z: 9
        visible: Manga.chapterPages.length > 0

        // Track
        Rectangle {
            anchors.fill: parent
            color: Util.alpha(Colors.text, 0.06)
        }

        // Fill
        Rectangle {
            width: Manga.chapterPages.length > 0
                ? parent.width * ((readerView.visiblePage + 1) / Manga.chapterPages.length)
                : 0
            height: parent.height
            color: Colors.primary
            Behavior on width { NumberAnimation { duration: Motion.slow; easing.type: Motion.easeOut } }
        }
    }
}
