import QtQuick
import qs.Commons
import qs.app
import "../services/manga_card.js" as MangaCard

// The poster tile, shared by the three panels (owner, round 6).
//
// One anatomy, the Stitch export's: the cover runs flush to the card's top and
// sides, a three-stop scrim fades its bottom into the card's own surface, and
// the block below carries the title plus whatever second line the panel has.
// The block is painted that same surface, so there is no seam.
//
// Everything a panel may add is an optional slot, and every slot only paints
// when its data exists — no invented scores, no placeholder text:
//
//   typeBadge   top-left chip, the work's format ("MANHWA", "MOVIE")
//   cornerText  top-right chip: a score ("★ 8.4") or a state ("ONGOING")
//   cornerTone  that chip's colour role: done | live | warn (see statusTone)
//   episodesText bottom-right chip over the cover ("12 ep")
//   bookmarked  a small accent dot at the top centre (in the library)
//   author      a muted line under the title (novels)
//   metaChapter / metaStatus / metaTone  the row under the title (manga)
//   footer      children declared by the caller (the libraries' progress bar)
//
// The card is one column: cover (width * COVER_RATIO) plus the info block, so a
// grid cell and a ghost card are the same height (services/CardMetrics.qml).
ClickableRect {
    id: root

    property url source: ""
    property string title: ""
    property string bodyFont: ""

    property string typeBadge: ""
    // "" keeps the neutral chip, "accent" asks for the theme accent.
    property string badgeTone: ""

    property string cornerText: ""
    // "done" | "live" | "warn" | "" (neutral), from services/manga_card.js.
    property string cornerTone: ""
    // A score is not a state: the anime panel's "★ 8.8" takes the theme's
    // accent and the bold weight, so it reads on top of the artwork instead of
    // disappearing into it (owner, round 6).
    property bool cornerAccent: false

    property string episodesText: ""
    property bool bookmarked: false

    property string author: ""

    property string metaChapter: ""
    property string metaStatus: ""
    property string metaTone: "muted"

    // Height of the extra bottom strip (the libraries' progress row).
    property int footerHeight: 0

    readonly property int _infoPadding: Style.space(8)
    readonly property int _infoInset: Style.space(8)
    readonly property bool _badgeAccent: root.badgeTone === "accent"

    // Qt caches a FAILED image load per URL for the engine's lifetime, so one
    // request that lands while the local backend is restarting would leave the
    // tile broken until the shell restarts. Retry with a cache-busting token.
    property int _attempt: 0
    readonly property string _coverUrl: {
        const base = String(root.source || "")
        if (base === "") return ""
        if (root._attempt === 0) return base
        return base + (base.indexOf("?") >= 0 ? "&" : "?") + "retry=" + root._attempt
    }

    anchors.margins: Style.space(5)
    radius: Style.cornerRadius
    color: Colors.surface_container
    // A 1 px hairline at ~6 % foreground separates the card from its neighbours.
    border.width: Style.spacing.hairline
    border.color: Colors.withAlpha(Colors.on_surface, 0.06)
    clip: true

    // Beside the cover, not inside it: the cover sits at opacity 0 until it's
    // ready, which would hide a child placeholder too.
    CoverPlaceholder {
        anchors.fill: cover
        status: cover.status
    }

    Image {
        id: cover
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        // The poster ratio of the export: the info block keeps the rest of the
        // cell, so the card has no gap under the artwork.
        height: root.width * MangaCard.COVER_RATIO
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

        // One retry per failure, two in total: a backend that is briefly down
        // heals itself, a cover that is genuinely gone stops hammering.
        Timer {
            id: coverRetry
            interval: 1500
            onTriggered: root._attempt += 1
        }

        // The reference's three-stop scrim over the WHOLE cover, so the artwork
        // dissolves into the card's own surface and the text below reads on a
        // near-solid area instead of on a photo.
        Rectangle {
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: parent.height
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Colors.withAlpha(Colors.surface_container, 0.55) }
                GradientStop { position: 1.0; color: Colors.surface_container }
            }
        }

        // The work's format, leading corner. The caller decides the casing and
        // the accent (long-form formats take it; MANGA stays neutral).
        Rectangle {
            visible: root.typeBadge !== ""
            anchors {
                top: parent.top
                left: parent.left
                topMargin: Style.space(6)
                leftMargin: Style.space(6)
            }
            height: Style.space(14)
            radius: Style.cornerRadius
            width: badgeText.implicitWidth + Style.space(8)
            color: root._badgeAccent
                ? Colors.withAlpha(Colors.primary, 0.22)
                : Colors.surface_container
            border.width: Style.spacing.hairline
            border.color: root._badgeAccent
                ? Colors.withAlpha(Colors.primary, 0.45)
                : Colors.outline_variant

            StyledText {
                id: badgeText
                anchors.centerIn: parent
                text: root.typeBadge
                font.family: root.bodyFont
                font.pixelSize: 8 // style-ignore — bespoke size
                font.letterSpacing: 1
                font.bold: true
                color: root._badgeAccent ? Colors.primary : Colors.on_surface_variant
            }
        }

        // The score or the state, trailing corner. One slot for both: a panel
        // never has both, and the pair reads as "format left, state right".
        Rectangle {
            visible: root.cornerText !== ""
            anchors {
                top: parent.top
                right: parent.right
                topMargin: Style.space(6)
                rightMargin: Style.space(6)
            }
            height: Style.space(14)
            radius: Style.cornerRadius
            width: cornerLabel.implicitWidth + Style.space(8)
            color: Colors.withAlpha(Colors.surface_container, 0.85)
            border.width: Style.spacing.hairline
            border.color: Colors.outline_variant

            StyledText {
                id: cornerLabel
                anchors.centerIn: parent
                text: root.cornerText
                font.family: root.bodyFont
                font.pixelSize: 8 // style-ignore — bespoke size
                font.letterSpacing: 0.6
                font.bold: true
                // The same roles the info row uses, so a state reads the same
                // wherever it is painted; a score takes the accent instead of
                // the muted role, so it reads on top of the artwork.
                color: root.cornerAccent ? Colors.primary
                    : root.cornerTone === "done" ? Colors.primary
                    : root.cornerTone === "warn" ? Colors.error
                    : Colors.on_surface_variant
            }
        }

        // How many episodes the source actually has, on the artwork it belongs
        // to (the anime panel's badge).
        Rectangle {
            visible: root.episodesText !== ""
            anchors {
                bottom: parent.bottom
                right: parent.right
                bottomMargin: Style.space(6)
                rightMargin: Style.space(6)
            }
            height: Style.space(14)
            radius: Style.cornerRadius
            width: episodesLabel.implicitWidth + Style.space(8)
            color: Colors.withAlpha(Colors.surface_container, 0.9)
            border.width: Style.spacing.hairline
            border.color: Colors.outline_variant

            StyledText {
                id: episodesLabel
                anchors.centerIn: parent
                text: root.episodesText
                font.family: root.bodyFont
                font.pixelSize: 8 // style-ignore — bespoke size
                font.letterSpacing: 0.4
                color: Colors.on_surface_variant
            }
        }

        // In the library: a small accent dot, so a saved work is recognisable
        // without opening it.
        Rectangle {
            visible: root.bookmarked
            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: Style.spacing.md }
            width: Style.space(7)
            height: width
            radius: width / 2 // style-ignore — status dot
            color: Colors.primary
            opacity: 0.9
        }
    }

    // The info block under the cover: title first, then the second line the
    // panel has (author, chapter/state, nothing). Its height is its content's,
    // and it is painted the card's own surface so the scrim above it lands on
    // an area with no visible seam.
    Rectangle {
        id: infoBlock
        anchors {
            bottom: parent.bottom
            bottomMargin: root.footerHeight
            left: parent.left
            right: parent.right
        }
        height: infoColumn.implicitHeight + root._infoPadding
        color: Colors.surface_container

        Column {
            id: infoColumn
            anchors {
                left: parent.left
                leftMargin: root._infoInset
                verticalCenter: parent.verticalCenter
            }
            width: infoBlock.width - 2 * root._infoInset
            // `spacing` only applies BETWEEN visible children, so a card with
            // no second line is title + padding and does not grow.
            spacing: Style.spacing.xs

            StyledText {
                id: titleText
                width: parent.width
                text: root.title
                font.family: root.bodyFont
                font.pixelSize: Style.font.bodySmall
                // The hierarchy comes from weight: the title is the only
                // semibold line on the card.
                font.weight: Font.DemiBold
                font.letterSpacing: 0.2
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                lineHeight: 1.3
            }

            // The novel panel's author, under the title.
            StyledText {
                visible: root.author !== ""
                width: parent.width
                text: root.author
                font.family: root.bodyFont
                font.pixelSize: Style.font.caption
                font.letterSpacing: 0.3
                color: Colors.on_surface_variant
                opacity: 0.7
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            // The manga panel's row: chapter on the left, state on the right.
            // The chapter keeps tabular digits so its numbers line up down the
            // column; the state takes a tone (`metaTone`). Both shrink with an
            // ellipsis instead of pushing through each other.
            Item {
                id: metaRow
                visible: root.metaChapter !== "" || root.metaStatus !== ""
                width: parent.width
                height: Math.max(Style.space(13),
                                 chapterMeta.implicitHeight,
                                 statusMeta.implicitHeight)

                StyledText {
                    id: chapterMeta
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                    }
                    width: Math.min(implicitWidth, parent.width / 2)
                    text: root.metaChapter
                    font.family: root.bodyFont
                    font.pixelSize: Style.font.caption
                    // "Cap. 9" and "Cap. 179" must start at the same place;
                    // proportional digits make the column jitter. Qt 6.12
                    // takes OpenType features directly.
                    font.features: { "tnum": 1 }
                    color: Colors.on_surface_variant
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                StyledText {
                    id: statusMeta
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    width: Math.min(implicitWidth, parent.width / 2)
                    text: root.metaStatus
                    font.family: root.bodyFont
                    font.pixelSize: Style.font.caption
                    font.weight: Font.Medium
                    // `live` and `muted` share the muted role on purpose: a work
                    // that is publishing says nothing the reader must act on.
                    color: root.metaTone === "done" ? Colors.primary
                        : root.metaTone === "warn" ? Colors.error
                        : Colors.on_surface_variant
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }
    }

    Rectangle {
        z: 10
        anchors.fill: parent
        radius: root.radius
        color: Colors.primary
        opacity: root.pressed ? Style.pressedFillAlpha : (root.hovered ? Style.hoverFillAlpha : 0)
        Behavior on opacity { NumberAnimation { duration: Motion.base } }
    }

    transform: Scale {
        origin.x: root.width / 2
        origin.y: root.height / 2
        xScale: root.pressed ? 0.97 : 1.0
        yScale: root.pressed ? 0.97 : 1.0
        Behavior on xScale { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeOut } }
        Behavior on yScale { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeOut } }
    }
}
