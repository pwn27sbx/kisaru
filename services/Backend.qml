import QtQuick
import Quickshell
import Quickshell.Io
import "health_backoff.js" as HealthBackoff

// One backend server: its process, its bounded respawn and the health poll
// that flips `serverReady` (audit 2026-11-06, finding 28).
//
// Anime, Manga and Novel differ only in the interpreter and script, the log
// tag, the port (`url`) and what they fetch once the server answers. The rest
// used to be three copies of the same block, so a fix to the respawn budget or
// the poll re-arm could land in one panel and miss the other two.
//
// A service keeps the state readable from outside (`Manga.serverReady`) by
// binding its own read-only property to `backend.serverReady`, and keeps its
// start-up work in `onReady`, so the order of its logging and fetches is the
// same as before.
Item {
    id: root

    property string python: ""
    property string script: ""
    property string url: ""
    property string tag: "[Backend]"

    // Respawn budget: a backend that cannot start must not loop forever.
    property int maxRestarts: 20
    property int restartCount: 0

    property bool serverReady: false

    signal ready

    Process {
        id: serverProcess
        command: [root.python, root.script]
        running: true
        onExited: (code) => {
            root.serverReady = false
            if (root.restartCount >= root.maxRestarts) {
                console.error(root.tag, "Server exited; restart budget spent")
                return
            }
            console.warn(root.tag, "Server exited with code", code, "— restarting")
            restartTimer.interval = HealthBackoff.nextDelay(root.restartCount, 3000, 60000)
            root.restartCount += 1
            restartTimer.start()
        }
    }

    // A bounded, growing pause before restarting: a server that cannot start
    // (port taken, venv missing) must not be respawned every 3 s forever
    // (audit 2026-11-06, finding 15).
    Timer {
        id: restartTimer
        interval: 3000
        onTriggered: {
            serverProcess.running = true
            // HealthPoller stops itself at ready(), so a restart has to re-arm it.
            healthPoller.running = true
        }
    }

    HealthPoller {
        id: healthPoller
        url: root.url
        onReady: {
            root.serverReady = true
            root.restartCount = 0
            console.log(root.tag, "Backend ready at", root.url)
            root.ready()
        }
    }
}
