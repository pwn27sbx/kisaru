import QtQuick
import qs.app
import qs.Commons

// The panel's brand: the app glyph plus this panel's short name.
//
// Injected into the shared PanelHeader as a Component, so the three readers do
// not carry three copies of the same row — a styling or glyph change lands here
// once instead of drifting across three files.
Row {
    id: root

    property string title: ""
    property string fontFamily: Style.font.family
    // The manga panel asked for text only ("MangaReader", no icon); the other
    // two keep the glyph, so it is a per-caller switch.
    property bool showGlyph: true
    // The manga panel also sets its brand in caps (owner, round 4). It is a
    // rendering transform, not a different string: the i18n table keeps the
    // product's own spelling and letter-spacing follows the caps look.
    property bool uppercaseTitle: false

    spacing: Style.spacing.sm

    // `visible` alone is enough: a Row does not allocate space for an
    // invisible item, and binding width to implicitWidth only risks a loop.
    MaterialIcon {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.showGlyph
        text: "󰂺"
        font.pixelSize: Style.font.icon
        color: Colors.primary
    }

    StyledText {
        anchors.verticalCenter: parent.verticalCenter
        text: root.title
        color: Colors.on_surface
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        font.capitalization: root.uppercaseTitle ? Font.AllUppercase : Font.MixedCase
        font.letterSpacing: root.uppercaseTitle ? 0.6 : 0
    }
}
