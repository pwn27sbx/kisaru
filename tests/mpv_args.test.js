"use strict";

// Tests for services/mpv_args.js — mpv argv builder for anime playback (WU-4).
// Run with: node --test tests/mpv_args.test.js

const test = require("node:test");
const assert = require("node:assert/strict");

const mpvArgs = require("../services/mpv_args.js");

const BASE = {
    url: "https://cdn.example/ep1.m3u8",
    title: "Steins;Gate — Ep. 1",
    referer: "https://zokoanime.video/",
    subtitle: "https://cdn.example/es.vtt",
    skipScriptPath: "/opt/kisaru/scripts/mpv_aniskip.lua",
    apiUrl: "http://127.0.0.1:5050",
    showId: "show-123",
    episode: "1",
    showTitle: "Steins;Gate, Part=1",
    skipMode: "auto",
    skipRecap: false,
    lang: "es",
    showSkipDisabled: false,
};

test("includes --script and --script-opts with dynamic apiUrl when enabled", () => {
    const args = mpvArgs.buildMpvArgs(Object.assign({}, BASE, {
        apiUrl: "http://127.0.0.1:6123",
        skipRecap: true,
    }));
    assert.equal(args[0], "mpv");
    assert.ok(args.includes("--script=/opt/kisaru/scripts/mpv_aniskip.lua"));
    const optArg = args.find((a) => a.startsWith("--script-opts="));
    assert.ok(optArg, "expected --script-opts");
    assert.ok(optArg.includes("kisaru_skip-api=http://127.0.0.1:6123"));
    assert.ok(optArg.includes("kisaru_skip-show_id=show-123"));
    assert.ok(optArg.includes("kisaru_skip-ep=1"));
    assert.ok(optArg.includes("kisaru_skip-mode=auto"));
    assert.ok(optArg.includes("kisaru_skip-recap=yes"));
    assert.ok(optArg.includes("kisaru_skip-lang=es"));
    // Commas and equals in showTitle must be percent-encoded so they cannot inject script-opts.
    assert.ok(!optArg.includes("Steins;Gate, Part=1"));
    assert.ok(optArg.includes("kisaru_skip-title=" + encodeURIComponent("Steins;Gate, Part=1")));
    // `--` stays right before the stream URL.
    assert.equal(args[args.length - 2], "--");
    assert.equal(args[args.length - 1], BASE.url);
});

test("omits --script and --script-opts when skipMode is off", () => {
    const args = mpvArgs.buildMpvArgs(Object.assign({}, BASE, { skipMode: "off" }));
    assert.ok(!args.some((a) => a.startsWith("--script=")));
    assert.ok(!args.some((a) => a.startsWith("--script-opts=")));
});

test("omits --script when per-show skip is disabled", () => {
    const args = mpvArgs.buildMpvArgs(Object.assign({}, BASE, { showSkipDisabled: true }));
    assert.ok(!args.some((a) => a.startsWith("--script=")));
    assert.ok(!args.some((a) => a.startsWith("--script-opts=")));
});

test("omits --script when apiUrl is empty (no hardcoded localhost fallback)", () => {
    const args = mpvArgs.buildMpvArgs(Object.assign({}, BASE, { apiUrl: "" }));
    assert.ok(!args.some((a) => a.startsWith("--script=")));
    assert.ok(!args.some((a) => a.includes("5050")));
});

test("returns empty array when url is empty", () => {
    assert.deepEqual(mpvArgs.buildMpvArgs(Object.assign({}, BASE, { url: "" })), []);
});
