"use strict";

// The pure privacy rule: fold, tag, record validation and the real check.
//
// The tag is a cheap QML pre-filter (one hex digit); the real comparison is
// the scrypt key, reproduced here with node's own implementation so the Python
// helper and the app can never drift apart silently.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");

const privacy = require("../services/privacy.js");

const md5 = (text) => crypto.createHash("md5").update(text, "utf8").digest("hex");

// Node's scrypt, adapted to the injected signature.
const scrypt = (word, salt, n, r, p, dklen) =>
    crypto.scryptSync(word, Buffer.from(salt), dklen,
        { N: n, r: r, p: p, maxmem: 2 ** 28 }).toString("hex");

const RECORD = {
    v: 1,
    salt: "0123456789abcdef0123456789abcdef",
    tag: md5("0123456789abcdef0123456789abcdef" + "muneca")[0],
    n: 131072,
    r: 8,
    p: 1,
    dk: scrypt("muneca", Buffer.from("0123456789abcdef0123456789abcdef", "hex"),
        131072, 8, 1, 32)
};

test("fold matches the CLI: lowercase, NFD, strip marks, trim", () => {
    assert.equal(privacy.foldWord("  Muñeca  "), "muneca");
    assert.equal(privacy.foldWord("MUNECA"), "muneca");
    assert.equal(privacy.foldWord("ÁÉÍÓÚÜ"), "aeiouu");
    assert.equal(privacy.foldWord(null), "");
});

test("the tag is the first hex digit of MD5 over salt + folded word", () => {
    // MD5("abc") is a published vector; the salt is concatenated as text.
    assert.equal(privacy.tagOf(md5, "", "abc"), "9");
    assert.equal(privacy.tagOf(md5, "salt", "Muñeca"),
        md5("salt" + "muneca")[0]);
});

test("an accent-folded word matches the stored tag", () => {
    assert.equal(privacy.tagMatches(md5, RECORD, "MUÑECA"), true);
    assert.equal(privacy.tagMatches(md5, RECORD, "muneca "), true);
    assert.equal(privacy.tagMatches(md5, RECORD, "otra"), false);
});

test("the scrypt check accepts the word and rejects another", () => {
    assert.equal(privacy.verify(scrypt, RECORD, "Muñeca"), true);
    assert.equal(privacy.verify(scrypt, RECORD, "muneca"), true);
    assert.equal(privacy.verify(scrypt, RECORD, "muneco"), false);
});

test("scrypt matches the published RFC 7914 vector", () => {
    const dk = crypto.scryptSync("password", "NaCl", 64,
        { N: 1024, r: 8, p: 16, maxmem: 2 ** 28 }).toString("hex");
    assert.equal(dk,
        "fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b373162" +
        "2eaf30d92e22a3886ff109279d9830dac727afb94a83ee6d8360cbdfa2cc0640");
});

test("a well-formed record parses", () => {
    assert.deepEqual(privacy.parse(JSON.stringify(RECORD)), RECORD);
});

test("malformed records are rejected, never half-trusted", () => {
    const bad = [
        "",
        "not json",
        JSON.stringify({ ...RECORD, v: 2 }),
        JSON.stringify({ ...RECORD, salt: "abc" }),
        JSON.stringify({ ...RECORD, tag: "zz" }),
        JSON.stringify({ ...RECORD, dk: "00" }),
        JSON.stringify({ ...RECORD, n: 1024 }),
        JSON.stringify({ ...RECORD, r: 1 }),
        JSON.stringify({ ...RECORD, p: 2 }),
        JSON.stringify({ ...RECORD, salt: "Z".repeat(32) })
    ];
    for (const text of bad) assert.equal(privacy.parse(text), null, text);
});

test("source scan: the word never reaches a log call", () => {
    const fs = require("node:fs");
    const path = require("node:path");
    const root = path.resolve(__dirname, "..");
    for (const file of ["services/Privacy.qml", "services/privacy.js",
        "scripts/privado.py"]) {
        const text = fs.readFileSync(path.join(root, file), "utf8");
        assert.doesNotMatch(text, /console\.(log|warn|error)\s*\([^)]*(word|searchText)/i,
            file + " logs the secret candidate");
        assert.doesNotMatch(text, /\bprint\s*\([^)]*(word|dk|tag|salt)/i,
            file + " prints a secret value");
    }
});
