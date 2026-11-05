import QtQuick
import qs.Commons
import qs.app
import qs.services
import qs.components
import "../services/list_metrics.js" as ListMetrics

// The dashed card (or row) that ends the Library root and creates a folder.
ClickableRect {
    id: root

    // False: a grid card the size of a title card. True: a list row.
    property bool row: false
    property string bodyFont: ""

    implicitHeight: root.row ? Style.space(ListMetrics.ROW_HEIGHT_BASE) : 0
    color: "transparent"

    Item {
        id: frame
        anchors.fill: parent
        anchors.margins: root.row ? 0 : Style.space(5)

        Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: Colors.primary
            opacity: root.hovered ? Style.hoverFillAlpha : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }

        Canvas {
            id: dashes
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                var line = Math.max(1, Style.spacing.hairline)
                ctx.lineWidth = line
                ctx.strokeStyle = Colors.outline
                ctx.setLineDash([Style.space(4), Style.space(4)])
                var r = Style.cornerRadius
                var x = line / 2
                var y = line / 2
                var w = width - line
                var h = height - line
                ctx.beginPath()
                if (r > 0 && typeof ctx.roundRect === "function")
                    ctx.roundRect(x, y, w, h, r)
                else
                    ctx.rect(x, y, w, h)
                ctx.stroke()
            }
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Component.onCompleted: requestPaint()
        }

        // Grid: a column. List: one line, so the row reads like its neighbours.
        Column {
            visible: !root.row
            anchors.centerIn: parent
            spacing: Style.spacing.sm

            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "󰐕"
                font.pixelSize: Style.font.heading
                color: Colors.on_surface_variant
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.t("folder.create")
                font.family: root.bodyFont
                font.pixelSize: Style.font.bodySmall
                color: Colors.on_surface_variant
            }
        }

        Row {
            visible: root.row
            anchors.centerIn: parent
            spacing: Style.spacing.sm

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰐕"
                font.pixelSize: Style.font.body
                color: Colors.on_surface_variant
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.t("folder.create")
                font.family: root.bodyFont
                font.pixelSize: Style.font.body
                color: Colors.on_surface_variant
            }
        }
    }
}
