// The private mode's pure rules: the folded word, the cheap tag and the record.
//
// The app itself never derives the key: the helper (`scripts/privado.py`) reads
// the word from stdin and compares the scrypt key. QML only computes the tag to
// decide whether a keystroke is worth handing to the helper at all. `verify()`
// exists for tests and for the CLI test to prove both sides agree.
//
// Record (privacy.json, mode 0600):
//   { v: 1, salt: 32 hex, tag: 1 hex, n: 131072, r: 8, p: 1, dk: 64 hex }
// word = fold plus trim, UTF-8. tag = first hex digit of MD5(salt + word).
// dk = scrypt(word, salt, n, r, p, maxmem=2**28, dklen=32).

var VERSION = 1;
var MIN_WORD_LENGTH = 8;
var N = 131072;
var R = 8;
var P = 1;

var HEX32 = /^[0-9a-f]{32}$/;
var HEX64 = /^[0-9a-f]{64}$/;
var HEX1 = /^[0-9a-f]$/;

// Same rule as `fold()` in services/library_filter.js and the CLI: lowercase,
// NFD, strip combining marks, trim. Written here again on purpose: the secret
// rule must not change because the search rule changes.
function foldWord(text) {
    var s = String(text === undefined || text === null ? "" : text).toLowerCase();
    if (typeof s.normalize === "function") {
        s = s.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    }
    return s.trim();
}

function tagOf(md5, salt, word) {
    if (typeof md5 !== "function") throw new Error("privacy: md5 function required");
    return String(md5(String(salt === undefined || salt === null ? "" : salt)
        + foldWord(word)))[0];
}

function parse(text) {
    var data;
    try {
        data = JSON.parse(String(text === undefined || text === null ? "" : text));
    } catch (e) {
        return null;
    }
    if (!data || typeof data !== "object" || Array.isArray(data)) return null;
    if (data.v !== VERSION) return null;
    if (typeof data.salt !== "string" || !HEX32.test(data.salt)) return null;
    if (typeof data.tag !== "string" || !HEX1.test(data.tag)) return null;
    if (typeof data.dk !== "string" || !HEX64.test(data.dk)) return null;
    if (data.n !== N || data.r !== R || data.p !== P) return null;
    return { v: VERSION, salt: data.salt, tag: data.tag, n: N, r: R, p: P, dk: data.dk };
}

function tagMatches(md5, record, word) {
    if (!record || typeof md5 !== "function") return false;
    return tagOf(md5, record.salt, word) === record.tag;
}

// Constant-time-ish comparison of the derived key with the stored one. The
// real check runs in Python with hmac.compare_digest; this one exists so the
// JS and Python sides can be tested against the same record.
function sameHex(a, b) {
    var left = String(a);
    var right = String(b);
    if (left.length !== right.length) return false;
    var diff = 0;
    for (var i = 0; i < left.length; i++) {
        diff |= left.charCodeAt(i) ^ right.charCodeAt(i);
    }
    return diff === 0;
}

// scrypt(word, saltBytes, n, r, p, dklen) -> hex string. Injected so the pure
// module has no crypto dependency and QML never needs one.
function verify(scrypt, record, word) {
    if (!record || typeof scrypt !== "function") return false;
    try {
        var salt = [];
        for (var i = 0; i < record.salt.length; i += 2) {
            salt.push(parseInt(record.salt.slice(i, i + 2), 16));
        }
        var got = scrypt(foldWord(word), salt, record.n, record.r, record.p, 32);
        return sameHex(got, record.dk);
    } catch (e) {
        return false;
    }
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        VERSION: VERSION,
        MIN_WORD_LENGTH: MIN_WORD_LENGTH,
        N: N,
        R: R,
        P: P,
        foldWord: foldWord,
        tagOf: tagOf,
        parse: parse,
        tagMatches: tagMatches,
        verify: verify
    };
}
