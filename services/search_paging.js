// How a merged search page moves the panel forward.
//
// A search page is the union of every source's window at the same offset, so it
// can be shorter than the offset jump (deduplication removes repeats) and, in
// the worst case, report more while the offset does not move at all. A page
// that does not advance must stop the paging: otherwise scrolling asks for the
// same window forever.
//
// Pure, so the paging rule is pinned by a node test instead of living in QML.

function _number(value, fallback) {
    var parsed = Number(value);
    return isFinite(parsed) ? Math.round(parsed) : fallback;
}

// currentOffset: where the request started; data: the chain's answer
// ({ nextOffset, hasMore }); itemCount: how many items arrived after merging.
function nextPage(currentOffset, data, itemCount) {
    var page = data || {};
    var current = Math.max(0, _number(currentOffset, 0));
    var count = Math.max(0, _number(itemCount, 0));
    var offset = page.nextOffset === undefined || page.nextOffset === null
        ? current + count
        : Math.max(0, _number(page.nextOffset, current + count));
    return {
        offset: offset,
        hasMore: page.hasMore === true && offset > current
    };
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { nextPage: nextPage };
}
