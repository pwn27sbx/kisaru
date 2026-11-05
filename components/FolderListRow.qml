import QtQuick
import qs.Commons
import qs.app
import qs.services
import qs.components
import "../services/list_metrics.js" as ListMetrics

// The list twin of FolderCard: a row with a mini collage where a title's
// thumbnail sits, the folder name and its title count.
ClickableRect {
    id: root

    property var covers: []
    property bool coversReady: true
    property string name: ""
    property int count: 0
    property bool hidden: false
    property string bodyFont: ""
    property int inset: Style.spacing.xl

    implicitHeight: Style.space(ListMetrics.ROW_HEIGHT_BASE)
    color: "transparent"

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
        width: Style.space(ListMetrics.THUMB_WIDTH)
        height: Style.space(ListMetrics.THUMB_HEIGHT)
        radius: root.radius
        color: Colors.surface_container
        clip: true

        CoverMosaic {
            anchors.fill: parent
            covers: root.covers
            ready: root.coversReady
            glyphSize: Style.font.caption
        }
    }

    Column {
        anchors {
            left: coverBox.right
            right: parent.right
            leftMargin: root.inset
            rightMargin: root.inset
            verticalCenter: parent.verticalCenter
        }
        spacing: Style.space(ListMetrics.TEXT_GAP_BASE)

        StyledText {
            width: parent.width
            text: root.name
            font.family: root.bodyFont
            font.pixelSize: Math.round(Style.font.body * ListMetrics.TITLE_SCALE)
            font.bold: true
            font.letterSpacing: 0.2
            color: Colors.on_surface
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Row {
            width: parent.width
            spacing: Style.spacing.xs

            StyledText {
                text: I18n.tn("folder.count", root.count)
                font.family: root.bodyFont
                font.pixelSize: Math.round(Style.font.body * ListMetrics.DATUM_SCALE)
                font.letterSpacing: 0.3
                color: Colors.mix(Colors.on_surface_variant, Colors.on_surface, 0.35)
            }

            StyledText {
                visible: root.hidden
                text: "󰌾"
                font.family: "Material Design Icons"
                font.pixelSize: Math.round(Style.font.body * ListMetrics.DATUM_SCALE)
                color: Colors.on_surface_variant
            }
        }
    }

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
}
