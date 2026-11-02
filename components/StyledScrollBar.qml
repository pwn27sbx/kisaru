import QtQuick
import QtQuick.Controls
import qs.app
import qs.Commons
import qs.services
import "../services/scroll_metrics.js" as Metrics

// The thin translucent scrollbar used by every list and grid in the shell.
//
// Option (b), owner §30: it lives in a lane of its own (the view reserves
// `Metrics.LANE` pixels on its right, so no card, row or paragraph sits under
// it), the handle is thinner than before, and it fades out when idle instead of
// sitting there. It appears while scrolling (position changes) or while the
// pointer is in the lane, and fades ~1 s after the last movement. Reduced motion
// makes show/hide instant instead of faded (services/MotionPrefs.qml).
ScrollBar {
    id: root

    property real thickness: Style.space(Metrics.THICKNESS)
    property real handleRadius: Style.space(1)
    property color handleColor: Colors.primary
    property real handleOpacity: 0.45

    policy: ScrollBar.AsNeeded

    // Visible while in use, hidden a moment after. `active` covers dragging and
    // the wheel (Qt sets it while the bar is being used).
    property bool awake: false

    opacity: awake || active || hovered || laneHover.hovered ? 1 : 0
    Behavior on opacity {
        enabled: !MotionPrefs.reduced
        NumberAnimation {
            duration: Metrics.FADE_MS
            easing.type: Motion.easeOut
        }
    }

    onPositionChanged: root._wake()
    onActiveChanged: if (active) root._wake()
    function _wake() {
        root.awake = true
        idleTimer.restart()
    }

    Timer {
        id: idleTimer
        interval: Metrics.IDLE_MS
        onTriggered: root.awake = false
    }

    // The lane is wider than the handle: a 2 px strip is impossible to point at,
    // and the owner asked for "hover the lane". Passive: it only reports hover,
    // so clicks reach the content underneath.
    Item {
        id: lane
        x: root.width - width
        width: Style.space(Metrics.LANE)
        height: root.height

        HoverHandler {
            id: laneHover
            onHoveredChanged: if (hovered) root._wake()
        }
    }

    contentItem: Rectangle {
        implicitWidth: root.thickness
        radius: root.handleRadius
        color: root.handleColor
        opacity: root.handleOpacity
    }
}
