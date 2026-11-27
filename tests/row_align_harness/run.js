"use strict";

// Runner for the headless list-row alignment harness (Harness.qml).
//
// Builds a throwaway Quickshell config root that mirrors the repository with
// symlinks plus a one-line shell.qml that instantiates Harness, points every
// data/config path at a scratch folder, and runs `qs` with the offscreen
// platform. The owner's library, settings and windows are never touched.
//
// CLI:
//   node tests/row_align_harness/run.js [--scenario manga|anime|novel]

const { spawn, spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const HERE = __dirname;
const REPO = path.resolve(HERE, "..", "..");

// qs.app / qs.services / qs.modules / qs.components must live at the config
// root. Ui/ and Commons/ are the Omarchy symlinks the repo already carries.
const DIRS = ["app", "services", "components", "modules", "Commons", "Ui"];

// Valid JSON the singletons can parse: their defaults, nothing of the owner's.
const LIBRARIES = ["manga_library.json", "anime_library.json", "new_novel_library.json"];

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
    fs.symlinkSync(path.join(root, "tests", "row_align_harness"),
        path.join(dir, "tests", "row_align_harness"));
    fs.writeFileSync(path.join(dir, "shell.qml"),
        'import "tests/row_align_harness"\nHarness {}\n');
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

async function runHarness(options = {}) {
    const scenario = options.scenario || "manga";
    const root = path.resolve(options.root || REPO);
    const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "kisaru-rows-"));
    const runtime = path.join(scratch, "runtime");
    fs.mkdirSync(runtime, { mode: 0o700 });
    const dir = configRoot(root, scratch);
    const data = dataRoot(scratch);
    const configHome = path.join(scratch, "config-home");
    fs.mkdirSync(configHome, { recursive: true });
    const env = Object.assign({}, process.env, {
        QT_QPA_PLATFORM: "offscreen",
        QT_QPA_PLATFORMTHEME: "",
        XDG_RUNTIME_DIR: runtime,
        XDG_DATA_HOME: data,
        XDG_CONFIG_HOME: configHome,
        KH_SCENARIO: scenario,
    });
    if (options.capture) env.KH_CAPTURE = path.resolve(options.capture);
    else delete env.KH_CAPTURE;
    delete env.WAYLAND_DISPLAY;
    delete env.DISPLAY;
    try {
        const out = await new Promise((resolve) => {
            const qs = spawn("timeout", ["90", "qs", "-p", dir],
                { env, stdio: ["ignore", "pipe", "pipe"] });
            let text = "";
            qs.stdout.on("data", (d) => { text += d; });
            qs.stderr.on("data", (d) => { text += d; });
            qs.on("exit", (code) => resolve({ code, text }));
        });
        const log = out.text.split("\n").map((l) =>
            l.replace(/^.*?(?:INFO|WARN|DEBUG|ERROR)[^:]*: /, ""));
        const result = log.find((l) => l.startsWith("RESULT ")) || null;
        return {
            code: out.code,
            result,
            pass: !!result && result.startsWith("RESULT PASS"),
            log,
            scenario,
        };
    } finally {
        fs.rmSync(scratch, { recursive: true, force: true });
    }
}

module.exports = { runHarness, hasQs };

if (require.main === module) {
    const args = process.argv.slice(2);
    const opt = {};
    for (let i = 0; i < args.length; i += 2) {
        opt[args[i].replace(/^--/, "")] = args[i + 1];
    }
    if (!hasQs()) {
        console.log("SKIP qs not installed");
        process.exit(0);
    }
    runHarness(opt).then((r) => {
        if (process.env.KH_VERBOSE) console.log(r.log.join("\n"));
        console.log(r.result || `NO RESULT (qs exit ${r.code})\n${r.log.slice(-25).join("\n")}`);
        process.exit(r.pass ? 0 : 1);
    });
}
