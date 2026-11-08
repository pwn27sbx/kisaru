import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.app
import qs.Commons
import qs.services
import qs.components
import "../../../components/wheel_scroll.js" as WheelScroll
import "../../../services/reader_metrics.js" as ReaderMetrics

Item {
    id: readerView

    readonly property string fontDisplay: Style.font.family
    readonly property string fontBody:    Style.font.family

    signal backRequested()
    signal toggleFullscreen()

    property bool isFullscreen: false
    property real fontSize:      17
    property real lineHeight:    1.75
    property bool headerVisible: true

    // The width the panel is heading to, not the width it has mid-animation.
    // The caller passes its target; a caller that passes nothing keeps the old
    // behaviour of following the live width.
    property real contentWidth: width
    readonly property real _targetMeasure: ReaderMetrics.columnWidth(contentWidth)
    // Set only by applyMeasure(). A binding here would follow contentWidth and
    // jump straight to the wider measure, before the panel can hold it — the
    // gate this whole change is about (review R3-MeasureBindingBypassesGate).
    property real _measure: 0
    // The widening target the fade commits at its midpoint (D1).
    property real _pendingMeasure: 0

    function reset() {
        headerVisible = true
        _anchorIndex = -1
        textScroll.contentY = 0
    }

    // Reflowing the chapter changes every paragraph's height, and the Flickable
    // only holds a pixel offset, so a resize would land the reader somewhere
    // else in the chapter. Remember the paragraph under the top edge (and how
    // far into it the reader was) before the measure changes; the Column calls
    // restoreAnchor() once it has re-laid out.
    property int _anchorIndex: -1
    property real _anchorOffset: 0
    property var _anchorChapter: null

    function captureAnchor() {
        _anchorChapter = Novel.currentChapter
        _anchorIndex = -1
        _anchorOffset = 0
        if (!paragraphsRepeater || !textScroll) return
        for (var i = 0; i < paragraphsRepeater.count; i++) {
            var item = paragraphsRepeater.itemAt(i)
            if (!item) continue
            if (item.y + item.height > textScroll.contentY) {
                _anchorIndex = i
                _anchorOffset = textScroll.contentY - item.y
                return
            }
        }
    }

    function restoreAnchor() {
        if (_anchorIndex < 0) return
        var index = _anchorIndex
        _anchorIndex = -1
        // A chapter that changed between capture and layout has no anchor left.
        if (!Novel.currentChapter || Novel.currentChapter !== _anchorChapter) return
        if (!paragraphsRepeater) return
        var item = paragraphsRepeater.itemAt(index)
        if (!item) return
        var offset = Math.min(_anchorOffset, item.height)
        // The Flickable's contentHeight may not have taken the new implicit
        // height yet, so measure the limit from the column itself.
        var limit = Math.max(0, textColumn.implicitHeight + 80 - textScroll.height)
        textScroll.contentY = Math.max(0, Math.min(item.y + offset, limit))
    }

    // The target measure is already known when the mode toggles, but the panel
    // is still on its way there. Narrowing applies at once; widening waits for
    // the animation to finish, then fades out, reflows on the hidden frame and
    // fades back in (owner, 2026-11-08: the text seemed to jump). A reader that
    // is not visible defers until it is shown and never fades: that view
    // already fades in as a whole. Reduced motion keeps the instant reflow.
    function applyMeasure(allowed) {
        if (!readerView.visible) return
        var next = ReaderMetrics.shownMeasure(_measure, _targetMeasure, width, contentWidth)
        if (next === _measure) return
        if (allowed === undefined) allowed = true
        if (ReaderMetrics.fadesOnMeasureChange(_measure, next, MotionPrefs.reduced, allowed)) {
            _pendingMeasure = next
            // A second widen while the fade runs only retargets it (D1).
            if (!measureFade.running)
                measureFade.restart()
            return
        }
        // Everything else keeps the instant path, and it must never leave a
        // running fade half-way (D2).
        if (measureFade.running)
            measureFade.stop()
        textColumn.opacity = 1
        captureAnchor()
        _measure = next
    }

    // The fade's midpoint and the instant path share this exact capture-then-set
    // order; the anchor is taken while the text is still where the reader left
    // it, then the column reflows.
    function _commitMeasure() {
        captureAnchor()
        _measure = _pendingMeasure
    }

    // Fade-out -> reflow -> fade-in for a widening (D1). textColumn has no
    // opacity binding and no Behaviour: the animation owns the value and always
    // ends at 1 (D3).
    SequentialAnimation {
        id: measureFade
        NumberAnimation {
            target: textColumn
            property: "opacity"
            to: 0
            duration: Motion.fast
            easing.type: Motion.easeOut
        }
        ScriptAction { script: readerView._commitMeasure() }
        NumberAnimation {
            target: textColumn
            property: "opacity"
            to: 1
            duration: Motion.base
            easing.type: Motion.easeOut
        }
        // A widening that arrives after the midpoint (during the fade-in) is
        // retargeted, never restarted (D1); once the text is fully back, the
        // newest target gets its own fade so no measure is dropped.
        onFinished: if (readerView._pendingMeasure !== readerView._measure)
            readerView.applyMeasure()
    }

    onContentWidthChanged: readerView.applyMeasure()
    onWidthChanged: readerView.applyMeasure()
    // Showing the reader applies the pending measure instantly: the view fades
    // in as a whole, so a second fade there would be invisible (D2).
    onVisibleChanged: if (readerView.visible) readerView.applyMeasure(false)

    readonly property bool _hasPrev: Novel.hasPrevChapter
    readonly property bool _hasNext: Novel.hasNextChapter

    readonly property string wordCountLabel: Novel.currentChapter && Novel.currentChapter.wordCount > 0
        ? I18n.t("words", { 1: (Math.round(Novel.currentChapter.wordCount / 100) / 10) }) : ""

    // The novel reader is a page of the theme, not a page of paper. Its ground,
    // its type and its chrome are the same `Colors` roles the rest of Kisaru
    // reads, so switching the Omarchy theme repaints it. Text keeps the theme's
    // foreground at full strength (never a dimmed copy): the theme pair is what
    // guarantees 4.5:1 on dark and light themes, and an alpha on top would drop
    // the darkest ones below it. Hierarchy comes from size, weight and spacing.
    Rectangle { anchors.fill: parent; color: Colors.background }

    Rectangle {
        id: readerHeader
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 54; color: Colors.background; z: 10
        opacity: readerView.headerVisible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.slow; easing.type: Motion.easeOut } }

        Rectangle {
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 1; color: Util.alpha(Colors.text, 0.10)
        }

        RowLayout {
            anchors { fill: parent; leftMargin: Style.spacing.md; rightMargin: Style.spacing.xxxl }
            spacing: Style.spacing.xxs

            Item {
                width: 44; height: 44
                Rectangle {
                    anchors.centerIn: parent; width: 34; height: 34; radius: Style.cornerRadius
                    color: backHover.containsMouse ? Util.alpha(Colors.text, 0.06) : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.base } }
                }
                Text { anchors.centerIn: parent; text: "←"; font.pixelSize: Style.font.iconLarge; color: Colors.text }
                MouseArea {
                    id: backHover; anchors.fill: parent; hoverEnabled: true
                    onClicked: { Novel.clearChapter(); readerView.backRequested() }
                }
            }

            Column {
                Layout.fillWidth: true; spacing: Style.spacing.hairline
                StyledText {
                    width: parent.width
                    text: Novel.currentNovel ? Novel.currentNovel.title : ""
                    font.family: readerView.fontDisplay; font.pixelSize: Style.font.bodySmall
                    color: Colors.text; elide: Text.ElideRight
                }
                StyledText {
                    width: parent.width
                    text: Novel.currentChapter ? Novel.currentChapter.title : ""
                    font.family: readerView.fontDisplay; font.pixelSize: Style.font.subtitle
                    color: Colors.text; elide: Text.ElideRight
                }
            }

            Item {
                width: 34; height: 34
                Rectangle {
                    anchors.centerIn: parent; width: 30; height: 30; radius: Style.cornerRadius
                    color: fsMinusHover.containsMouse ? Util.alpha(Colors.text, 0.06) : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }
                Text { anchors.centerIn: parent; text: "A−"; font.pixelSize: Style.font.caption; color: Colors.text }
                MouseArea {
                    id: fsMinusHover; anchors.fill: parent; hoverEnabled: true
                    onClicked: readerView.fontSize = Math.max(13, readerView.fontSize - 1)
                }
            }

            Item {
                width: 34; height: 34
                Rectangle {
                    anchors.centerIn: parent; width: 30; height: 30; radius: Style.cornerRadius
                    color: fsPlusHover.containsMouse ? Util.alpha(Colors.text, 0.06) : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }
                Text { anchors.centerIn: parent; text: "A+"; font.pixelSize: Style.font.bodySmall; color: Colors.text }
                MouseArea {
                    id: fsPlusHover; anchors.fill: parent; hoverEnabled: true
                    onClicked: readerView.fontSize = Math.min(26, readerView.fontSize + 1)
                }
            }

            Item {
                width: 34; height: 34
                Rectangle {
                    anchors.centerIn: parent; width: 30; height: 30; radius: Style.cornerRadius
                    color: fullscreenHover.containsMouse ? Util.alpha(Colors.text, 0.06) : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }
                Text {
                    anchors.centerIn: parent
                    text: readerView.isFullscreen ? "🗗" : "⛶"
                    font.pixelSize: Style.font.subtitle; color: Colors.text
                }
                MouseArea {
                    id: fullscreenHover; anchors.fill: parent; hoverEnabled: true
                    onClicked: readerView.toggleFullscreen()
                }
            }

            Rectangle {
                visible: readerView.wordCountLabel.length > 0
                height: 24; width: wcTxt.implicitWidth + 18; radius: Style.cornerRadius
                color: "transparent"; border.color: Colors.outline_variant; border.width: 1
                Text {
                    id: wcTxt; anchors.centerIn: parent
                    text: readerView.wordCountLabel
                    font.family: readerView.fontBody; font.pixelSize: Style.font.caption
                    font.letterSpacing: 0.4; color: Colors.text
                }
            }
        }
    }

    Item {
        anchors { top: readerHeader.bottom; left: parent.left; right: parent.right }
        height: 2; z: 9
        Rectangle { anchors.fill: parent; color: Util.alpha(Colors.text, 0.08) }
        Rectangle {
            width: textScroll.contentHeight > textScroll.height
                ? parent.width * Math.min(1,
                (textScroll.contentY + textScroll.height) / textScroll.contentHeight)
                : parent.width
            height: parent.height; color: Colors.primary
            Behavior on width { NumberAnimation { duration: Motion.fast } }
        }
    }

    // Loading: a ghost page in the reader's own measure and type size
    Rectangle {
        anchors.fill: parent; color: Colors.background; z: 8
        opacity: Novel.isFetchingChapter ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Motion.slow; easing.type: Motion.easeOut } }

        SkeletonText {
            anchors.fill: parent
            active: Novel.isFetchingChapter
            fontSize: readerView.fontSize
            lineHeight: readerView.lineHeight
            topInset: readerView.headerVisible ? 56 : 2
        }
    }

    LoadingBar {
        anchors { top: readerHeader.bottom; left: parent.left; right: parent.right }
        z: 10
        active: Novel.isFetchingChapter
    }

    Rectangle {
        anchors.fill: parent; color: Colors.background; z: 7
        visible: Novel.chapterError.length > 0 && !Novel.isFetchingChapter
        Column {
            anchors.centerIn: parent; spacing: Style.spacing.xl
            Text {
                text: "⚠"; font.pixelSize: 32; color: Colors.error // style-ignore — bespoke size
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: Novel.chapterError; color: Colors.text
                font.pixelSize: Style.font.bodySmall; font.family: readerView.fontBody
                wrapMode: Text.Wrap; width: 260; horizontalAlignment: Text.AlignHCenter; lineHeight: 1.4
            }
        }
    }

    Flickable {
        id: textScroll
        anchors {
            fill: parent
            topMargin: readerView.headerVisible ? Style.space(56) : Style.spacing.xxs
            bottomMargin: Style.space(56)
        }
        contentWidth: width
        contentHeight: textColumn.implicitHeight + 80
        clip: true; boundsBehavior: Flickable.StopAtBounds
        Behavior on anchors.topMargin { NumberAnimation { duration: Motion.slow; easing.type: Motion.easeOut } }

        // Same wheel preference as the manga reader (settings.json).
        WheelHandler {
            blocking: true
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: function(event) {
                const limit = Math.max(0, textScroll.contentHeight - textScroll.height)
                textScroll.contentY = WheelScroll.nextContentY(
                    textScroll.contentY, event.angleDelta.y, event.pixelDelta.y,
                    UiPrefs.scrollFactor, limit)
                event.accepted = true
            }
        }

        MouseArea {
            anchors.fill: parent; propagateComposedEvents: true
            onClicked: { readerView.headerVisible = !readerView.headerVisible; mouse.accepted = false }
        }

        Column {
            id: textColumn
            width: readerView._measure
            // The positioner finishes moving the paragraphs and only then
            // updates its implicitHeight, so restoring here lands after the
            // reflow and before the frame is painted: one reflow, one anchor
            // restore, no per-frame work.
            onImplicitHeightChanged: readerView.restoreAnchor()
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: Style.space(36); bottomPadding: Style.space(48); spacing: Style.space(0)

            StyledText {
                width: parent.width
                text: Novel.currentChapter ? Novel.currentChapter.title : ""
                font.family: readerView.fontDisplay
                font.pixelSize: readerView.fontSize + 7
                font.bold: true
                color: Colors.text
                wrapMode: Text.Wrap; lineHeight: 1.25; bottomPadding: Style.spacing.lg
            }

            Item {
                width: parent.width; height: 24
                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    spacing: Style.space(5)
                    Rectangle { width: 8;  height: 2; radius: height / 2; color: Colors.primary; opacity: 0.3 } // style-ignore — line
                    Rectangle { width: 32; height: 2; radius: height / 2; color: Colors.primary; opacity: 0.7 } // style-ignore — line
                    Rectangle { width: 8;  height: 2; radius: height / 2; color: Colors.primary; opacity: 0.3 } // style-ignore — line
                }
            }

            Item { width: 1; height: 20 }

            Repeater {
                id: paragraphsRepeater
                model: Novel.currentChapter ? Novel.currentChapter.paragraphs : []
                StyledText {
                    width: textColumn.width
                    text: modelData
                    font.family: readerView.fontDisplay
                    font.pixelSize: readerView.fontSize
                    color: Colors.text
                    wrapMode: Text.Wrap; lineHeight: readerView.lineHeight
                    bottomPadding: Math.round(readerView.fontSize * readerView.lineHeight * 0.75)
                    textFormat: Text.PlainText
                }
            }
        }

    }

    Rectangle {
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        height: 56; color: Colors.background; z: 10

        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 1; color: Util.alpha(Colors.text, 0.10)
        }

        Row {
            anchors { fill: parent; leftMargin: Style.space(16); rightMargin: Style.space(16) }

            Item {
                width: parent.width / 3; height: parent.height
                opacity: readerView._hasPrev ? 1.0 : 0.25
                Behavior on opacity { NumberAnimation { duration: Motion.base } }

                // Ghost buttons: the label sits on the page ground, never on a
                // tint, so the theme pair keeps its contrast in every state.
                Rectangle {
                    id: prevBtn
                    anchors { verticalCenter: parent.verticalCenter; left: parent.left }
                    width: prevBtnRow.implicitWidth + 28; height: 36; radius: Style.cornerRadius
                    color: "transparent"
                    border.width: 1
                    border.color: prevNavArea.containsMouse && readerView._hasPrev
                        ? Colors.primary : Colors.outline_variant
                    Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                    Row {
                        id: prevBtnRow; anchors.centerIn: parent; spacing: Style.space(5)
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "‹"; font.pixelSize: Style.font.iconLarge; color: Colors.text }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: I18n.t("action.prev"); font.family: readerView.fontBody; font.pixelSize: Style.font.body; color: Colors.text }
                    }
                }

                MouseArea {
                    id: prevNavArea; anchors.fill: parent; hoverEnabled: true
                    enabled: readerView._hasPrev
                    onClicked: { Novel.fetchPrevChapter(); textScroll.contentY = 0 }
                }
            }

            Item {
                width: parent.width / 3; height: parent.height
                StyledText {
                    anchors.centerIn: parent
                    text: Novel.currentChapter ? Novel.currentChapter.title : ""
                    font.family: readerView.fontBody; font.pixelSize: Style.font.caption
                    color: Colors.text; font.letterSpacing: 0.4
                    elide: Text.ElideMiddle; width: parent.width - 12
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            Item {
                width: parent.width / 3; height: parent.height
                opacity: readerView._hasNext ? 1.0 : 0.25
                Behavior on opacity { NumberAnimation { duration: Motion.base } }

                Rectangle {
                    id: nextBtn
                    anchors { verticalCenter: parent.verticalCenter; right: parent.right }
                    width: nextBtnRow.implicitWidth + 28; height: 36; radius: Style.cornerRadius
                    color: "transparent"
                    border.width: 1
                    border.color: nextNavArea.containsMouse && readerView._hasNext
                        ? Colors.primary : Util.alpha(Colors.primary, 0.7)
                    Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                    Row {
                        id: nextBtnRow; anchors.centerIn: parent; spacing: Style.space(5)
                        Text { anchors.verticalCenter: parent.verticalCenter; text: I18n.t("action.next"); font.family: readerView.fontBody; font.pixelSize: Style.font.body; color: Colors.text }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "›"; font.pixelSize: Style.font.iconLarge; color: Colors.text }
                    }
                }

                MouseArea {
                    id: nextNavArea; anchors.fill: parent; hoverEnabled: true
                    enabled: readerView._hasNext
                    onClicked: { Novel.fetchNextChapter(); textScroll.contentY = 0 }
                }
            }
        }
    }
}
