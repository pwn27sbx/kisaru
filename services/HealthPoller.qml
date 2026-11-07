import QtQuick
import "health_backoff.js" as HealthBackoff

// Polls `<url>/health` until the backend answers, then stops and emits ready()
// exactly once. The caller keeps its own start-up work in onReady so the order
// of its logging and follow-up fetches is unchanged.
//
// It used to ask every 150 ms forever: a backend that cannot start (missing
// venv, port taken) cost ~20 requests per second for the whole session. The
// delay now doubles up to `maxInterval`, and the poll gives up after
// `maxAttempts` with a `failed` signal (audit 2026-11-06, finding 15).
Timer {
    id: root

    property string url: ""
    property int initialInterval: 150
    property int maxInterval: 5000
    property int maxAttempts: 40
    property int attempts: 0
    property int requestTimeout: 10000

    signal ready
    signal failed

    interval: initialInterval
    repeat: true
    running: true

    // The respawn timer re-arms the poller; a fresh start gets a fresh budget.
    onRunningChanged: {
        if (running) {
            attempts = 0
            interval = initialInterval
        }
    }

    onTriggered: {
        var settled = false

        function giveUp() {
            root.attempts += 1
            if (HealthBackoff.exhausted(root.attempts, root.maxAttempts)) {
                root.stop()
                console.warn("[HealthPoller] giving up on", root.url,
                             "after", root.attempts, "attempts")
                root.failed()
                return
            }
            root.interval = HealthBackoff.nextDelay(
                root.attempts, root.initialInterval, root.maxInterval)
        }

        function fail() {
            if (settled) return
            settled = true
            giveUp()
        }

        var xhr = new XMLHttpRequest()
        xhr.timeout = root.requestTimeout
        xhr.ontimeout = function() { fail() }
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                if (settled) return
                settled = true
                root.stop()
                root.ready()
            } else {
                fail()
            }
        }
        xhr.open("GET", root.url + "/health")
        xhr.send()
    }
}
