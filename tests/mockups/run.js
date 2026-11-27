"use strict";

// Runner for the version-picker mockups (PickerMockups.qml).
//
// Builds a throwaway Quickshell config root that mirrors the repository with
// symlinks plus a one-line shell.qml that instantiates PickerMockups, points
// every data/config path at a scratch folder, and runs `qs` with the offscreen
// platform once per scenario. The owner's library, settings and windows are
// never touched and no input is synthesized: the hover and switch states are
// plain bindings read from KH_MOCK.
//
// CLI:
//   node tests/mockups/run.js --out <folder>

const { spawn, spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const HERE = __dirname;
const REPO = path.resolve(HERE, "..", "..");

// qs.app / qs.services / qs.modules / qs.components must live at the config
// root. Ui/ and Commons/ are the modules the repo already carries.
const DIRS = ["app", "services", "components", "modules", "Commons", "Ui"];

const SCENARIOS = ["B-default", "B-hover-row", "B-hover-icon", "A-off", "A-on", "A-hover-row"];

const LIBRARIES = ["manga_library.json", "anime_library.json", "new_novel_library.json"];

// Valid JSON the singletons can parse: their defaults, nothing of the owner's.
const PRIVACY = JSON.stringify({
    v: 1,
    salt: "00112233445566778899aabbccddeeff",
    tag: "0",
    n: 131072,
    r: 8,
    p: 1,
    dk: "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
});

const ORGANIZER = JSON.stringify({
    anime: { folders: [] },
    manga: { folders: [] },
    novel: { folders: [] }
});

function configRoot(root, scratch) {
    const dir = path.join(scratch, "config");
    fs.mkdirSync(path.join(dir, "tests"), { recursive: true });
    for (const name of DIRS) {
        const source = path.join(root, name);
        if (fs.existsSync(source)) fs.symlinkSync(source, path.join(dir, name));
    }
    fs.symlinkSync(path.join(root, "tests", "mockups"),
        path.join(dir, "tests", "mockups"));
    fs.writeFileSync(path.join(dir, "shell.qml"),
        'import "tests/mockups"\nPickerMockups {}\n');
    return dir;
}

function dataRoot(scratch) {
    const dir = path.join(scratch, "data", "kisaru");
    fs.mkdirSync(dir, { recursive: true });
    for (const name of LIBRARIES) fs.writeFileSync(path.join(dir, name), "[]");
    fs.writeFileSync(path.join(dir, "privacy.json"), PRIVACY);
    fs.writeFileSync(path.join(dir, "organizer.json"), ORGANIZER);
    return path.join(scratch, "data");
}

function hasQs() {
    return spawnSync("sh", ["-c", "command -v qs"], { encoding: "utf8" }).status === 0;
}

function capture(scenario, outDir, dir, env) {
    return new Promise((resolve) => {
        const qs = spawn("timeout", ["60", "qs", "-p", dir], {
            env: Object.assign({}, env, {
                KH_MOCK: scenario,
                KH_CAPTURE: outDir
            }),
            stdio: ["ignore", "pipe", "pipe"]
        });
        let text = "";
        qs.stdout.on("data", (d) => { text += d; });
        qs.stderr.on("data", (d) => { text += d; });
        qs.on("exit", (code) => resolve({ code, text }));
    });
}

async function main() {
    const args = process.argv.slice(2);
    let out = "";
    for (let i = 0; i < args.length; i += 1) {
        if (args[i] === "--out") out = args[i + 1] || "";
    }

    if (!hasQs()) {
        console.log("SKIP qs not installed");
        return 0;
    }

    const outDir = path.resolve(out || path.join(os.tmpdir(), "kisaru-picker-mockups"));
    fs.mkdirSync(outDir, { recursive: true });

    const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "kisaru-picker-mockups-"));
    const runtime = path.join(scratch, "runtime");
    fs.mkdirSync(runtime, { mode: 0o700 });
    const dir = configRoot(REPO, scratch);
    const data = dataRoot(scratch);
    const configHome = path.join(scratch, "config-home");
    fs.mkdirSync(configHome, { recursive: true });
    const env = Object.assign({}, process.env, {
        QT_QPA_PLATFORM: "offscreen",
        QT_QPA_PLATFORMTHEME: "",
        XDG_RUNTIME_DIR: runtime,
        XDG_DATA_HOME: data,
        XDG_CONFIG_HOME: configHome
    });
    delete env.WAYLAND_DISPLAY;
    delete env.DISPLAY;

    let failed = 0;
    try {
        for (const scenario of SCENARIOS) {
            const result = await capture(scenario, outDir, dir, env);
            const file = path.join(outDir, scenario + ".png");
            const ok = fs.existsSync(file) && fs.statSync(file).size > 0;
            console.log((ok ? "OK   " : "FAIL ") + file);
            if (!ok) {
                failed += 1;
                const lines = result.text.split("\n")
                    .filter((line) => /Error|error|CAPTURE|Failed|failed/.test(line))
                    .slice(-12);
                console.log("     qs exit " + result.code + (lines.length ? "\n     " + lines.join("\n     ") : ""));
            }
        }
    } finally {
        fs.rmSync(scratch, { recursive: true, force: true });
    }
    return failed === 0 ? 0 : 1;
}

main().then((code) => process.exit(code)).catch((error) => {
    console.error(error);
    process.exit(1);
});
