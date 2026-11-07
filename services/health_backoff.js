// Backoff math for the backend health poll and the respawn timer.
//
// Plain functions so tests/health_backoff.test.js can exercise them without a
// Wayland session. `attempt` is the number of failures already counted.

function nextDelay(attempt, initial, maximum) {
    if (attempt <= 0) return initial;
    return Math.min(initial * Math.pow(2, attempt), maximum);
}

function exhausted(attempts, maximum) {
    return attempts >= maximum;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        nextDelay: nextDelay,
        exhausted: exhausted
    };
}
