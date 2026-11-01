"use strict";

// The idle fade's wiring, checked where the shell really uses it.
//
// The fade broke once for a whole round and nobody noticed until the owner
// did: no commit had touched it, the shell had simply been started while a
// temporary `IDLE_OPACITY = 1.0` edit was in the tree, and an imported JS
// module is never re-evaluated after the file is restored. These probes make
// that class of loss visible from the test run instead of from the screen:
//
//   - the slot opacity must come from Panels.opacityForSlot (the real path),
//     not from a hand-assembled state in shell.qml;
//   - each panel must keep publishing `pointerInside` from a HoverHandler,
//     or the fade silently pins itself to "pointer is inside";
//   - IDLE_OPACITY must be the owner's 0.15 and must be declared in exactly
//     one place, so a leftover override cannot survive in another file.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const read = (rel) => fs.readFileSync(path.join(ROOT, rel), "utf8");

const PANELS = [
    "modules/manga/MangaReader.qml",
    "modules/anime/AnimePanel.qml",
    "modules/novel/NovelReader.qml",
];

test("shell.qml takes every slot's opacity from the tested function", () => {
    const shell = read("shell.qml");
    for (const slot of ["mangaSlot", "novelSlot", "animeSlot"]) {
        assert.match(
            shell,
            new RegExp(`opacity:\\s*Panels\\.opacityForSlot\\(\\s*${slot}\\s*\\)`),
            `${slot} must bind its opacity to Panels.opacityForSlot`
        );
    }
    // The inline assembly is what made the real path untestable; it must not
    // come back.
    assert.doesNotMatch(shell, /Panels\.opacityFor\s*\(/);
});

test("the three panels share one header: no per-panel look flags", () => {
    // Owner, round 6: the redesigned header is the default of the shared
    // component. A flag coming back would let one panel drift away from the
    // other two, which is exactly what the shared-components plan removes.
    const header = read("components/PanelHeader.qml");
    for (const flag of ["segmentedTabs", "fullHeightCells", "showLanguage", "showMode", "extraAction"]) {
        assert.doesNotMatch(header, new RegExp(flag), `PanelHeader still declares ${flag}`);
    }
    const brand = read("components/PanelBrand.qml");
    for (const flag of ["showGlyph", "uppercaseTitle"]) {
        assert.doesNotMatch(brand, new RegExp(flag), `PanelBrand still declares ${flag}`);
    }
    // The language chip lives in the settings page only.
    assert.ok(!fs.existsSync(path.join(ROOT, "components/LanguageToggle.qml")),
        "LanguageToggle.qml is back; the language is a setting");
});

test("the header holds no search state and no panel preferences", () => {
    // A-2: the search is a field under the row, and SUB/DUB is a setting.
    const header = read("components/PanelHeader.qml");
    // Declarations, not words: the comments still talk about the overlay ring.
    for (const gone of [
        "default property alias overlay",
        "property bool showSearch",
        "property bool searchOpen",
        "signal searchClicked",
        "readonly property bool showBrand",
        "property var modes",
        "signal modeSelected"
    ]) {
        assert.ok(!header.includes(gone), `PanelHeader still declares ${gone}`);
    }
    // The provider picker stays: it is used to switch sources all the time.
    assert.match(header, /extraCell/);
});

test("every panel shows the shared search field, and anime keeps its mode in settings", () => {
    for (const file of PANELS) {
        assert.match(read(file), /SearchField\s*\{/, `${file}: no shared search field`);
        assert.match(read(file), /onEdited:\s*searchDebounce\.restart\(\)/, `${file}: field is not debounced`);
    }
    const anime = read("modules/anime/AnimePanel.qml");
    // The audio mode is a settings row now, persisted, and named in the bar.
    assert.match(anime, /PanelSettings\s*\{[^}]*modes:/s);
    assert.match(anime, /onModeSelected/);
    assert.match(anime, /modeText:\s*Anime\.currentMode\.toUpperCase\(\)/);
    assert.match(read("services/Anime.qml"), /currentMode:\s*UiPrefs\.animeMode/);
    assert.match(read("services/Anime.qml"), /UiPrefs\.setAnimeMode\(mode\)/);
    const novel = read("modules/novel/NovelReader.qml");
    assert.match(novel, /extraCell:/);
});

test("the three panels count in the status bar, not in a heading", () => {
    // A-3: the count belongs to the bar (owner, round 4 for manga, round 6 for
    // the other two), and the rule that picks it is the same tested helper.
    for (const file of PANELS) {
        const panel = read(file);
        assert.match(panel, /StatusBar\s*\{/, `${file}: no status bar`);
        assert.match(panel, /StatusLine\.visibleCount\(/, `${file}: count is not the shared rule`);
        assert.match(panel, /StatusLine\.format\(/, `${file}: count is not formatted by the shared rule`);
    }
    // Anime's library heading had its own badge; two counts are one too many.
    const animeLibrary = read("modules/anime/components/LibraryView.qml");
    assert.ok(!animeLibrary.includes("libCountText"), "anime Library kept its own count badge");
    assert.ok(!animeLibrary.includes("anime.library.title"), "anime Library kept its heading");
});

test("the audio setting is the same card as the language row", () => {
    // Owner, round 6: title and description on the left, control on the right,
    // the container the language row uses — not two loose buttons.
    const settings = read("components/PanelSettings.qml");
    const start = settings.indexOf("Audio mode (the anime panel");
    const audio = settings.slice(start, settings.indexOf("UI language", start));
    assert.match(audio, /SettingsCard\s*\{/, "the audio row is not a settings card");
    assert.match(audio, /modeSelected/, "the card has no SUB/DUB control");
    const card = read("components/SettingsCard.qml");
    // Same container tokens as qs.Ui's Toggle, which the language row uses.
    assert.match(card, /BorderSurface/);
    assert.match(card, /Style\.controlFill\(/);
    assert.match(card, /Border\.controlSpec\(\s*"normal"/);
});

test("every panel keeps publishing pointerInside from a HoverHandler", () => {
    for (const file of PANELS) {
        const qml = read(file);
        assert.match(qml, /HoverHandler\s*\{\s*id:\s*pointer\s*\}/, `${file}: no HoverHandler`);
        assert.match(
            qml,
            /readonly property bool pointerInside:\s*pointer\.hovered/,
            `${file}: pointerInside no longer follows the pointer`
        );
    }
});

test("IDLE_OPACITY is the owner's value, declared in exactly one place", () => {
    const panels = read("services/panels.js");
    assert.match(panels, /var IDLE_OPACITY = 0\.15;/, "the idle opacity is not 0.15");

    const offenders = [];
    const walk = (dir) => {
        for (const entry of fs.readdirSync(path.join(ROOT, dir), { withFileTypes: true })) {
            if (entry.name === ".git" || entry.name === "node_modules") continue;
            const rel = dir ? `${dir}/${entry.name}` : entry.name;
            if (entry.isDirectory()) {
                walk(rel);
                continue;
            }
            if (!/\.(js|qml)$/.test(entry.name)) continue;
            // The runtime files only: a test asserting the constant is not an
            // override, and probe scripts do not reach the shell.
            if (rel === "services/panels.js" || rel.startsWith("tests/")) continue;
            if (/IDLE_OPACITY\s*=/.test(read(rel))) offenders.push(rel);
        }
    };
    walk("");
    assert.deepEqual(offenders, [], "IDLE_OPACITY is being assigned outside services/panels.js");
});

test("the fade is animated with a Motion token", () => {
    const shell = read("shell.qml");
    const fade = /Behavior on opacity\s*\{\s*NumberAnimation\s*\{\s*duration:\s*Motion\.\w+\s*\}\s*\}/;
    assert.match(shell, fade);
});
