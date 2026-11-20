import QtQuick
import Quickshell
import "../../components/wheel_scroll.js" as WheelScroll
import "../../components/reader_scroll.js" as ReaderScroll

// Headless harness for the manga long-strip reader.
//
// It builds the same ListView as modules/manga/components/ReaderView.qml and
// takes every decision from the REAL components/wheel_scroll.js and
// components/reader_scroll.js. Only the delegate `height:` binding is copied
// from ReaderView.qml; tests/reader_scroll_unit.test.js checks the copy. The
// real ReaderView is never loaded: its Manga singleton talks to port 5150.
//
// KH_SCENARIO
//   scroll  wheel down through 13 slow pages; PASS when no wheel write moves the
//           view up, the view never lands below every laid-out page, and it
//           ends on the last page.
//   retry   page 1 fails once (the automatic retry must load it), page 2 fails
//           twice (the click must load it), page 3 is a missing offline file
//           (never retried by itself).
//
// Run through tests/reader_scroll.test.js or tests/reader_scroll_harness/run.js.
ShellRoot {
    FloatingWindow {
        implicitWidth: 900; implicitHeight: 1000
        visible: true
        color: "black"

        Item {
            id: readerView
            anchors.fill: parent

            readonly property string scenario: Quickshell.env("KH_SCENARIO") || "scroll"
            readonly property int port: parseInt(Quickshell.env("KH_PORT") || "0")
            readonly property real scrollFactor: 2
            readonly property var pages: {
                const base = "http://127.0.0.1:" + port + "/image?url=p"
                if (scenario === "retry")
                    return [base + 0, base + 1, base + 2, "file:///nonexistent/kisaru-harness/003.png"]
                const out = []
                for (let i = 0; i < 13; i++) out.push(base + i)
                return out
            }

            // ── State the real ReaderView keeps ──────────────────────────────
            property int _lastPage: 0
            property real _ratio: 1.42
            property bool _ratioLearned: false
            property var _attempts: ({})
            function _learnRatio(value) {
                if (ReaderScroll.shouldLearnRatio(readerView._ratioLearned, value)) {
                    readerView._ratio = value
                    readerView._ratioLearned = true
                }
            }
            function _retryPage(index) {
                readerView._attempts = ReaderScroll.bumpAttempt(readerView._attempts, index)
            }
            readonly property int visiblePage: ReaderScroll.pageAt(
                pageListView.indexAt(pageListView.width / 2, pageListView.contentY + 1),
                readerView._lastPage, pageListView.count)
            onVisiblePageChanged: if (visiblePage !== _lastPage) _lastPage = visiblePage

            // ── Probes ───────────────────────────────────────────────────────
            property string tag: "qt"
            property bool driving: false
            property real _prevY: 0
            property int badUp: 0
            property int blanks: 0
            property real t0: Date.now()
            function ts() { return ((Date.now() - t0) / 1000).toFixed(2) }
            function st() {
                return "cY=" + Math.round(pageListView.contentY) + " cH=" + Math.round(pageListView.contentHeight)
                    + " oY=" + Math.round(pageListView.originY)
                    + " end=" + Math.round(pageListView.originY + pageListView.contentHeight - pageListView.height)
                    + " vis=" + (visiblePage + 1) + "/" + pageListView.count
            }
            function setY(value, why) { const prev = tag; tag = why; pageListView.contentY = value; tag = prev }

            // The body of ReaderView's WheelHandler.onWheel, minus the warning.
            function wheel(angleY, pixelY) {
                const plan = ReaderScroll.wheelPlan(WheelScroll, pageListView, angleY, pixelY,
                    readerView.scrollFactor, readerView.visiblePage)
                if (plan.kind === "page") {
                    const prev = tag; tag = "page-step"
                    pageListView.positionViewAtIndex(plan.index, ListView.Beginning)
                    tag = prev
                } else if (plan.kind === "move") {
                    setY(plan.y, "wheel")
                }
            }

            ListView {
                id: pageListView
                anchors { fill: parent; topMargin: 54 }
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: readerView.pages
                // The retry scenario needs all four pages alive at once.
                cacheBuffer: readerView.scenario === "retry" ? 100000 : Math.max(0, height * 2)
                spacing: 4
                onContentYChanged: {
                    const dy = contentY - readerView._prevY
                    if (readerView.driving && dy < -1 && readerView.tag !== "qt") {
                        readerView.badUp++
                        console.log("UP-MOVE t=" + readerView.ts() + " by=" + readerView.tag
                            + " dy=" + Math.round(dy) + " " + readerView.st())
                    }
                    // A blank frame has no page anywhere at the top of the view.
                    // The top can also sit in the `spacing` gap between two laid-out
                    // pages, where indexAt answers -1 too; look one gap further down
                    // before calling it blank.
                    if (readerView.driving && indexAt(width / 2, contentY + 1) < 0
                            && indexAt(width / 2, contentY + spacing + 2) < 0) {
                        readerView.blanks++
                        console.log("BLANK t=" + readerView.ts() + " " + readerView.st())
                    }
                    readerView._prevY = contentY
                }

                delegate: Item {
                    id: page
                    readonly property int pageIndex: index
                    readonly property int attempt: ReaderScroll.attemptOf(readerView._attempts, index)
                    readonly property int status: pageImg.status
                    property bool _reloading: false
                    width: pageListView.width
                    height: pageImg.status === Image.Ready && pageImg.implicitWidth > 0
                        ? pageImg.implicitHeight * (Math.max(1, pageListView.width) / pageImg.implicitWidth)
                        : Math.max(1, pageListView.width) * readerView._ratio

                    // What ReaderView's retry click does.
                    function retry() {
                        const before = pageImg.source.toString()
                        readerView._retryPage(index)
                        if (ReaderScroll.pageSource(modelData, page.attempt) === before) {
                            page._reloading = true
                            Qt.callLater(function() { page._reloading = false })
                        }
                    }

                    Timer {
                        id: autoRetry
                        interval: ReaderScroll.AUTO_RETRY_DELAY_MS
                        onTriggered: readerView._retryPage(page.pageIndex)
                    }

                    Image {
                        id: pageImg
                        anchors.fill: parent
                        source: page._reloading ? "" : ReaderScroll.pageSource(modelData, page.attempt)
                        sourceSize.width: Math.max(1, pageListView.width)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: true
                        onStatusChanged: {
                            if (status === Image.Ready && implicitWidth > 0)
                                readerView._learnRatio(implicitHeight / implicitWidth)
                            else if (status === Image.Error && ReaderScroll.canAutoRetry(modelData, page.attempt))
                                autoRetry.restart()
                            if (readerView.scenario === "retry")
                                console.log("STATUS t=" + readerView.ts() + " p" + page.pageIndex
                                    + " status=" + status + " attempt=" + page.attempt)
                        }
                    }
                }

                // Mirrors ReaderView's ~72 px chapter-navigation footer.
                footer: Item {
                    width: pageListView.width
                    height: pageListView.count > 0 ? 72 : 0
                }
            }

            // ── Drivers ──────────────────────────────────────────────────────
            Timer {
                interval: parseInt(Quickshell.env("KH_TICK") || "80"); repeat: true
                running: readerView.scenario === "scroll"
                property int ticks: 0
                onTriggered: {
                    ticks++
                    if (ticks < 15) return   // let page 1 land
                    readerView.driving = true
                    const wheelTicks = parseInt(Quickshell.env("KH_TICKS") || "250")
                    const n = ticks - 15
                    if (n < wheelTicks) {
                        readerView.wheel(-120, 0)
                        if (n % 25 === 0) console.log("TICK " + n + " t=" + readerView.ts() + " " + readerView.st())
                    } else if (n >= wheelTicks + 100) {
                        const ok = readerView.badUp === 0 && readerView.blanks === 0
                            && readerView.visiblePage === pageListView.count - 1
                        console.log("DONE " + readerView.st())
                        console.log("RESULT " + (ok ? "PASS" : "FAIL") + " badUpMoves=" + readerView.badUp
                            + " blankFrames=" + readerView.blanks + " endPage=" + (readerView.visiblePage + 1))
                        Qt.exit(ok ? 0 : 1)
                    }
                }
            }

            Timer {
                interval: 100; repeat: true
                running: readerView.scenario === "retry"
                property int ticks: 0
                property var checks: []
                function item(i) { return pageListView.itemAtIndex(i) }
                function check(name, ok) {
                    checks.push(name + "=" + (ok ? "ok" : "BAD"))
                    console.log("CHECK " + name + " " + (ok ? "ok" : "BAD") + " t=" + readerView.ts()
                        + " p0=" + item(0).status + "/" + item(0).attempt
                        + " p1=" + item(1).status + "/" + item(1).attempt
                        + " p2=" + item(2).status + "/" + item(2).attempt
                        + " p3=" + item(3).status + "/" + item(3).attempt)
                }
                onTriggered: {
                    ticks++
                    if (ticks === 65) {
                        // 6.5 s: both automatic retries have run and answered.
                        check("autoRetryLoadsPage1", item(1).status === Image.Ready && item(1).attempt === 1)
                        check("page2FailsTwice", item(2).status === Image.Error && item(2).attempt === 1)
                        check("noAutoRetryForFile", item(3).status === Image.Error && item(3).attempt === 0)
                        check("goodPageUntouched", item(0).status === Image.Ready && item(0).attempt === 0)
                        item(2).retry()
                        item(3).retry()
                    } else if (ticks === 95) {
                        // 9.5 s: well past the click's refetch and past another 3 s.
                        check("clickLoadsPage2", item(2).status === Image.Ready && item(2).attempt === 2)
                        check("clickReloadsFile", item(3).status === Image.Error && item(3).attempt === 1)
                        const ok = checks.every(function(c) { return c.endsWith("=ok") })
                        console.log("RESULT " + (ok ? "PASS" : "FAIL") + " " + checks.join(" "))
                        Qt.exit(ok ? 0 : 1)
                    }
                }
            }
        }
    }
}
