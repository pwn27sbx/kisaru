"use strict";

// The bar widget runs inside Omarchy's Quickshell config, which cannot import
// Kisaru's services/I18n.qml, so omarchy/pwnsxb.kisaru/strings.js carries its
// own table and resolver (audit 2026-11-06, finding 29). tools/lint-i18n.js
// does not scan omarchy/, so this file is the guard: it pins the resolver and
// proves Panel.qml reads every user-facing string from the table.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const strings = require("../omarchy/pwnsxb.kisaru/strings.js");
const panel = fs.readFileSync(path.join(ROOT, "omarchy/pwnsxb.kisaru/Panel.qml"), "utf8");

test("only English and Spanish exist", () => {
    assert.deepEqual(Object.keys(strings.tables).sort(), ["en", "es"]);
});

test("every key exists in both tables", () => {
    const en = Object.keys(strings.tables.en).sort();
    assert.deepEqual(Object.keys(strings.tables.es).sort(), en);
});

test("normalizeLanguage() folds anything Spanish-ish to es and the rest to en", () => {
    for (const value of ["es", "es-419", "ES", "es_ES.UTF-8", " español "])
        assert.equal(strings.normalizeLanguage(value), "es", value);
    for (const value of ["en", "en_US.UTF-8", "fr", "", null, undefined])
        assert.equal(strings.normalizeLanguage(value), "en", String(value));
});

test("the language follows QS_LANG, then settings, then LANG, then English", () => {
    const resolve = strings.resolveLanguage;
    assert.equal(resolve("es", "en", "en_US"), "es");
    assert.equal(resolve("en", "es", "es_ES"), "en");
    assert.equal(resolve("", "es", "en_US"), "es");
    assert.equal(resolve("", "", "es_ES.UTF-8"), "es");
    assert.equal(resolve("", "", "fr_FR.UTF-8"), "en");
    assert.equal(resolve("", "", ""), "en");
});

test("languageFromSettings() reads only a valid language key", () => {
    assert.equal(strings.languageFromSettings('{"language":"es"}'), "es");
    assert.equal(strings.languageFromSettings('{"language":"en","scrollFactor":2}'), "en");
    assert.equal(strings.languageFromSettings('{"language":"fr"}'), "");
    assert.equal(strings.languageFromSettings('{"scrollFactor":2}'), "");
    assert.equal(strings.languageFromSettings("not json"), "");
    assert.equal(strings.languageFromSettings(""), "");
});

test("the settings path is the new folder unless only the inherited one exists", () => {
    const base = "/home/someone/.config";
    const fresh = strings.settingsFile(base, false);
    const legacy = strings.settingsFile(base, true);
    assert.equal(fresh, "/home/someone/.config/kisaru/settings.json");
    assert.equal(legacy, "/home/someone/.config/qs-novelmangareader/settings.json");
    assert.equal(strings.resolveSettingsPath(fresh, legacy, true, true), fresh);
    assert.equal(strings.resolveSettingsPath(fresh, legacy, false, true), legacy);
    assert.equal(strings.resolveSettingsPath(fresh, legacy, false, false), fresh);
});

test("t() translates a key and falls back to English, then to the key", () => {
    assert.equal(strings.t("es", "menu.title"), "Lector");
    assert.equal(strings.t("en", "menu.title"), "Reader");
    assert.equal(strings.t("fr", "menu.title"), "Reader");
    assert.equal(strings.t("es", "no.such.key"), "no.such.key");
});

test("Panel.qml reads every user-facing string from the table", () => {
    const used = [...panel.matchAll(/root\.t\("([^"]+)"\)/g)].map((m) => m[1]);
    assert.deepEqual(used.sort(),
        ["entry.anime", "entry.manga", "entry.novel", "menu.title", "menu.tooltip"]);
    for (const key of used) assert.ok(key in strings.tables.en, key);
    // No raw literal survived: a label, tooltip or section header must go
    // through the table, and the old hard-coded wording is gone.
    assert.ok(!/\b(?:label|tooltipText)\s*:\s*"/.test(panel));
    assert.ok(!/text:\s*"Reader"/.test(panel));
    assert.ok(!/Novelas/.test(panel));
});
