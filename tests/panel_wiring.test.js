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
        assert.match(panel, /StatusLine\.barText\(/, `${file}: count is not the shared rule`);
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
    // Anchored on the component, not on a comment: rewording the prose must not
    // silently change what this checks.
    const start = settings.indexOf("SettingsCard {");
    const audio = settings.slice(start, settings.indexOf("UI language", start));
    assert.match(audio, /SettingsCard\s*\{/, "the audio row is not a settings card");
    assert.match(audio, /modeSelected/, "the card has no SUB/DUB control");
    const card = read("components/SettingsCard.qml");
    // The values copied from qs.Ui's Toggle, pinned: the minimum height it
    // enforces, the idle fill, the normal border and the container it builds on.
    assert.match(card, /BorderSurface/);
    assert.match(card, /minimumHeight: 54/);
    assert.match(card, /Style\.controlFill\(false \/\* focused \*\/, false \/\* hot \*\//);
    assert.match(card, /Border\.controlSpec\("normal"/);
});

test("every header shows its tab counters", () => {
    // Owner, round 6: anime and novel get the same "Browse 32 · Library 1" the
    // manga header has had since round 4.
    for (const file of PANELS) {
        assert.match(read(file), /tabCounts:\s*\[/, `${file}: no tab counts`);
    }
});

test("a library cell reserves its footer on top of the shared box", () => {
    // The review of A-4 caught the real bug: the libraries' progress strip is
    // not part of INFO_BASE, so a cell that forgets it makes the info block
    // ride over the cover. Every library grid and its ghost must pass it.
    for (const file of [
        "modules/manga/components/LibraryView.qml",
        "modules/anime/components/LibraryView.qml",
        "modules/novel/components/LibraryView.qml",
    ]) {
        const qml = read(file);
        assert.match(qml, /CardMetrics\.cellHeight\([^)]*Style\.space\(\d+\)\s*\)/s,
            `${file}: the cell does not reserve the footer`);
    }
});

test("the six grids and their ghosts share one cell box and three columns", () => {
    const grids = [
        "modules/manga/components/BrowseView.qml",
        "modules/manga/components/LibraryView.qml",
        "modules/anime/components/BrowseView.qml",
        "modules/anime/components/LibraryView.qml",
        "modules/novel/components/BrowseView.qml",
        "modules/novel/components/LibraryView.qml",
    ];
    for (const file of grids) {
        const qml = read(file);
        assert.match(qml, /CardMetrics\.cellHeight\(/, `${file}: cell height is not the shared one`);
        assert.match(qml, /CardMetrics\.columns/, `${file}: columns are not the shared count`);
        // The old per-panel ratio literals are gone: they were five different
        // numbers for the same box.
        for (const ratio of ["1.58", "1.65", "1.72", "1.78"]) {
            assert.ok(!qml.includes(`ratio: ${ratio}`), `${file}: still uses ratio ${ratio}`);
        }
    }
});

test("one card: no per-panel anatomy and no inline delegates left", () => {
    const card = read("components/CoverCard.qml");
    // Declarations, not words: "variant" also appears inside outline_variant.
    for (const gone of [
        "property string variant",
        "property bool stitch",
        "property int inset",
        "property int titlePadding",
        "property bool badgeLeading",
        "property int gradientHeight"
    ]) {
        assert.ok(!card.includes(gone), `CoverCard still declares ${gone}`);
    }
    const constants = read("services/manga_card.js");
    assert.ok(!constants.includes("VARIANTS"), "manga_card.js still exports VARIANTS");
    // The anime and novel browse grids draw the shared card now.
    for (const file of ["modules/anime/components/BrowseView.qml", "modules/novel/components/BrowseView.qml"]) {
        assert.match(read(file), /CoverCard\s*\{/, `${file}: still draws its own card`);
    }
});

test("every panel remembers its own grid/list choice", () => {
    const views = [
        ["modules/manga/components/BrowseView.qml", "manga"],
        ["modules/manga/components/LibraryView.qml", "manga"],
        ["modules/anime/components/BrowseView.qml", "anime"],
        ["modules/anime/components/LibraryView.qml", "anime"],
        ["modules/novel/components/BrowseView.qml", "novel"],
        ["modules/novel/components/LibraryView.qml", "novel"],
    ];
    for (const [file, panel] of views) {
        const qml = read(file);
        assert.match(qml, new RegExp(`viewModeFor\\("${panel}"\\)`), `${file}: reads another panel's layout`);
        // One shared control: the view names its panel and never carries its
        // own copy of the segmented box.
        assert.match(qml, /ViewModeToggle\s*\{/, `${file}: no shared layout toggle`);
        assert.match(qml, new RegExp(`panel: "${panel}"`), `${file}: the toggle names another panel`);
        assert.ok(!qml.includes("cellsRow {") && !qml.includes("viewCells {"),
            `${file}: still carries a hand-built toggle`);
        assert.match(qml, /ListRow\s*\{/, `${file}: no list rows`);
    }
    assert.match(read("components/ViewModeToggle.qml"), /UiPrefs\.setViewMode\(root\.panel/, "the shared toggle does not write the panel's key");
});

test("the anime score chip is legible: accent and bold", () => {
    // Owner, round 6: the rating moved to the trailing corner and became dim;
    // it takes the accent like the episodes chip so it reads on the artwork.
    const card = read("components/CoverCard.qml");
    assert.match(card, /property bool cornerAccent/);
    // The chip's text is always bold; the accent is what makes a score read.
    assert.match(card, /font\.bold: true/);
    assert.match(card, /color: root\.cornerAccent \? Colors\.primary/);
    for (const file of [
        "modules/anime/components/BrowseView.qml",
        "modules/anime/components/LibraryView.qml",
    ]) {
        assert.match(read(file), /cornerAccent: true/, `${file}: the score is still dim`);
    }
});

test("all three panels are 550 wide, and the novel keeps fullscreen", () => {
    // Owner, round 6 (D2). The novel's reader is the reason the width exists, so
    // its fullscreen branch must survive the change.
    assert.match(read("modules/manga/MangaReader.qml"), /implicitWidth: 550/);
    assert.match(read("modules/anime/AnimePanel.qml"), /implicitWidth: 550/);
    assert.match(read("modules/novel/NovelReader.qml"), /implicitWidth: fullscreen \?.*: 550/);
});

test("the anime list row carries the score the grid shows", () => {
    const row = read("components/ListRow.qml");
    assert.match(row, /property string score/);
    assert.match(row, /visible: root\.score !== ""/);
    // The score keeps the accent tone of the grid's chip.
    assert.match(row, /color: Colors\.primary/);
    const browse = read("modules/anime/components/BrowseView.qml");
    assert.match(browse, /score: modelData\.score/);
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
