import QtQuick
import qs.app
import qs.Commons
import qs.services
import qs.Ui

// The grid/list toggle, one control for the six views (owner, round 6).
//
// One segmented box: a faint surface, a hairline, the theme radius and the two
// cells inside. The views used to carry a copy each — six copies of one control,
// which is exactly what a shared component is for.
//
// The view tells it its panel and its current layout; the control writes the
// preference itself, through the same `UiPrefs` every panel already uses.
Rectangle {
    id: root

    // "manga" | "anime" | "novel": which panel's preference this writes.
    required property string panel
    required property bool listMode
    property string fontFamily: Style.font.family

    implicitWidth: cells.implicitWidth + 2 * Style.spacing.xxs
    implicitHeight: cells.implicitHeight + 2 * Style.spacing.xxs
    radius: Style.cornerRadius
    color: Colors.surface_container
    border.width: Style.spacing.hairline
    border.color: Colors.outline_variant

    Row {
        id: cells
        x: Style.spacing.xxs
        y: Style.spacing.xxs
        spacing: Style.spacing.xxs

        ViewModeChip {
            glyph: "▦"
            label: I18n.t("view.grid")
            current: !root.listMode
            bodyFont: root.fontFamily
            cellSize: Style.space(22)
            onClicked: UiPrefs.setViewMode(root.panel, "grid")
        }

        ViewModeChip {
            glyph: "☰"
            label: I18n.t("view.list")
            current: root.listMode
            bodyFont: root.fontFamily
            cellSize: Style.space(22)
            onClicked: UiPrefs.setViewMode(root.panel, "list")
        }
    }
}
