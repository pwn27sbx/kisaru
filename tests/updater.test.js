"use strict";

// The update check's decision logic (S2, A2): local version vs remote tags.
//
// Only numbered releases count: `vX.Y.Z`, nothing else. These tests pin the
// cases that decide whether a user sees a banner, so a prerelease tag or an
// annotated-tag peeled line can never start one.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");

const updater = require("../services/updater.js");

test("compareVersions() orders release versions numerically", () => {
    assert.equal(updater.compareVersions("1.2.3", "1.2.3"), 0);
    assert.equal(updater.compareVersions("1.2.3", "1.2.4"), -1);
    assert.equal(updater.compareVersions("1.2.4", "1.2.3"), 1);
    assert.equal(updater.compareVersions("1.9.0", "1.10.0"), -1);
    assert.equal(updater.compareVersions("2.0.0", "1.99.99"), 1);
});

test("compareVersions() refuses anything that is not X.Y.Z", () => {
    assert.equal(updater.compareVersions("1.2", "1.2.0"), null);
    assert.equal(updater.compareVersions("v1.2.3", "1.2.3"), null);
    assert.equal(updater.compareVersions("1.2.3-rc.1", "1.2.3"), null);
    assert.equal(updater.compareVersions("", "1.2.3"), null);
});

test("versionFromTag() keeps only numbered releases", () => {
    assert.equal(updater.versionFromTag("refs/tags/v1.2.3"), "1.2.3");
    assert.equal(updater.versionFromTag("v1.10.0"), "1.10.0");
    assert.equal(updater.versionFromTag("refs/tags/v1.2.3-rc.1"), "");
    assert.equal(updater.versionFromTag("refs/tags/v1.2"), "");
    assert.equal(updater.versionFromTag("refs/tags/v1.2.3^{}"), "");
    assert.equal(updater.versionFromTag("refs/tags/nightly"), "");
    assert.equal(updater.versionFromTag(""), "");
});

test("parseTags() reads ls-remote lines and ignores the rest", () => {
    const output = [
        "aaaa\trefs/tags/v1.0.0",
        "bbbb\trefs/tags/v1.1.0",
        "",
        "cccc\trefs/tags/v1.1.0^{}",
        "dddd\trefs/tags/v2.0.0-rc.1",
        "eeee\trefs/tags/not-a-release"
    ].join("\n");
    assert.deepEqual(updater.parseTags(output), ["1.0.0", "1.1.0"]);
    assert.deepEqual(updater.parseTags(""), []);
});

test("highestVersion() picks the numerically highest release", () => {
    assert.equal(updater.highestVersion(["1.9.0", "1.10.0", "1.2.0"]), "1.10.0");
    assert.equal(updater.highestVersion([]), "");
    assert.equal(updater.highestVersion(["garbage", "1.0.0"]), "1.0.0");
});

test("updateAvailable() reports only a strictly newer release", () => {
    assert.equal(updater.updateAvailable("1.0.0", ["1.0.0"]), "");
    assert.equal(updater.updateAvailable("1.0.0", ["1.0.1"]), "1.0.1");
    assert.equal(updater.updateAvailable("1.0.0", ["0.9.9"]), "");
    assert.equal(updater.updateAvailable("1.0.0", ["1.10.0", "1.9.0"]), "1.10.0");
    // The raw ls-remote output works too.
    assert.equal(updater.updateAvailable("1.0.0", "aaaa\trefs/tags/v1.2.0"), "1.2.0");
    assert.equal(updater.updateAvailable("", ["1.2.0"]), "");
    assert.equal(updater.updateAvailable("1.0", ["1.2.0"]), "");
});

test("updateAvailable() never raises a banner for malformed or prerelease tags", () => {
    const tags = ["1.2", "v1.2.0", "1.2.0-rc.1", "nightly", ""];
    assert.equal(updater.updateAvailable("1.0.0", tags), "");
});

test("versionFromManifest() accepts only a plain version", () => {
    assert.equal(updater.versionFromManifest('{"version":"1.2.3"}'), "1.2.3");
    assert.equal(updater.versionFromManifest('{"version":" 1.2.3 "}'), "1.2.3");
    assert.equal(updater.versionFromManifest('{"version":"1.2.3-rc.1"}'), "");
    assert.equal(updater.versionFromManifest('{"version":""}'), "");
    assert.equal(updater.versionFromManifest('{"name":"kisaru"}'), "");
    assert.equal(updater.versionFromManifest("not json"), "");
    assert.equal(updater.versionFromManifest(""), "");
});

test("parseCheck() reads the checker's state lines", () => {
    const text = [
        "checkout=yes",
        "branch=main",
        "dirty=yes",
        "tag=v1.2.0",
        "tag=v1.2.0-rc.1",
        "error=1"
    ].join("\n");
    assert.deepEqual(updater.parseCheck(text), {
        checkout: true,
        branch: "main",
        dirty: true,
        tags: ["1.2.0"],
        error: true
    });

    const copy = updater.parseCheck("checkout=no\nbranch=\ndirty=\ntag=v1.3.0\n");
    assert.equal(copy.checkout, false);
    assert.equal(copy.branch, "");
    assert.equal(copy.dirty, false);
    assert.deepEqual(copy.tags, ["1.3.0"]);
    assert.equal(copy.error, false);
});
