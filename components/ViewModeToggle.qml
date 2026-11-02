import QtQuick
import qs.app
import qs.Commons
import qs.services
import qs.Ui

// The grid/list toggle, one control for the six views (owner, round 6).
//
// Two icon cells, no frame (owner §30): the boxed surface around them did not
// match the chips' height and read as a defect. Each cell is exactly as tall as
// a filter chip — both are a line of body text plus the control padding — and
// the selected one uses the chip's own selected recipe (solid accent, dark bold
// glyph), so the row reads as one family of controls.
//
// The view tells it its panel and its current layout; the control writes the
// preference itself, through the same `UiPrefs` every panel already uses. Its
// right edge is the caller's job: each row pins it to its grid's right edge.
Row {
    id: root

    // "manga" | "anime" | "novel": which panel's preference this writes.
    required property string panel
    required property bool listMode
    property string fontFamily: Style.font.family

    spacing: Style.spacing.xxs

    ViewModeChip {
        glyph: "▦"
        label: I18n.t("view.grid")
        current: !root.listMode
        bodyFont: root.fontFamily
        onClicked: UiPrefs.setViewMode(root.panel, "grid")
    }

    ViewModeChip {
        glyph: "☰"
        label: I18n.t("view.list")
        current: root.listMode
        bodyFont: root.fontFamily
        onClicked: UiPrefs.setViewMode(root.panel, "list")
    }
}
