// The keyboard and label logic of a MenuSelect (components/MenuSelect.qml).
//
// A dropdown is three questions and one state: which row is current, which row
// is highlighted, and where the highlight goes on ↑/↓. They live here so they
// can be tested without a screen, the same way header_cell.js and list_metrics.js
// are (owner, §32.2).
//
// Options are [{ label, value }] and values are strings or numbers.

// The row whose value matches, or -1.
function indexOf(options, value) {
    for (var i = 0; i < (options ? options.length : 0); i++) {
        if (options[i].value === value) return i;
    }
    return -1;
}

// What the button shows: the matching label, else the fallback, else the first
// option's label, else "". A dropdown always has to name something.
function labelFor(options, value, fallback) {
    var i = indexOf(options, value);
    if (i >= 0) return options[i].label;
    if (fallback !== undefined && fallback !== null && fallback !== "") return fallback;
    return options && options.length ? options[0].label : "";
}

// ↑/↓ move the highlight and stop at the ends: a five-item filter is not a
// wheel, and wrapping surprises a keyboard user.
function next(index, count, delta) {
    if (!count || count < 1) return -1;
    var from = index < 0 ? (delta > 0 ? -1 : count) : index;
    var to = from + delta;
    if (to < 0) return 0;
    if (to > count - 1) return count - 1;
    return to;
}

// Where the highlight starts when the menu opens: the current row, or the first.
function openingIndex(options, value) {
    var i = indexOf(options, value);
    return i >= 0 ? i : 0;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        indexOf: indexOf,
        labelFor: labelFor,
        next: next,
        openingIndex: openingIndex
    };
}
