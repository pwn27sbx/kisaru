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

test("the header owns the search now, and still no panel preferences", () => {
    // Owner §33 reversed the round-6 rule: the field lives in the header and
    // grows over the brand. What must stay out is a panel preference (SUB/DUB).
    const header = read("components/PanelHeader.qml");
    assert.match(header, /SearchField\s*\{/, "the header has no search field");
    assert.match(header, /property bool searchOpen/, "the header cannot open its search");
    assert.ok(!/currentMode|animeMode|setViewMode/.test(header),
        "the header must not carry a panel preference");
});

test("every panel shows the shared header with the search in it (§33)", () => {
    // The tool bar is gone: the header is the whole chrome, so the panel is
    // asserted to give it the search and the one debounce behind it.
    for (const file of PANELS) {
        assert.ok(!/ToolBar\s*\{/.test(read(file)), `${file}: still places a tool bar row`);
        assert.match(read(file), /PanelHeader\s*\{/, `${file}: no shared header`);
        assert.match(read(file), /onSearchEdited:\s*searchDebounce\.restart\(\)/, `${file}: search is not debounced`);
        assert.ok(!/SearchField\s*\{/.test(read(file)), `${file}: still carries its own search field`);
    }
    const anime = read("modules/anime/AnimePanel.qml");
    // The audio mode is a settings row now, persisted, and named in the bar.
    assert.match(anime, /modes:\s*/, "the audio rows left the settings page");
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

test("Browse carries no number and Library shows its count as a badge", () => {
    // Owner, round 6 gave every header its counters; A-8 refined the rule:
    // the loaded count already lives in the status bar, so Browse passes `-1`
    // (no counter) and only Library carries a number.
    for (const file of PANELS) {
        const panel = read(file);
        assert.match(panel, /tabCounts:\s*\[-1,/, `${file}: Browse still carries a number`);
        // The badge counts the visible list (folders and private mode), not
        // the raw one, and anime is no longer the exception.
        assert.match(panel, /tabCounts:\s*\[-1,\s*\w+\.visibleCount\(\)\]/,
            `${file}: Library does not count its visible list`);
    }
    // The badge, and the rule that hides it at zero, are in one place.
    const header = read("components/PanelHeader.qml");
    assert.match(header, /HeaderCell\.showBadge\(cell\.count\)/, "the header does not hide an empty badge");
    assert.match(header, /font\.bold: true/, "the badge number is not bold");
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

test("every panel remembers its own grid/list choice, set from the settings page", () => {
    // Owner §33: the switch left the header for the settings page, persisted per
    // panel exactly as before.
    for (const [file, panel] of PANELS.map((f, i) => [f, ["manga", "anime", "novel"][i]])) {
        const qml = read(file);
        assert.ok(!/ViewModeToggle\s*\{/.test(qml), `${file}: the header still carries the switch`);
        assert.match(qml, new RegExp(`viewModeFor\\("${panel}"\\)`), `${file}: reads another panel's layout`);
        assert.match(qml, new RegExp(`onLayoutSelected: function\\(id\\) \\{ UiPrefs\\.setViewMode\\("${panel}"`),
            `${file}: does not persist its own layout`);
    }
    assert.match(read("components/PanelSettings.qml"), /layoutSelected/, "the settings page has no layout option");
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

test("the list row is the owner's sketch: tall cover, big title, small datum", () => {
    // A-9: 64 x 90 cover, title about 1.35x the body size, datum back to a
    // caption under it, block centred.
    const row = read("components/ListRow.qml");
    // Both thumbnail sides come from the shared metrics, never from the row.
    assert.match(row, /Style\.space\(ListMetrics\.THUMB_WIDTH\)/);
    assert.match(row, /Style\.space\(ListMetrics\.THUMB_HEIGHT\)/);
    assert.ok(!row.includes("Math.round(height * 0.7)"), "the thumbnail is derived from the row again");
    // Title one step over the body, from the shared scale, bold, two lines.
    assert.match(row, /Style\.font\.body \* ListMetrics\.TITLE_SCALE/,
        "the title does not read the shared type scale");
    assert.match(row, /font\.bold: true/, "the title is not bold");
    assert.match(row, /maximumLineCount: 2/, "long titles still die on one line");
    assert.match(row, /wrapMode: Text\.Wrap/, "two lines do not wrap");
    // The datum under it is small, and brighter than the muted role.
    assert.match(row, /Style\.font\.body \* ListMetrics\.DATUM_SCALE/, "the datum does not read the shared scale");
    assert.match(row, /datumColor: Colors\.card_secondary/,
        "the datum does not use the shared readable token");
    assert.match(row, /Colors\.outline_variant/, "no separator between rows");
});

test("the list ghost has the list row's shape, not a chapter row's", () => {
    // A-9: the Browse/Library skeletons stand in for ListRow, so they must draw
    // the same cover; a pill-shaped ghost makes the panel jump on load.
    const skeleton = read("components/SkeletonList.qml");
    assert.match(skeleton, /property bool cover/);
    assert.match(skeleton, /Style\.space\(ListMetrics\.THUMB_WIDTH\)/);
    assert.match(skeleton, /Style\.space\(ListMetrics\.THUMB_HEIGHT\)/);
    // A-10: the ghost reads the row's type scale and gap from the same module
    // instead of copying the font tokens, and its content inset is its own
    // property rather than a second meaning for dividerInset.
    assert.match(skeleton, /ListMetrics\.TITLE_SCALE/);
    assert.match(skeleton, /ListMetrics\.DATUM_SCALE/);
    assert.match(skeleton, /ListMetrics\.TEXT_GAP_BASE/);
    assert.match(skeleton, /property int inset:/);
    assert.ok(!/cover \? root\.dividerInset/.test(skeleton), "the cover still borrows dividerInset as an inset");
    for (const file of [
        "modules/manga/components/BrowseView.qml",
        "modules/manga/components/LibraryView.qml",
        "modules/anime/components/BrowseView.qml",
        "modules/anime/components/LibraryView.qml",
        "modules/novel/components/BrowseView.qml",
        "modules/novel/components/LibraryView.qml",
    ]) {
        const qml = read(file);
        assert.match(qml, /SkeletonList\s*\{[\s\S]{0,400}?cover: true/, `${file}: its ghost is still a chapter row`);
    }
});

test("the anime list row carries the score the grid shows", () => {
    const row = read("components/ListRow.qml");
    assert.match(row, /property string score/);
    assert.match(row, /visible: root\.score !== ""/);
    // The score keeps the accent tone of the grid's chip.
    assert.match(row, /color: Colors\.primary/);
    // Both anime lists feed the same field from the same data.
    for (const file of [
        "modules/anime/components/BrowseView.qml",
        "modules/anime/components/LibraryView.qml",
    ]) {
        const qml = read(file);
        assert.ok(qml.includes('"★ " + value.toFixed(1)'), `${file}: no score run`);
        assert.match(qml, /isFinite\(value\)/, `${file}: the score is not guarded`);
    }
});

test("settings and libraries read the new name first, the inherited one only as a fallback", () => {
    // Owner decision D6: the app owns `kisaru` paths, and the migration window
    // must not show an empty library or reset the settings.
    const prefs = read("services/UiPrefs.qml");
    assert.match(prefs, /Paths\.CONFIG_DIR/);
    assert.match(prefs, /Paths\.LEGACY_CONFIG_DIR/);
    assert.match(prefs, /Paths\.resolvePath\(root\._newDir, root\._oldDir/);
    assert.match(prefs, /id: oldProbe/);
    // Same race on the settings file: the empty state must arrive too.
    assert.match(prefs, /_finishWhenProbeFindsNothing/);

    for (const [file, panel] of [
        ["services/Manga.qml", "manga"],
        ["services/Anime.qml", "anime"],
        ["services/Novel.qml", "novel"],
    ]) {
        const qml = read(file);
        assert.match(qml, new RegExp(`Paths\\.libraryPath\\(root\\._dataHome, "${panel}", false\\)`),
            `${file}: no new library path`);
        // The inherited candidate follows the same (XDG-aware) data home.
        assert.match(qml, new RegExp(`Paths\\.legacyLibraryPath\\(root\\._dataHome, "${panel}"\\)`),
            `${file}: no inherited library path to fall back to`);
        assert.match(qml, /id: oldLibraryProbe/, `${file}: no probe for the inherited library`);
        // The read can fail before the probe settles; without this the empty
        // state would never arrive on a fresh install (review R3-ProbeRace).
        assert.match(qml, /_finishWhenProbeFindsNothing/, `${file}: the probe race is not closed`);
        assert.match(qml, /Paths\.resolvePath\(root\._newLibraryPath, root\._oldLibraryPath/,
            `${file}: the library path is not resolved through the shared rule`);
    }

    // The backends' interpreter is the new venv and nothing else: a silent
    // fallback would hide a broken install behind old packages.
    assert.match(read("services/ReaderEnv.qml"), /Paths\.DATA_DIR \+ "\/venv\/bin\/python3"/);
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

test("the folder cards, the hide switches and no padlock are wired", () => {
    // v2: no chip row. The root is a card grid (folders first, then folderless
    // titles), the open folder carries back/rename/delete, and the hide switch
    // is the one clear control (there is no padlock any more).
    for (const [file, kind] of [
        ["modules/manga/components/LibraryView.qml", "manga"],
        ["modules/anime/components/LibraryView.qml", "anime"],
        ["modules/novel/components/LibraryView.qml", "novel"],
    ]) {
        const qml = read(file);
        assert.ok(!qml.includes("FolderRow"), `${file}: the chip row came back`);
        assert.match(qml, /\.visibleEntries\(""\)/, `${file}: does not read the visible shelf`);
        assert.match(qml, /FolderCards\.rootItems\(/, `${file}: no root cards`);
        assert.match(qml, /FolderCards\.searchTitles\(/, `${file}: search does not cross folders`);
        assert.match(qml, /FolderCard\s*\{/, `${file}: no folder card`);
        assert.match(qml, /FolderListRow\s*\{/, `${file}: no folder row`);
        assert.match(qml, /CreateFolderCard\s*\{/, `${file}: no create card`);
        assert.match(qml, /kind: "create"/, `${file}: the create card is not in the model`);
        assert.match(qml, /FolderPrompt\s*\{/, `${file}: no folder dialog`);
        assert.match(qml, /onQueryChanged:/, `${file}: no unlock hook`);
        assert.match(qml, /Privacy\.consider\(query/, `${file}: the query never reaches the helper`);
        assert.match(qml, /signal secretEntered\(\)/, `${file}: no collapse signal`);
        assert.match(qml, new RegExp(`Organizer\\.setHidden\\("${kind}"`),
            `${file}: the open folder cannot be hidden`);
        assert.match(qml, /folder\.count/, `${file}: the folder card has no count`);
        // Only a hidden or unresolved folder is closed while locked. A
        // visible folder opens with no secret, while locked, and a lock from
        // inside it keeps it open.
        assert.match(qml, new RegExp(`activeFolderLockedOut:\\n\\s*LibraryViewJs\\.lockedOut\\(activeFolder, Organizer\\.folders\\("${kind}"\\)`),
            `${file}: the lock gate does not use lockedOut`);
        assert.match(qml, /folderOpen: activeFolder !== "" && !_searching && !activeFolderLockedOut/,
            `${file}: a visible folder is still gated by the lock`);
        assert.match(qml, /activeFolderName:\n\s*\(activeFolder === "" \|\| activeFolderLockedOut\)/,
            `${file}: the status line hides a visible folder while locked`);
        assert.match(qml, /function _renameFolder\(folderId\) \{\n\s*if \(activeFolderLockedOut\) return/,
            `${file}: rename is gated by the lock, not by the folder`);
        assert.match(qml, /function _confirmDelete\(folderId\) \{\n\s*if \(activeFolderLockedOut\) return/,
            `${file}: delete is gated by the lock, not by the folder`);
        assert.match(qml, /function _toggleHideFolder\(\) \{\n\s*if \(!Privacy\.configured \|\| activeFolder === ""\) return/,
            `${file}: the folder switch is not gated by a configured word`);
        assert.match(qml, /visible: !activeFolderLockedOut/,
            `${file}: the rename/delete controls are hidden for a visible locked folder`);
        // One shared borderless switch and the three-dot menu.
        assert.match(qml, /HideSwitch\s*\{/, `${file}: no folder hide switch`);
        assert.match(qml, /checked: !Privacy\.locked && libraryView\.activeFolderHidden/,
            `${file}: the switch does not show the hidden state`);
        assert.ok(!/HideSwitch\s*\{[^}]*label:/.test(qml),
            `${file}: the switch copies the label instead of sharing the state`);
        assert.match(qml, /OverflowMenu\s*\{/, `${file}: no three-dot menu`);
        assert.match(qml, /Toolbar\.menuActions\(\)/, `${file}: the menu actions are copied`);
        assert.ok(!qml.includes("FolderAction"), `${file}: the loose action boxes are back`);
        assert.ok(!qml.includes("folder.hiddenMark"), `${file}: the separate hidden tag is back`);
        assert.ok(!qml.includes("folder.renameShort"), `${file}: the menu label is copied`);
        assert.match(qml, /if \(Privacy\.locked && libraryView\.activeFolderLockedOut\)\n\s*libraryView\.activeFolder = ""/,
            `${file}: a lock always sends the view back to the root`);
        assert.ok(!qml.includes('folderOpen: activeFolder !== "" && !_searching && !Privacy.locked'),
            `${file}: the old all-folders lock gate is back`);
    }

    const mosaic = read("components/CoverMosaic.qml");
    assert.match(mosaic, /_box\(index\)/, "the 2x2 mosaic geometry is missing");
    assert.match(read("components/FolderCard.qml"), /CoverMosaic\s*\{/);
    assert.match(read("components/FolderListRow.qml"), /CoverMosaic\s*\{/);

    // The padlock is gone from the chrome and the panels.
    const header = read("components/PanelHeader.qml");
    assert.ok(!header.includes("lockVisible"), "the padlock property is back");
    assert.ok(!header.includes("lockClicked"), "the padlock signal is back");
    assert.ok(!header.includes('privacy.lock'), "the padlock button is back");
    for (const file of PANELS) {
        const qml = read(file);
        assert.ok(!qml.includes("lockVisible"), `${file}: the padlock wiring is back`);
        assert.ok(!qml.includes("onLockClicked"), `${file}: the padlock handler is back`);
    }

    // Detail's folder control is a real button that opens the folder list.
    for (const file of [
        "modules/manga/components/DetailView.qml",
        "modules/anime/components/DetailView.qml",
        "modules/novel/components/DetailView.qml",
    ]) {
        const qml = read(file);
        assert.match(qml, /FolderPicker\s*\{/, `${file}: no folder list`);
        assert.match(qml, /onCreateRequested: folderPrompt\.openText/, `${file}: cannot create from Detail`);
        assert.match(qml, /I18n\.t\("folder\.current"/, `${file}: the button does not name the folder`);
        assert.ok(!qml.includes("_folderOptions"), `${file}: the old menu remains`);
        assert.match(qml, /HideSwitch\s*\{/, `${file}: no title hide switch`);
        assert.match(qml, /function _toggleHiddenTitle\(\)/, `${file}: no title hide handler`);
        assert.match(qml, /signal hiddenRequested\(\)/, `${file}: hiding cannot leave the Detail`);
        assert.ok(!/HideSwitch\s*\{[^}]*label:/.test(qml),
            `${file}: the Detail passes a label instead of the shared state`);
    }
});

test("the row has no card context action, and the header keeps onSearchEdited", () => {
    const card = read("components/CoverCard.qml");
    for (const gone of ["rightClicked", "contextMenu", "onPressAndHold", "menuRequested"])
        assert.ok(!card.includes(gone), `CoverCard grew a context action: ${gone}`);

    // Amendment 11: the new hook is onQueryChanged; the debounce path is untouched.
    for (const file of PANELS) {
        assert.match(read(file), /onSearchEdited:\s*searchDebounce\.restart\(\)/);
    }
});

test("the panels use the visible count and name the active folder", () => {
    for (const [file, service] of [
        ["modules/manga/MangaReader.qml", "Manga"],
        ["modules/anime/AnimePanel.qml", "Anime"],
        ["modules/novel/NovelReader.qml", "Novel"],
    ]) {
        const qml = read(file);
        assert.match(qml, new RegExp(`libraryCount: ${service}\\.visibleCount\\(\\)`),
            `${file}: the bar counts the raw list`);
        assert.match(qml, /folderName: libraryView\.activeFolderName/,
            `${file}: the bar does not name the folder`);
        assert.match(qml, /onSecretEntered: root\.collapseSearch\(\)/,
            `${file}: the panel ignores the unlock signal`);
        // Browse holds the query while the helper decides.
        assert.match(qml, /Privacy\.consider\(text, function\(code\)/,
            `${file}: Browse sends the candidate without the tag check`);
    }
    for (const file of PANELS) {
        assert.match(read(file), /if \(code === 1\) root\._sendBrowseQuery\(text\)/,
            `${file}: a tag hit never sends its search`);
    }
});

test("the shell locks when a panel hides, and there is no idle lock", () => {
    const shell = read("shell.qml");
    assert.match(shell, /if \(slot\.item && !slot\.item\.visible\)\s*\n\s*Privacy\.lock\(\)/,
        "the close/minimize/switch hook is missing");
    // Owner decision (2026-11-05): no IdleMonitor, no five-minute lock.
    assert.ok(!shell.includes("IdleMonitor"), "the idle lock came back");
    assert.ok(!/\b300\b/.test(shell), "an idle timeout is still wired");
});

test("a hidden title leaves no trace in the detail views or the logs", () => {
    for (const [file, service] of [
        ["modules/manga/components/DetailView.qml", "Manga"],
        ["modules/novel/components/DetailView.qml", "Novel"],
        ["modules/anime/components/DetailView.qml", "Anime"],
    ]) {
        const qml = read(file);
        assert.match(qml, new RegExp(`${service}\\.visibleEntryId\\(\\)`),
            `${file}: membership still reads the raw entry`);
        assert.match(qml, /_simulatedSaved/, `${file}: the locked save is not simulated`);
        assert.match(qml, new RegExp(`${service}\\.isHiddenLibraryEntry\\(`),
            `${file}: the simulated branch cannot recognise a hidden title`);
        assert.match(qml, new RegExp(`${service}\\.visibleEntry\\(\\)`),
            `${file}: progress still reads the raw entry`);
    }

    // The library log lines name no title, id or chapter.
    for (const [file, tag] of [
        ["services/Manga.qml", "ServiceManga"],
        ["services/Novel.qml", "ServiceNovel"],
        ["services/Anime.qml", "ServiceAnime"],
    ]) {
        const qml = read(file);
        for (const line of qml.split("\n")) {
            if (!line.includes(`[${tag}]`)) continue;
            if (!/console\.(log|warn|error)/.test(line)) continue;
            // The plan leaves the NovelBin migration error untouched.
            if (line.includes("Migrated novel not on FreeWebNovel")) continue;
            assert.doesNotMatch(line, /title|name|id\b|chapter|episode|searchText|MangaId|NovelId|AnimeId/,
                `${file}: a log line names a title or id: ${line.trim()}`);
        }
        // The progress guard exists in the service too, not only in the view.
        assert.match(qml, /Privacy\.locked && root\.isHiddenLibraryEntry\(/,
            `${file}: progress is not protected while locked`);
    }

    // No panel ever logs the typed query.
    for (const file of PANELS) {
        for (const line of read(file).split("\n")) {
            if (/console\./.test(line))
                assert.doesNotMatch(line, /searchText|header\.text/, `${file}: logs the query`);
        }
    }
});

test("folders are written atomically and a broken file blocks saves", () => {
    const org = read("services/Organizer.qml");
    assert.match(org, /atomicWrites: true/);
    assert.match(org, /Paths\.organizerPath\(root\._dataHome\)/);
    assert.match(org, /if \(!root\.loaded \|\| root\.loadFailed\) return false/,
        "a broken organizer does not block writes");
    assert.match(org, /root\.loadFailed = true/, "a broken organizer is not flagged");
    // A missing file and an unreadable file are different things: only the
    // first is a fresh install; the second must keep the last good list and
    // keep the save lock.
    assert.match(org, /error === FileViewError\.FileNotFound/,
        "an unreadable organizer is treated as missing");
    assert.match(org, /onLoadFailed: function\(error\)/, "the load error is discarded");
    // The last good list survives: onLoaded only assigns after JSON.parse.
    assert.match(org, /root\.data = parsed/);
});

test("the secret travels on stdin, never in argv, and has a watchdog", () => {
    const priv = read("services/Privacy.qml");
    assert.match(priv, /Paths\.privacyPath\(root\._dataHome\)/);
    assert.match(priv, /watchChanges: true/);
    assert.match(priv, /onFileChanged: privacyFile\.reload\(\)/);
    assert.match(priv, /command: \[ReaderEnv\.python, "-I", root\.helper, "--check", root\.path\]/);
    assert.match(priv, /checker\.write\(root\._word\)/);
    assert.match(priv, /checker\.stdinEnabled = false/, "stdin is never closed (the helper waits)");
    assert.match(priv, /interval: 2000/, "no watchdog");
    // The candidate is not part of the command line.
    assert.ok(!/command:\s*\[[^\]]*_word/.test(priv), "the word reached argv");
});

test("the visible library and the lock state are the only display path", () => {
    for (const [file, service] of [
        ["services/Manga.qml", "Manga"],
        ["services/Novel.qml", "Novel"],
        ["services/Anime.qml", "Anime"],
    ]) {
        const qml = read(file);
        assert.match(qml, /function visibleEntries\(folderId\)/);
        assert.match(qml, /function visibleEntryId\(\)/);
        assert.match(qml, /function isHiddenLibraryEntry\(entryId\)/);
        assert.match(qml, /function setFolder\(entryId, folderId\)/);
        assert.match(qml, /function deleteFolder\(folderId\)/);
    }
    // The raw accessors are untouched for writes.
    for (const file of ["services/Manga.qml", "services/Novel.qml", "services/Anime.qml"]) {
        assert.match(read(file), /function isInLibrary\(/);
        assert.match(read(file), /function getLibraryEntry\(/);
    }
});
test("leaving the Library tab locks through the shared header", () => {
    const header = read("components/PanelHeader.qml");
    assert.match(header, /import "\.\.\/services\/panels\.js" as Panels/);
    assert.match(header, /Panels\.locksOnTabChange\(root\.tabIndex, index\)/,
        "the tab cell does not ask the shared rule");
    assert.match(header, /if \(leaveLibrary\) Privacy\.lock\(\)/,
        "leaving the Library tab does not lock");

    // No panel carries its own lock copy: opening and closing a title stays
    // inside the Library stack and never changes the tab.
    for (const file of PANELS) {
        const qml = read(file);
        assert.ok(!qml.includes("Privacy.lock()"),
            `${file}: a per-panel lock call is back`);
    }

    // A hidden title open in Detail while switching tabs follows the existing
    // lock behaviour: the panel returns to the Library stack.
    for (const [file, service] of [
        ["modules/manga/MangaReader.qml", "Manga"],
        ["modules/novel/NovelReader.qml", "Novel"],
        ["modules/anime/AnimePanel.qml", "Anime"],
    ]) {
        assert.match(read(file),
            new RegExp(`${service}\\.isHiddenLibraryEntry\\([\\s\\S]{0,500}root\\.tabIndex = 1`),
            `${file}: a hidden open title no longer returns to the Library on lock`);
    }
});
