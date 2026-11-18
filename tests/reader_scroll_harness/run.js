"use strict";

// Runner for the headless reader harness (Harness.qml + server.js).
//
// Starts the delayed image server on a free port, runs `qs` with the offscreen
// platform and its own XDG_RUNTIME_DIR, and returns the RESULT line, the qs log
// and the requests the server saw. It never touches port 5150 or a running
// Kisaru.
//
// Quickshell refuses imports from outside its config folder, and Harness.qml
// imports ../../components. So each run builds a throwaway config root that
// mirrors the repository with symlinks (components/ and
// tests/reader_scroll_harness/) plus a two-line shell.qml that instantiates
// Harness: the real files are loaded, nothing is copied.
//
// CLI:
//   node tests/reader_scroll_harness/run.js [--scenario scroll|retry]
//        [--delays '<json array>'] [--refetch <s>] [--root <repo-like dir>]
// `--root` runs against another tree with the same layout, for example an
// export of older components, without committing a second version.

const { spawn, spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const HERE = __dirname;
const REPO = path.resolve(HERE, "..", "..");

function configRoot(root, scratch) {
    const dir = path.join(scratch, "config");
    fs.mkdirSync(path.join(dir, "tests"), { recursive: true });
    fs.symlinkSync(path.join(root, "components"), path.join(dir, "components"));
    fs.symlinkSync(path.join(root, "tests", "reader_scroll_harness"),
        path.join(dir, "tests", "reader_scroll_harness"));
    fs.writeFileSync(path.join(dir, "shell.qml"), 'import "tests/reader_scroll_harness"\nHarness {}\n');
    return dir;
}

function hasQs() {
    return spawnSync("sh", ["-c", "command -v qs"], { encoding: "utf8" }).status === 0;
}

function startServer(config) {
    return new Promise((resolve, reject) => {
        const child = spawn(process.execPath, [path.join(HERE, "server.js"), JSON.stringify(config)],
            { stdio: ["ignore", "pipe", "inherit"] });
        const requests = [];
        let buffer = "";
        let resolved = false;
        child.stdout.on("data", (data) => {
            buffer += data;
            let nl;
            while ((nl = buffer.indexOf("\n")) >= 0) {
                const line = buffer.slice(0, nl);
                buffer = buffer.slice(nl + 1);
                if (line.startsWith("REQ ")) requests.push(line.slice(4));
                const port = /^PORT (\d+)$/.exec(line);
                if (port && !resolved) {
                    resolved = true;
                    resolve({ port: Number(port[1]), requests, stop: () => child.kill() });
                }
            }
        });
        child.on("error", reject);
        child.on("exit", (code) => { if (!resolved) reject(new Error(`server exited ${code}`)); });
    });
}

const SCENARIOS = {
    scroll: { delays: [0.1, 0.3, 0.6, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0, 5.5], refetch: 1.5, fail: {} },
    retry: { delays: [0.1, 0.2, 0.2, 0], refetch: 0.5, fail: { p1: 1, p2: 2 } },
};

async function runHarness(options = {}) {
    const scenario = options.scenario || "scroll";
    const base = SCENARIOS[scenario];
    if (!base) throw new Error(`unknown scenario ${scenario}`);
    const config = {
        delays: options.delays || base.delays,
        refetch: options.refetch === undefined ? base.refetch : options.refetch,
        fail: options.fail || base.fail,
    };
    const root = path.resolve(options.root || REPO);
    const server = await startServer(config);
    const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "kisaru-harness-"));
    const runtime = path.join(scratch, "runtime");
    fs.mkdirSync(runtime, { mode: 0o700 });
    const dir = configRoot(root, scratch);
    const env = Object.assign({}, process.env, {
        QT_QPA_PLATFORM: "offscreen",
        QT_QPA_PLATFORMTHEME: "",
        XDG_RUNTIME_DIR: runtime,
        KH_SCENARIO: scenario,
        KH_PORT: String(server.port),
    });
    delete env.WAYLAND_DISPLAY;
    delete env.DISPLAY;
    try {
        const out = await new Promise((resolve) => {
            const qs = spawn("timeout", ["120", "qs", "-p", dir], { env, stdio: ["ignore", "pipe", "pipe"] });
            let text = "";
            qs.stdout.on("data", (d) => { text += d; });
            qs.stderr.on("data", (d) => { text += d; });
            qs.on("exit", (code) => resolve({ code, text }));
        });
        const log = out.text.split("\n").map((l) => l.replace(/^.*?(?:INFO|WARN|DEBUG)[^:]*: /, ""));
        const result = log.find((l) => l.startsWith("RESULT ")) || null;
        return { code: out.code, result, pass: !!result && result.startsWith("RESULT PASS"),
            log, requests: server.requests.slice(), config };
    } finally {
        server.stop();
        fs.rmSync(scratch, { recursive: true, force: true });
    }
}

module.exports = { runHarness, hasQs, SCENARIOS };

if (require.main === module) {
    const args = process.argv.slice(2);
    const opt = {};
    for (let i = 0; i < args.length; i += 2) {
        const key = args[i].replace(/^--/, "");
        const value = args[i + 1];
        if (key === "delays") opt.delays = JSON.parse(value);
        else if (key === "refetch") opt.refetch = Number(value);
        else if (key === "fail") opt.fail = JSON.parse(value);
        else opt[key] = value;
    }
    if (!hasQs()) {
        console.log("SKIP qs not installed");
        process.exit(0);
    }
    runHarness(opt).then((r) => {
        if (process.env.KH_VERBOSE) console.log(r.log.join("\n"));
        if (r.config.fail && Object.keys(r.config.fail).length) console.log("REQUESTS " + r.requests.join(" "));
        console.log(r.result || `NO RESULT (qs exit ${r.code})\n${r.log.slice(-20).join("\n")}`);
        process.exit(r.pass ? 0 : 1);
    });
}
