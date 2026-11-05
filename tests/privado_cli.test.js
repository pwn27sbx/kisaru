"use strict";

// The private-mode helper, run as a user would run it.
//
// Every run here is sandboxed: temporary HOME, temporary XDG_DATA_HOME and a
// test word. The owner's real library is never read or written, and the word is
// never printed by the helper, the app, or this test.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const SCRIPT = path.join(ROOT, "scripts", "privado.py");
const BIN = path.join(ROOT, "bin", "kisaru");

const PYTHON = process.env.PYTHON || "python3";
const WORD = "MuñecaSegura";   // a test word, only ever used in a sandbox

function sandbox() {
    const home = fs.mkdtempSync(path.join(os.tmpdir(), "kisaru-privado-"));
    const data = path.join(home, "data");
    fs.mkdirSync(data, { recursive: true });
    return {
        home,
        data,
        path: path.join(data, "kisaru", "privacy.json"),
        env: { HOME: home, XDG_DATA_HOME: data }
    };
}

function run(args, input, env) {
    return spawnSync(PYTHON, [SCRIPT, ...args], {
        encoding: "utf8",
        timeout: 60000,
        input: input === undefined ? "" : input,
        env: { ...process.env, ...env }
    });
}

const scrypt = (word, salt, n, r, p, dklen) =>
    crypto.scryptSync(word, Buffer.from(salt), dklen,
        { N: n, r: r, p: p, maxmem: 2 ** 28 }).toString("hex");

test("checking before a word exists is an error, never a match", () => {
    const box = sandbox();
    const result = run(["--check", box.path], WORD, box.env);
    assert.equal(result.status, 2);
    assert.equal(result.stdout, "");
    assert.equal(result.stderr, "");
});

test("the helper writes a valid record, mode 0600, and prints nothing secret", () => {
    const box = sandbox();
    const setup = run([], WORD + "\n" + WORD + "\n", box.env);
    assert.equal(setup.status, 0, setup.stderr);
    assert.ok(!setup.stdout.includes(WORD) && !setup.stderr.includes(WORD),
        "the helper echoed the word");

    const stat = fs.statSync(box.path);
    assert.equal(stat.mode & 0o777, 0o600);

    const record = JSON.parse(fs.readFileSync(box.path, "utf8"));
    assert.equal(record.v, 1);
    assert.equal(record.n, 131072);
    assert.equal(record.r, 8);
    assert.equal(record.p, 1);
    assert.match(record.salt, /^[0-9a-f]{32}$/);
    assert.match(record.tag, /^[0-9a-f]$/);
    assert.match(record.dk, /^[0-9a-f]{64}$/);

    // The tag and the key are over the folded word, exactly like the app.
    const md5 = crypto.createHash("md5").update(record.salt + "munecasegura", "utf8").digest("hex");
    assert.equal(record.tag, md5[0]);
    assert.equal(record.dk,
        scrypt("munecasegura", Buffer.from(record.salt, "hex"), 131072, 8, 1, 32));
});

test("the check accepts the word, its folded forms, and nothing else", () => {
    const box = sandbox();
    assert.equal(run([], WORD + "\n" + WORD + "\n", box.env).status, 0);

    for (const word of [WORD, "MUNECASEGURA", "  muñecasegura  "]) {
        const result = run(["--check", box.path], word, box.env);
        assert.equal(result.status, 0, "folded word did not match");
        assert.equal(result.stdout + result.stderr, "");
    }
    const wrong = run(["--check", box.path], "otra palabra", box.env);
    assert.equal(wrong.status, 1);
    assert.equal(wrong.stdout + wrong.stderr, "");
});

test("fold parity with the JS check, using Muñeca", () => {
    // The setup path refuses short words, so a six-letter word is written as a
    // record here; the CLI still has to fold it exactly like services/privacy.js.
    const box = sandbox();
    const salt = "fedcba9876543210fedcba9876543210";
    const folded = "muneca";
    const md5 = crypto.createHash("md5").update(salt + folded, "utf8").digest("hex");
    const record = {
        v: 1, salt: salt, tag: md5[0], n: 131072, r: 8, p: 1,
        dk: scrypt(folded, Buffer.from(salt, "hex"), 131072, 8, 1, 32)
    };
    fs.mkdirSync(path.dirname(box.path), { recursive: true });
    fs.writeFileSync(box.path, JSON.stringify(record));

    const result = run(["--check", box.path], "MUÑECA", box.env);
    assert.equal(result.status, 0);
    assert.equal(result.stdout + result.stderr, "");

    const privacy = require("../services/privacy.js");
    assert.equal(privacy.tagMatches(
        (text) => crypto.createHash("md5").update(text, "utf8").digest("hex"), record, "Muñeca"), true);
    assert.equal(privacy.verify(scrypt, record, "muñeca"), true);
});

test("a malformed file is an error, and stays untouched", () => {
    const box = sandbox();
    fs.mkdirSync(path.dirname(box.path), { recursive: true });
    fs.writeFileSync(box.path, "{ not json");
    const result = run(["--check", box.path], WORD, box.env);
    assert.equal(result.status, 2);
    assert.equal(fs.readFileSync(box.path, "utf8"), "{ not json");
});

test("a word under 8 characters is refused and no file is written", () => {
    const box = sandbox();
    const result = run([], "corta\ncorta\n", box.env);
    assert.notEqual(result.status, 0);
    assert.ok(!fs.existsSync(box.path));
});

test("replacing an existing word needs a confirmation", () => {
    const box = sandbox();
    assert.equal(run([], WORD + "\n" + WORD + "\n", box.env).status, 0);
    const before = fs.readFileSync(box.path, "utf8");

    const refused = run([], "n\n", box.env);
    assert.notEqual(refused.status, 0);
    assert.equal(fs.readFileSync(box.path, "utf8"), before);
});

test("kisaru privado runs the helper from the config folder, out of --help", () => {
    const box = sandbox();
    const cfg = path.join(box.home, "cfg", "kisaru");
    fs.mkdirSync(path.join(cfg, "scripts"), { recursive: true });
    fs.writeFileSync(path.join(cfg, "shell.qml"), "");
    fs.copyFileSync(SCRIPT, path.join(cfg, "scripts", "privado.py"));

    const result = spawnSync("bash", [BIN, "privado"], {
        encoding: "utf8",
        timeout: 60000,
        input: WORD + "\n" + WORD + "\n",
        env: { ...process.env, HOME: box.home, XDG_CONFIG_HOME: path.join(box.home, "cfg"),
            XDG_DATA_HOME: box.data }
    });
    assert.equal(result.status, 0, result.stderr);
    assert.ok(fs.existsSync(box.path), "the command did not write the secret");

    // The help gives no hint that the mode exists.
    const help = spawnSync("bash", [BIN, "--help"], { encoding: "utf8" });
    assert.doesNotMatch(help.stdout, /privado|privacidad|secreta/i);
});
