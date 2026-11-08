"use strict";

// The readers follow the Omarchy theme (owner report 2026-11-08: "el lector no
// toma el tema seleccionado de omarchy"). The novel reader used to paint a warm
// paper palette copied by hand; the manga reader kept an ink-black mat. Both now
// read the same theme roles as the rest of Kisaru, and every line of text sits
// on the theme's ground at full strength, so the theme's own foreground/background
// pair decides the contrast (>= 4.5:1 on the dark and the light themes).
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const contrast = require("../services/contrast.js");

const ROOT = path.resolve(__dirname, "..");
const read = (rel) => fs.readFileSync(path.join(ROOT, rel), "utf8");

const NOVEL = "modules/novel/components/ReaderView.qml";
const MANGA = "modules/manga/components/ReaderView.qml";

// Palettes that do not depend on this machine: the darkest theme the owner
// measured (solarized-osaka), a well-known light theme and a warm light one.
const FIXTURES = [
    { name: "solarized-osaka (dark)", mode: "dark", background: "#001419", foreground: "#839395", accent: "#268bd3", urgent: "#db302d" },
    { name: "solarized-light", mode: "light", background: "#fdf6e3", foreground: "#586e75", accent: "#268bd3", urgent: "#dc322f" },
    { name: "warm-light", mode: "light", background: "#f5efe6", foreground: "#4a4038", accent: "#a05a2c", urgent: "#b03a2e" }
];

// Every theme installed under the two Omarchy theme folders, read-only.
function installedThemes() {
    const home = process.env.HOME || "";
    const dirs = [
        path.join(home, ".local/share/omarchy/themes"),
        path.join(home, ".config/omarchy/themes")
    ];
    const themes = [];
    for (const dir of dirs) {
        if (!dir || !fs.existsSync(dir)) continue;
        for (const name of fs.readdirSync(dir)) {
            const file = path.join(dir, name, "colors.toml");
            if (!fs.existsSync(file)) continue;
            const text = fs.readFileSync(file, "utf8");
            const pick = (key) => {
                const match = text.match(new RegExp("^" + key + '\\s*=\\s*"(#[0-9A-Fa-f]{6})"', "m"));
                return match ? match[1] : "";
            };
            const background = pick("background");
            const foreground = pick("foreground");
            if (!background || !foreground) continue;
            themes.push({
                name: name + " (" + ((text.match(/^mode\s*=\s*"(\w+)"/m) || [])[1] || "unknown") + ")",
                mode: (text.match(/^mode\s*=\s*"(\w+)"/m) || [])[1] || "unknown",
                background: background,
                foreground: foreground,
                accent: pick("accent"),
                urgent: pick("red")
            });
        }
    }
    return themes;
}

const PALETTES = FIXTURES.concat(installedThemes());

test("the reader tokens are the theme's own foreground and background", () => {
    const colors = read("app/Colors.qml");
    assert.match(colors, /readonly property color background: Commons\.Color\.background/);
    assert.match(colors, /readonly property color text: Commons\.Color\.foreground/);
});

test("every theme clears 4.5:1 for reader text", () => {
    for (const palette of PALETTES) {
        const ratio = contrast.ratio(palette.foreground, palette.background);
        assert.ok(ratio >= 4.5,
            palette.name + ": text on the page is " + ratio.toFixed(2) + ":1");
    }
});

test("the warning icon stays visible on every theme", () => {
    for (const palette of PALETTES) {
        if (!palette.urgent) continue;
        const ratio = contrast.ratio(palette.urgent, palette.background);
        assert.ok(ratio >= 3,
            palette.name + ": the warning icon is " + ratio.toFixed(2) + ":1");
    }
});

// The reader must not dim its text: a token at 85% alpha would drop the
// darkest theme below 4.5:1 even though the theme pair clears it.
test("the novel reader paints every text with a full-strength theme role", () => {
    const qml = read(NOVEL);
    const ELEMENT = /\b(StyledText|Text)\s*\{([^}]*)\}/g;
    let found = 0;
    let match;
    while ((match = ELEMENT.exec(qml)) !== null) {
        found++;
        const body = match[2];
        const color = body.match(/color:\s*([^;}\n]+)/);
        assert.ok(color, "a " + match[1] + " has no colour: " + body.trim());
        const value = color[1].trim().replace(/\s*\/\/.*$/, "");
        assert.match(value, /^Colors\.(text|error)$/,
            "the reader dims or hard-codes text: " + value);
        assert.ok(!/\bopacity\s*:/.test(body),
            "the reader dims text with opacity: " + body.trim());
    }
    assert.ok(found >= 12, "only " + found + " text elements found");
});

// A hover fill sits behind the icon it highlights; at 10% it already pushes
// solarized-light below 4.5:1, so the fill is capped.
test("hover fills keep the theme pair above 4.5:1", () => {
    const qml = read(NOVEL);
    const fills = [...qml.matchAll(/containsMouse[^\n]*?Util\.alpha\(Colors\.text,\s*([\d.]+)\)/g)];
    assert.ok(fills.length >= 3, "only " + fills.length + " hover fills found");
    for (const fill of fills) {
        const alpha = Number(fill[1]);
        assert.ok(alpha <= 0.06, "a hover fill uses " + alpha);
        for (const palette of PALETTES) {
            const tint = contrast.mix(palette.background, palette.foreground, alpha);
            const ratio = contrast.ratio(palette.foreground, tint);
            assert.ok(ratio >= 4.5,
                palette.name + ": text on a " + alpha + " hover fill is " + ratio.toFixed(2) + ":1");
        }
    }
});

test("the novel reader draws its page and chrome from the theme", () => {
    const qml = read(NOVEL);
    assert.match(qml, /anchors\.fill: parent; color: Colors\.background/,
        "the page ground is not the theme background");
    assert.ok(!/#[0-9a-fA-F]{3,8}\b/.test(qml), "a hex colour survived");
    assert.ok(!/Qt\.rgba\(/.test(qml), "a Qt.rgba() colour survived");
    assert.ok(!/intentional/.test(qml), "the 'warm palette is intentional' note survived");
    assert.ok(!qml.includes("#1a1714"), "the warm ground survived");
    assert.match(qml, /color: Colors\.surface_container_low|color: Colors\.background/,
        "the chrome bars do not read a theme surface");
});

test("the manga reader's three literals are theme colours", () => {
    const qml = read(MANGA);
    assert.ok(!qml.includes("#08080a"), "the ink-black mat survived");
    assert.ok(!/Qt\.rgba\(/.test(qml), "a Qt.rgba() colour survived");
    assert.match(qml, /Rectangle \{ anchors\.fill: parent; color: Colors\.background \}/,
        "the reading mat is not the theme background");
    assert.match(qml, /textColor: Colors\.text/,
        "the loading caption is still hard-coded white");
});

test("the README no longer calls the warm palette intentional", () => {
    const text = read("README.md");
    assert.ok(!text.includes("#1a1714"), "the README still names the warm ground");
    assert.ok(!/fondo cálido|paleta cálida|imitan papel|no siguen el tema/.test(text),
        "the README still says the novel reader ignores the theme");
    assert.match(text, /lector de novelas/);
    assert.match(text, /siguen el tema|sigue el tema/);
});
