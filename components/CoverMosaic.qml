import QtQuick
import qs.app
import qs.Commons
import qs.components

// The little collage on a folder card or row: up to four covers.
//
// One cover fills the box, two split it into columns, three put one large on
// the left and two stacked on the right, four make the 2x2 mosaic. An empty
// folder shows the folder glyph. It only draws the URLs it is given: the
// caller passes covers from the visible list, so a hidden title can never be
// painted here.
Item {
    id: root

    property var covers: []
    property bool ready: true
    // The glyph size of the empty state: a full card and a row differ.
    property int glyphSize: Style.font.heading

    function _box(index) {
        var gap = Math.max(1, Style.spacing.hairline)
        var w = root.width
        var h = root.height
        var halfW = (w - gap) / 2
        var halfH = (h - gap) / 2
        var count = root.covers ? root.covers.length : 0

        if (count <= 1) return { x: 0, y: 0, w: w, h: h }
        if (count === 2) {
            return index === 0
                ? { x: 0, y: 0, w: halfW, h: h }
                : { x: halfW + gap, y: 0, w: halfW, h: h }
        }
        if (count === 3) {
            if (index === 0) return { x: 0, y: 0, w: halfW, h: h }
            return index === 1
                ? { x: halfW + gap, y: 0, w: halfW, h: halfH }
                : { x: halfW + gap, y: halfH + gap, w: halfW, h: halfH }
        }
        var column = index % 2
        var row = Math.floor(index / 2)
        return {
            x: column === 0 ? 0 : halfW + gap,
            y: row === 0 ? 0 : halfH + gap,
            w: halfW,
            h: halfH
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Colors.surface_container_high
        visible: root.covers.length === 0
    }

    MaterialIcon {
        anchors.centerIn: parent
        visible: root.covers.length === 0
        text: "󰉋"
        font.pixelSize: root.glyphSize
        color: Colors.on_surface_variant
        opacity: 0.6
    }

    Repeater {
        model: root.covers

        delegate: Image {
            required property int index
            required property var modelData

            readonly property var box: root._box(index)
            x: box.x
            y: box.y
            width: box.w
            height: box.h
            source: root.ready ? String(modelData || "") : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            clip: true
        }
    }
}
