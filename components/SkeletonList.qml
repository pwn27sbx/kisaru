pragma ComponentBehavior: Bound

import QtQuick
import qs.app
import qs.Commons
import "../services/list_metrics.js" as ListMetrics

// Placeholder rows for a list while it fetches, rippling top to bottom. Row
// height and divider inset match the real list, and so does the shape of the
// row: `cover: true` draws the cover of a ListRow, otherwise a chapter row's
// number pill and title (plus a subtitle line when `subtitle` is set).
//
// A-9: the Browse and Library ghosts stand in for ListRow, so they draw the
// same 64 x 90 cover from services/list_metrics.js — a ghost of the wrong shape
// makes the panel jump the moment the data lands.
Rectangle {
    id: root

    property bool active: false
    property int rowHeight: 58
    property bool subtitle: true
    property int dividerInset: 72
    // True for the lists whose real row is a ListRow (cover on the left).
    property bool cover: false
    // The list row's own type scale, so the ghost's bars are the row's lines.
    property real titleHeight: Style.font.heading
    property real datumHeight: Style.font.caption

    color: Colors.background
    clip: true
    opacity: root.active ? 1 : 0
    visible: root.opacity > 0
    Behavior on opacity { NumberAnimation { duration: Motion.slow; easing.type: Motion.easeOut } }

    Column {
        anchors { left: parent.left; right: parent.right }

        Repeater {
            model: root.visible ? Math.ceil(root.height / root.rowHeight) : 0

            delegate: Item {
                id: row
                required property int index

                width: parent.width
                height: root.rowHeight

                Item {
                    id: content
                    anchors {
                        fill: parent
                        leftMargin: root.cover ? root.dividerInset : Style.space(16)
                        rightMargin: Style.space(16)
                    }

                    // A chapter row's number pill.
                    Rectangle {
                        id: pill
                        visible: !root.cover
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44; height: 26; radius: height / 2 // style-ignore — skeleton
                        color: Colors.surface_container_high
                    }

                    // A list row's cover: the same box the real thumbnail takes.
                    Rectangle {
                        id: coverGhost
                        visible: root.cover
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        width: Style.space(ListMetrics.THUMB_WIDTH)
                        height: Style.space(ListMetrics.THUMB_HEIGHT)
                        radius: Style.cornerRadius
                        color: Colors.surface_container
                    }

                    Column {
                        anchors {
                            left: root.cover ? coverGhost.right : pill.right
                            leftMargin: root.cover ? Style.spacing.xl : Style.spacing.xxxl
                            right: parent.right; rightMargin: Style.space(24)
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: root.cover ? Style.spacing.md : Style.space(7)

                        Rectangle {
                            // Varied so the rows don't read as a barcode.
                            width: parent.width * [0.62, 0.48, 0.7, 0.55, 0.4][row.index % 5]
                            height: root.cover ? root.titleHeight : 9
                            radius: height / 2 // style-ignore — skeleton
                            color: Colors.surface_container_high
                        }
                        Rectangle {
                            visible: root.subtitle
                            width: 64
                            height: root.cover ? root.datumHeight : 7
                            radius: height / 2 // style-ignore — skeleton
                            color: Colors.surface_container
                        }
                    }
                }

                Rectangle {
                    anchors {
                        bottom: parent.bottom
                        left: parent.left; right: parent.right
                        leftMargin: root.dividerInset; rightMargin: Style.space(16)
                    }
                    height: 1; color: Colors.outline_variant; opacity: 0.2
                }

                SkeletonPulse {
                    target: content
                    delay: row.index * 90
                    running: root.visible
                }
            }
        }
    }
}
