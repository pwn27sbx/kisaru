import QtQuick
import qs.Commons
import qs.app

// The poster tile shared by the manga / anime / novel grids: cover art with a
// placeholder and bottom fade, an optional type badge, a solid info block with
// the metadata line and a two-line title, and press/hover feedback.
//
// Anything else the grid needs — a score badge, the progress strip — is added as
// an ordinary child. Tell the card how tall the bottom strip is via `footerHeight`
// so the cover and title bar size around it. The hover tint keeps a high `z` so it
// still sits above those children, as it did when it was declared last.
//
// Two anatomies share this component:
//   `variant: "classic"` (default) — the poster tile anime, novel and the
//     library have always drawn: inset artwork, a solid title bar, the badge
//     trailing. Untouched geometry, so those panels do not move.
//   `variant: "stitch"` — the manga grid's card from the Stitch reference: the
//     artwork runs flush to the card's top and sides, a three-stop scrim fades
//     its bottom into the card's own surface, and the block below carries the
//     title plus a chapter/status row.
ClickableRect {
    id: root

    property url source: ""
    property string title: ""
    property string bodyFont: ""
    // "classic" | "stitch" — see the header.
    property string variant: "classic"
    readonly property bool stitch: variant === "stitch"
    // Display text for the type badge ("MANHWA", "MANGA", …). Callers pass it
    // already localized and cased; an empty string hides the badge.
    property string typeBadge: ""
    // The work's own metadata ("Cap. 105 · En curso"), never the reader's
    // progress: Library's CoverProgressBar owns that and lives in the footer.
    // It sits in the info block, under the title — painting it over the artwork
    // was unreadable, because the cover is a photo, not a backdrop.
    property string meta: ""
    // The stitch card splits that metadata into the row Stitch draws: chapter
    // on the left with tabular digits, status on the right. `metaTone` is the
    // "done" | "live" | "warn" | "muted" answer from services/manga_card.js;
    // the classic card ignores all three.
    property string metaChapter: ""
    property string metaStatus: ""
    property string metaTone: "muted"
    // Title bar padding. Browse's old inline delegate used 18 px and this card
    // used 10, so unifying them without this prop would move the cover 8 px.
    property int titlePadding: 10
    property int gradientHeight: 48
    property int footerHeight: 0
    // Cover inset inside the card. `0` keeps the original poster tiles, where
    // the artwork reaches the card's edges; a positive value turns the cover
    // into a picture inside a panel, with this card's own surface showing
    // around it.
    property int inset: 0
    // Which top corner carries the type badge. `false` is the original
    // top-right slot (anime and the novel panel); `true` moves it to the
    // leading corner, above the title. The stitch card always leads.
    property bool badgeLeading: false

    // ── Stitch anatomy ────────────────────────────────────────────────────
    // Stitch's info block is p-2; the cover keeps the 3 / 4.4 poster ratio of
    // the reference (`aspect-[3/4.4]`), so its height is the card's width
    // times 4.4 / 3 and the card is one flush column.
    readonly property int _infoPadding: root.stitch ? Style.space(8) : root.titlePadding
    readonly property int _infoInset: root.stitch ? Style.space(8) : Style.spacing.xl
    // "MANHWA" / "MANHUA" take the accent; MANGA and anything else stay
    // neutral. The badge text is already uppercased and localized by the
    // caller, and neither type name is translated.
    readonly property bool _badgeAccent: {
        const badge = String(root.typeBadge).toLowerCase()
        return badge.indexOf("manhwa") === 0 || badge.indexOf("manhua") === 0
    }

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
    // Stitch separates the card from its neighbours with a 1 px hairline at
    // ~6 % foreground. The classic tile has no border (width 0 draws nothing),
    // so anime and the novel panel keep exactly the edge they have today.
    border.width: root.stitch ? Style.spacing.hairline : 0
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
            topMargin: root.inset
            leftMargin: root.inset
            rightMargin: root.inset
        }
        // The inset is taken off the cover as well, so its bottom edge still
        // meets the info block; with `inset: 0` this is the original height.
        // Stitch fixes the cover to the poster ratio instead and lets the info
        // block keep the rest of the cell, so the card has no gap under it.
        height: root.stitch
            ? root.width * (4.4 / 3)
            : root.height - root.inset - infoBlock.height - root.footerHeight
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

        // Classic: the short fade that has always sat under the solid info
        // block. Stitch: the reference's three-stop scrim over the WHOLE
        // cover, so the artwork dissolves into the card's own surface and the
        // text below reads on a near-solid area instead of on a photo.
        Rectangle {
            visible: !root.stitch
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: root.gradientHeight
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: Colors.surface_container }
            }
        }

        Rectangle {
            visible: root.stitch
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: parent.height
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Colors.withAlpha(Colors.surface_container, 0.55) }
                GradientStop { position: 1.0; color: Colors.surface_container }
            }
        }

        // Type badge (Manga / Manhwa / Manhua). Verbatim text: the caller
        // decides the casing, so Browse keeps the uppercased look it had. The
        // leading corner belongs to the stitch card and to Browse's old inset
        // tile; the trailing one is what anime and the novel panel show.
        Rectangle {
            visible: root.typeBadge !== ""
            anchors {
                top: parent.top
                left: (root.stitch || root.badgeLeading) ? parent.left : undefined
                right: (root.stitch || root.badgeLeading) ? undefined : parent.right
                // Stitch parks the badge at top-1.5 / left-1.5 of the cover.
                topMargin: root.stitch ? Style.space(6) : Style.spacing.lg
                leftMargin: root.stitch ? Style.space(6) : Style.spacing.lg
                rightMargin: Style.spacing.lg
            }
            height: root.stitch ? Style.space(14) : 20
            radius: Style.cornerRadius
            width: badgeText.implicitWidth + (root.stitch ? Style.space(8) : 14)
            // Stitch tints the long-form formats with the accent and leaves
            // MANGA on the card's own surface; both read as a small chip.
            color: root.stitch
                ? (root._badgeAccent
                    ? Colors.withAlpha(Colors.primary, 0.22)
                    : Colors.surface_container)
                : Qt.rgba(0, 0, 0, 0.7)
            border.width: root.stitch ? Style.spacing.hairline : 0
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
                color: root.stitch
                    ? (root._badgeAccent ? Colors.primary : Colors.on_surface_variant)
                    : Colors.primary_fixed_dim
            }
        }
    }

    // The solid info block under the cover: the title, then the metadata line.
    // Its height is the content's own, so an empty `meta` adds nothing and the
    // anime / novel tiles keep the exact title bar they have today. Library's
    // `cellHeight` is fixed, so a card that does carry metadata takes the
    // height from the cover, never from its neighbors.
    //
    // Same colour as the card in both variants, which is what makes Stitch's
    // scrim land on an area with no visible seam.
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
            // Order is title first, metadata second — the reference layout.
            // `spacing` only applies BETWEEN visible children, so with `meta`
            // empty the block is title + padding and does not grow.
            spacing: Style.spacing.xs

            StyledText {
                id: titleText
                width: parent.width
                text: root.title
                font.family: root.bodyFont
                font.pixelSize: Style.font.bodySmall
                // Stitch gets its hierarchy from weight: the title is the only
                // semibold line on the card. `Normal` is the default, so the
                // classic tiles are untouched.
                font.weight: root.stitch ? Font.DemiBold : Font.Normal
                font.letterSpacing: 0.2
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                lineHeight: 1.3
            }

            StyledText {
                id: metaText
                visible: root.meta !== "" && !root.stitch
                width: parent.width
                text: root.meta
                font.family: root.bodyFont
                font.pixelSize: Style.font.caption
                font.letterSpacing: 0.3
                color: Colors.on_surface_variant
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            // Stitch's meta row: chapter on the left, state on the right. The
            // chapter keeps tabular digits so its numbers line up down the
            // column; the state takes a tone (see `metaTone`). Both shrink with
            // an ellipsis instead of pushing through each other.
            Item {
                id: metaRow
                visible: root.stitch
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
                    // The tones the card knows. `live` and `muted` share the
                    // same muted role on purpose: a work that is publishing
                    // says nothing the reader needs to act on.
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
