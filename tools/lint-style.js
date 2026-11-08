"use strict";

// Raw-token guards for the UI redesign (Fase R1).
//
// Fails when a view hardcodes a radius, a spacing value, a motion duration, a
// font size or a colour instead of asking the shared token singleton
// (`qs.Commons.Style`) or the theme palette (`qs.app.Colors`). `Style.*`, a
// derived expression (`height / 2`, `root.radius`), a property reference or a
// theme role all pass; a bare number on the right of a tracked property and a
// colour literal anywhere do not.
//
// Examples that fail:  radius: 12   ·   spacing: 6   ·   color: "#1a1714"
//                      color: Qt.rgba(1, 1, 1, 0.07)
// Examples that pass:  radius: Style.cornerRadius   ·   radius: height / 2
//                      color: Colors.text   ·   color: Util.alpha(Colors.text, 0.07)
//
// CLI:  node tools/lint-style.js [path ...]      (exit 1 on violations)
//       node tools/lint-style.js components modules
//       node tools/lint-style.js                    (scans the default set)

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");

// Directories scanned by default. The token source (`Commons/`), the palette
// (`colors/`), the services and the tooling themselves are never scanned.
const DEFAULT_DIRS = ["modules", "components", "omarchy"];
const DEFAULT_FILES = ["shell.qml"];

const SKIP_DIRS = new Set([".git", "node_modules", "Commons", "colors", "services", "tools", "tests", "bin", "extras"]);

// Property names whose right-hand side must come from Style.* (or a derived
// expression), never a bare number. `anchors.` is stripped before matching.
const TRACKED = new Set([
    "radius",
    "spacing",
    "rowSpacing",
    "columnSpacing",
    "margins",
    "leftMargin",
    "rightMargin",
    "topMargin",
    "bottomMargin",
    "padding",
    "leftPadding",
    "rightPadding",
    "topPadding",
    "bottomPadding",
    "duration",
    "font.pixelSize",
]);

const PURE_NUMBER = /^\d+(?:\.\d+)?$/;
// A capsule/pill/circle radius: half the element's own height or width.
const CAPSULE = /\b(?:height|width)\s*\/\s*2\b/;
// Colour literals: a hex value (`#rgb`, `#rrggbb`, `#aarrggbb`) or a Qt.rgba()
// call. Both freeze one palette into the view and stop it following the
// Omarchy theme.
const COLOR_LITERAL = /#(?:[0-9A-Fa-f]{8}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{3})\b|Qt\.rgba\(/;
// A `name: value` pair, value ending at the next `;`, `}` or end of line.
const PROP = /([A-Za-z_][A-Za-z0-9_.]*)\s*:\s*([^;}\n]*)/g;

function stripComment(line) {
    const idx = line.indexOf("//");
    return idx === -1 ? line : line.slice(0, idx);
}

// Every violation in one QML source. Exported so a test can feed a literal
// without writing a file.
function scanText(text, rel) {
    const violations = [];
    const lines = String(text).split("\n");
    for (let i = 0; i < lines.length; i++) {
        // `// style-ignore` documents a deliberate exception on that line.
        if (lines[i].includes("style-ignore")) continue;
        if (lines[i].includes("DesktopTheme")) {
            violations.push({ file: rel, line: i + 1, prop: "DesktopTheme", value: "deprecated — use Style.*" });
            continue;
        }
        const line = stripComment(lines[i]);
        const color = line.match(COLOR_LITERAL);
        if (color) {
            violations.push({ file: rel, line: i + 1, prop: "color", value: color[0] + "  → use Colors.*" });
        }
        PROP.lastIndex = 0;
        let m;
        while ((m = PROP.exec(line)) !== null) {
            let prop = m[1];
            if (prop.startsWith("anchors.")) prop = prop.slice("anchors.".length);
            if (!TRACKED.has(prop)) continue;
            const value = m[2].trim();
            if (PURE_NUMBER.test(value)) {
                violations.push({ file: rel, line: i + 1, prop: m[1], value });
            } else if (prop === "radius" && CAPSULE.test(value)) {
                // A control must use Style.cornerRadius; only genuinely round
                // things (dots, spinners, bars) keep height / 2 and opt out
                // with // style-ignore.
                violations.push({ file: rel, line: i + 1, prop: m[1], value: value + "  → capsule, use Style.cornerRadius" });
            }
        }
    }
    return violations;
}

function scanFile(abs) {
    return scanText(fs.readFileSync(abs, "utf8"), path.relative(ROOT, abs));
}

function walk(dir) {
    const out = [];
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        if (entry.isDirectory()) {
            if (SKIP_DIRS.has(entry.name)) continue;
            out.push(...walk(path.join(dir, entry.name)));
        } else if (entry.name.endsWith(".qml")) {
            out.push(path.join(dir, entry.name));
        }
    }
    return out;
}

function collectFiles(args) {
    const files = [];
    const targets = args.length > 0 ? args : DEFAULT_DIRS;
    for (const target of targets) {
        const abs = path.resolve(ROOT, target);
        if (!fs.existsSync(abs)) continue;
        if (fs.statSync(abs).isDirectory()) files.push(...walk(abs));
        else if (abs.endsWith(".qml")) files.push(abs);
    }
    if (args.length === 0) {
        for (const f of DEFAULT_FILES) {
            const abs = path.resolve(ROOT, f);
            if (fs.existsSync(abs)) files.push(abs);
        }
    }
    return files;
}

function check(args) {
    const files = collectFiles(args || []);
    return { files: files.length, violations: files.flatMap(scanFile) };
}

function main() {
    const { files, violations } = check(process.argv.slice(2));
    if (violations.length === 0) {
        console.log(`lint-style: OK (${files} files, 0 raw tokens)`);
        return 0;
    }
    for (const v of violations) {
        console.log(`${v.file}:${v.line}: ${v.prop}: ${v.value}  → use Style.*`);
    }
    console.log(`lint-style: ${violations.length} raw token(s) in ${files} files`);
    return 1;
}

if (require.main === module) process.exit(main());

module.exports = { check, collectFiles, scanFile, scanText };
