// The one content gutter the top zone and the grids share (owner, §32.1).
//
// The rule is "one left edge and one right edge", measured on what the eye sees:
// the filter menu's text, the grid's first card, the list's rows and the tool bar
// all start on the same line, and the toggle's last glyph, the last card and the
// last row end on the same line. `ink` is the card's own inner margin, the
// distance between a cell's box and the visible card, so the controls line their
// ink up with the cards' ink instead of with their boxes (owner, 2026-11-02).
pragma Singleton
import QtQuick
import Quickshell
import qs.Commons
import "scroll_metrics.js" as Metrics

Singleton {
    id: root

    // Both sides are the same number (owner, 2026-11-02): the visible space
    // between the panel edge and the content must be equal left and right. The
    // scrollbar lives INSIDE this gutter instead of adding a lane of its own, so
    // the extra width §31 gave it is gone.
    readonly property int left: Style.spacing.lg
    readonly property int right: Style.spacing.lg

    // The card's own inner margin (components/CoverCard.qml). The grid's box is
    // not what the eye sees: the card's visible edge starts `ink` inside it, so
    // the controls align their INK here, not their boxes (owner, 2026-11-02).
    readonly property int ink: Style.space(5)
}
