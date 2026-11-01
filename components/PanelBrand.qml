import QtQuick
import qs.app
import qs.Commons

// The panel's brand: this panel's short name, in caps, no glyph.
//
// Injected into the shared PanelHeader as a Component, so the three readers do
// not carry three copies of the same row — a styling change lands here once
// instead of drifting across three files.
//
// Round 6: the caps and the missing glyph stopped being per-panel options when
// the owner made one header for all three. The caps are a rendering transform,
// not a different string: the i18n table keeps the product's own spelling
// ("MangaReader", "Anime", "Novel") and the brand reads as a wordmark.
Row {
    id: root

    property string title: ""
    property string fontFamily: Style.font.family

    StyledText {
        anchors.verticalCenter: parent.verticalCenter
        text: root.title
        color: Colors.on_surface
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.6
    }
}
