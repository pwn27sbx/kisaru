"use strict";

// The release contract behind the updater (S8, A16).
//
// `kisaru update` advances to a tag `vX.Y.Z`; the banner compares the installed
// manifest version against those tags. Both only work while the manifest says
// the same number as the tag, so the release steps in the README are pinned
// here: bump the manifest, tag it without the `v`, push the tag.
//
// A checkout without tags (a shallow CI clone, or the repo before its first
// release) cannot check the match; the test skips instead of inventing one.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const MANIFEST = "omarchy/pwnsxb.kisaru/manifest.json";
const read = (rel) => fs.readFileSync(path.join(ROOT, rel), "utf8");

function manifestVersion() {
    return JSON.parse(read(MANIFEST)).version;
}

// Release tags, newest first, with the same `vX.Y.Z` filter the updater uses.
function releaseTags() {
    try {
        return execFileSync("git",
            ["tag", "--list", "v[0-9]*", "--sort=-v:refname"],
            { cwd: ROOT, encoding: "utf8" })
            .split("\n")
            .map((line) => line.trim())
            .filter((tag) => /^v\d+\.\d+\.\d+$/.test(tag));
    } catch (e) {
        return [];
    }
}

test("the manifest carries a plain release version", () => {
    assert.match(manifestVersion(), /^\d+\.\d+\.\d+$/);
});

test("the newest release tag matches the manifest version", (t) => {
    const tags = releaseTags();
    if (tags.length === 0) return t.skip("no release tags in this checkout");
    assert.equal(manifestVersion(), tags[0].slice(1),
        `manifest ${manifestVersion()} must equal tag ${tags[0]} without the v`);
});

test("the README documents the release steps and the update flow", () => {
    const readme = read("README.md");
    assert.match(readme, /## Actualizar/);
    assert.match(readme, /kisaru update/);
    assert.match(readme, /## Publicar una versión/);
    assert.match(readme, /manifest\.json/);
    assert.match(readme, /git tag v\d+\.\d+\.\d+/);
    assert.match(readme, /git push origin v\d+\.\d+\.\d+/);
});
