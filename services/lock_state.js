// The lock state machine, pure so every trigger can be pinned without a screen.
//
// Locked is the initial state: the process starts locked. A word verified by
// the helper toggles it, so typing the word again locks. Every other trigger
// (close, minimize, panel switch, padlock) is the same `lock` action, because
// the shell cannot tell those apart and does not need to.
//
// A generation counter separates "the word the user is typing now" from a
// helper that answers late: only the current generation may change the state.

var LOCK = "lock";
var START = "start";
var SETTLE = "settle";
var CANCEL = "cancel";

function initial() {
    return { locked: true, generation: 0, checking: false };
}

function reduce(state, action) {
    var current = state || initial();
    var type = action ? action.type : "";

    if (type === LOCK) {
        return { locked: true, generation: current.generation + 1, checking: false };
    }
    if (type === START) {
        return { locked: current.locked, generation: current.generation + 1, checking: true };
    }
    if (type === CANCEL) {
        return { locked: current.locked, generation: current.generation + 1, checking: false };
    }
    if (type === SETTLE) {
        // A stale answer is not an answer.
        if (action.generation !== current.generation) return current;
        if (action.ok !== true)
            return { locked: current.locked, generation: current.generation, checking: false };
        return { locked: !current.locked, generation: current.generation, checking: false };
    }
    return current;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        LOCK: LOCK,
        START: START,
        SETTLE: SETTLE,
        CANCEL: CANCEL,
        initial: initial,
        reduce: reduce
    };
}
