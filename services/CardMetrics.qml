pragma Singleton
import QtQuick
import Quickshell
import qs.Commons
import "manga_card.js" as Card

// One source of truth for the card box, shared by the six grids and by the
// skeletons that stand in for them while a page loads.
//
// A cell is a poster column: the cover keeps the export's 3 / 4.4 ratio and the
// info band under it is content-sized (two title lines plus its metadata row and
// padding). Both numbers live in services/manga_card.js, which is tested there;
// this singleton only applies the theme's spacing scale and the column count,
// so a grid and its skeleton cannot disagree about either.
Singleton {
    id: root

    readonly property real coverRatio: Card.COVER_RATIO
    readonly property real infoBase: Card.INFO_BASE
    // Three columns in every panel (owner, round 6, D7).
    readonly property int columns: 3

    function cellHeight(cellWidth) {
        var width = Number(cellWidth)
        if (!isFinite(width) || width <= 0) return 0
        return width * root.coverRatio + Style.space(root.infoBase)
    }
}
