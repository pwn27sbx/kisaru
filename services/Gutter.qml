// The one content gutter the top zone and the grids share (owner, §32.1).
//
// The rule is "one left edge and one right edge": the filter dropdown, the
// search row, the grid's first card and the list's rows all start at `left`,
// and the toggle, the last card and the last row all end at `right`. The
// scrollbar's lane (§31) lives OUTSIDE `right`, which is why the right gutter
// is one lane wider than the left one.
pragma Singleton
import QtQuick
import Quickshell
import qs.Commons
import "scroll_metrics.js" as Metrics

Singleton {
    id: root

    readonly property int left: Style.spacing.lg
    readonly property int right: Style.spacing.lg + Style.space(Metrics.LANE)
}
