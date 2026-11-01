import QtQuick
import qs.app
import qs.Commons

// Horizontal filter chips shared by the three Browse views (plan R2 §2.2).
//
// The active chip is a SOLID accent block with the dark bold label; the rest are
// muted with no fill and no border. Both readings come from components/Chip and
// the tested recipe in services/header_cell.js (owner, round 6 for the fill,
// A-8 for the dark bold label).
//
// `options` is a string[] or an array of { label } objects; `currentIndex`
// marks the active one and `activated(index)` reports a click. `label` is
// already localized by the caller, so a language toggle re-evaluates it.
//
// Chips that do not fit scroll horizontally instead of shrinking or wrapping;
// when they fit, the row does not move at all.
Item {
    id: root

    property var options: []
    property int currentIndex: -1
    property string fontFamily: Style.font.family

    signal activated(int index)

    implicitHeight: Style.space(48)

    function labelOf(option) {
        return (option && typeof option === "object") ? String(option.label) : String(option)
    }

    Flickable {
        id: scroller
        anchors {
            fill: parent
            leftMargin: Style.spacing.md
            rightMargin: Style.spacing.md
            topMargin: Style.spacing.sm
            bottomMargin: Style.spacing.sm
        }
        contentWidth: chips.width
        contentHeight: height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentWidth > width

        Row {
            id: chips
            height: scroller.height
            spacing: Style.spacing.sm

            Repeater {
                model: root.options

                // components/Chip, not a kit Button: Button paints the selected
                // label from the theme's light `selected-color`, which is why
                // the active chip read light on orange (owner, A-8).
                delegate: Chip {
                    required property var modelData
                    required property int index

                    text: root.labelOf(modelData)
                    current: index === root.currentIndex
                    bodyFont: root.fontFamily
                    onClicked: root.activated(index)
                }
            }
        }
    }
}
