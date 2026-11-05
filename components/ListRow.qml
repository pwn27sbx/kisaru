import QtQuick
import qs.Commons
import qs.app
import "../services/list_metrics.js" as ListMetrics

// One row of a manga list view: a cover thumbnail, the title, the work's
// metadata line and — when the caller has one — the reader's own progress.
//
// Round 9 (A-10) is the middle ground the owner asked for after finding A-9 too
// big: a 48 x 68 cover, a title one step over the body size (bold, up to two
// lines) and under it the datum — the chapter, the score run, the author —
// small but legible, not faint. The text block is centred against the cover.
// Every size, and the gap between title and datum, comes from
// services/list_metrics.js, which the loading skeleton reads too.
//
// It is the row twin of CoverCard, and it takes the SAME `meta` string instead
// of composing it: both views build it with services/manga_card.js, so the
// "chapter · status" rules (and their missing-chapter fallbacks) keep exactly
// one implementation. `progress` is the other thing: Library owns "Cap. N",
// Browse passes nothing and the slot collapses.
//
// Signals and press feedback match CoverCard, so a grid and its list are
// interchangeable from the view's point of view.
ClickableRect {
    id: root

    property url source: ""
    property string title: ""
    // Already localized by the caller (manga_card.metaLine).
    property string meta: ""
    // A score the row carries ahead of the meta line ("★ 8.8"), in the accent
    // tone the grid's chip uses. Empty hides it; the separator is the row's.
    property string score: ""
    // The reader's progress for this entry ("Cap. 12"); empty hides the slot.
    property string progress: ""
    // True once the entry has been read at least once: colours the progress.
    property bool progressActive: false
    property string bodyFont: ""
    // Horizontal padding for the cover, the text and the progress label. The
    // caller matches it to its own header/grid inset (Browse uses xl, Library
    // lg, like the two grids do).
    property int inset: Style.spacing.xl

    // The datum is secondary, not faint: the muted role lifted toward the
    // foreground (A-10). One place, so the score's companions and the author
    // line cannot drift.
    readonly property color datumColor: Colors.card_secondary

    // Qt caches a FAILED image load per URL for the engine's lifetime (see
    // CoverCard): one request that lands while the local backend restarts
    // would leave the row broken until the shell restarts. Same cache-busting
    // retry, one attempt per failure.
    property int _attempt: 0
    readonly property string _coverUrl: {
        const base = String(root.source || "")
        if (base === "") return ""
        if (root._attempt === 0) return base
        return base + (base.indexOf("?") >= 0 ? "&" : "?") + "retry=" + root._attempt
    }

    // Shared with the skeleton that stands in for these rows while loading.
    implicitHeight: Style.space(ListMetrics.ROW_HEIGHT_BASE)
    color: "transparent"

    // Hover/press tint behind the content. Declared first so it stays under
    // the cover and the text; the rows themselves have no fill of their own.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Colors.primary
        opacity: root.pressed ? Style.pressedFillAlpha : (root.hovered ? Style.hoverFillAlpha : 0)
        Behavior on opacity { NumberAnimation { duration: Motion.base } }
    }

    Rectangle {
        id: coverBox
        anchors {
            left: parent.left
            verticalCenter: parent.verticalCenter
            leftMargin: root.inset
        }
        // The thumbnail's size is a decision, not a consequence of the row
        // height: it is shared with the skeleton through list_metrics, and both
        // sides are declared so nothing depends on which way a ratio is read.
        width: Style.space(ListMetrics.THUMB_WIDTH)
        height: Style.space(ListMetrics.THUMB_HEIGHT)
        radius: root.radius
        color: Colors.surface_container
        clip: true

        Image {
            id: cover
            anchors.fill: parent
            source: root._coverUrl
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.slow } }

            onStatusChanged: {
                if (status === Image.Error && root._attempt < 2)
                    coverRetry.restart()
            }
        }

        Timer {
            id: coverRetry
            interval: 1500
            onTriggered: root._attempt += 1
        }
    }

    // Outside the cover: the cover is transparent until the image is ready,
    // which would hide a child placeholder too. The glyph is scaled down to the
    // thumbnail: the default suits a full-size poster tile.
    CoverPlaceholder {
        anchors.fill: coverBox
        status: cover.status
        glyphSize: Style.font.title
    }

    // Title + metadata, centred as one block against the cover. `right` stops
    // before the progress label when the caller passes one, so a long title
    // never runs underneath it.
    Column {
        id: textColumn
        anchors {
            left: coverBox.right
            right: progressText.visible ? progressText.left : parent.right
            leftMargin: root.inset
            rightMargin: root.inset
            verticalCenter: parent.verticalCenter
        }
        // A short breath between the title and the datum (A-10: tighter than
        // A-9, from the shared metrics).
        spacing: Style.space(ListMetrics.TEXT_GAP_BASE)

        StyledText {
            width: parent.width
            text: root.title
            font.family: root.bodyFont
            // One step over the body size, from the shared scale.
            font.pixelSize: Math.round(Style.font.body * ListMetrics.TITLE_SCALE)
            font.bold: true
            font.letterSpacing: 0.2
            color: Colors.on_surface
            // Two lines instead of one: a long title is worth more than a tidy
            // column (owner, A-8). Elide still cuts the second line.
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        // The datum under the title: "Ch. 200", "★ 8.8 · 4 ep", the author. The
        // score keeps the accent tone of the grid's chip and the rest is muted,
        // small, the way the sketch draws it; the separator appears only when
        // both halves exist.
        Row {
            width: parent.width
            spacing: Style.spacing.xs

            StyledText {
                id: scoreText
                visible: root.score !== ""
                text: root.score
                font.family: root.bodyFont
                font.pixelSize: Math.round(Style.font.body * ListMetrics.DATUM_SCALE)
                font.letterSpacing: 0.3
                font.bold: true
                color: Colors.primary
            }

            StyledText {
                id: scoreSeparator
                visible: root.score !== "" && root.meta !== ""
                text: "·"
                font.family: root.bodyFont
                font.pixelSize: Math.round(Style.font.body * ListMetrics.DATUM_SCALE)
                color: root.datumColor
            }

            StyledText {
                visible: root.meta !== ""
                // A Row does not shrink its children: without this the meta
                // runs past the row instead of eliding (review finding).
                width: Math.max(0, parent.width
                    - (scoreText.visible ? scoreText.width + parent.spacing : 0)
                    - (scoreSeparator.visible ? scoreSeparator.width + parent.spacing : 0))
                text: root.meta
                font.family: root.bodyFont
                font.pixelSize: Math.round(Style.font.body * ListMetrics.DATUM_SCALE)
                font.letterSpacing: 0.3
                color: root.datumColor
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }

    // The hairline between rows: inset like the content, so the list reads as
    // rows and not as a wall of text (owner, A-8).
    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: root.inset
            rightMargin: root.inset
        }
        height: 1
        color: Colors.outline_variant
        opacity: 0.6
    }

    StyledText {
        id: progressText
        anchors {
            right: parent.right
            rightMargin: root.inset
            verticalCenter: parent.verticalCenter
        }
        visible: root.progress !== ""
        text: root.progress
        font.family: root.bodyFont
        font.pixelSize: Style.font.caption
        font.letterSpacing: 0.4
        color: root.progressActive ? Colors.primary : Colors.card_secondary
        opacity: root.progressActive ? 0.9 : 1
    }
}
