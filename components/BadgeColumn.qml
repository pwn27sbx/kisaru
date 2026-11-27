import QtQuick
import qs.Commons
import "../services/list_badge.js" as ListBadge

// The fixed slot every badge of one list sits in.
//
// A badge's text width depends on its number — "Ch. 262.2" is wider than
// "Ch. 262" — so a pill sized to its own text pushed the titles of the rows
// after it to a different x (owner, 2026-11-27). The list now measures the
// widest badge it can show, once, from its model, and hands that width to every
// row's pill (components/ListBadge.qml): all titles start on the same line, and
// each row separator starts on the column's left edge.
//
// Independent of the delegates on purpose: a ListView only creates the rows on
// screen, so a maximum taken from the drawn pills would change while scrolling.
// The column is measured for the whole model instead.
Item {
    id: root

    // Every badge text the list can show, in model order.
    property var labels: []
    property string fontFamily: ""
    // Padded the same on both sides by the pill, so the two stay in step.
    property real paddingX: ListBadge.PADDING_X

    visible: false
    implicitWidth: root.columnWidth
    implicitHeight: 0

    // The pill's exact typography: family, size, weight and letter spacing all
    // move the advance, so each probe copies every one of them. A hidden Text
    // is the measuring tool (not TextMetrics) because letterSpacing is part of
    // the width the pill really paints.
    Repeater {
        id: probes
        model: root.labels || []

        delegate: Text {
            visible: false
            text: modelData
            font.family: root.fontFamily
            font.pixelSize: ListBadge.FONT_PIXEL_SIZE // style-ignore — bespoke size
            font.bold: true
            font.letterSpacing: ListBadge.LETTER_SPACING
        }
    }

    // Declarative on purpose: the width follows the model and the font by
    // itself, including a font that finishes loading after the first pass. An
    // imperative re-measure could miss exactly that.
    readonly property real columnWidth: {
        const widths = []
        for (let i = 0; i < probes.count; i++)
            widths.push(probes.itemAt(i).implicitWidth)
        return ListBadge.columnWidth(widths, root.paddingX)
    }
}
