"use strict";

// `kisaru update` (S6, A8–A15), run the way the floating terminal runs it.
//
// Every case is sandboxed: a bare git remote, a clone under mktemp -d, a temp
// HOME, a temp XDG_CONFIG_HOME and a temp XDG_DATA_HOME. `qs`, `pip`, `setsid`
// and `uwsm-app` are stubs on PATH that only record what they were asked to do.
// The owner's install and the running Kisaru are never touched.
//
// Run with:  node --test

const test = require("node:test");
const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const BIN = path.join(ROOT, "bin", "kisaru");

function git(args, cwd) {
    const result = spawnSync("git", args, { cwd, encoding: "utf8" });
    if (result.status !== 0)
        throw new Error(`git ${args.join(" ")} failed: ${result.stderr}`);
    return result.stdout.trim();
}

function writeManifest(root, version) {
    const dir = path.join(root, "omarchy", "pwnsxb.kisaru");
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, "manifest.json"),
        JSON.stringify({ schemaVersion: 1, id: "pwnsxb.kisaru", version }, null, 2) + "\n");
}

function stub(file, body) {
    fs.writeFileSync(file, "#!/usr/bin/env bash\n" + body);
    fs.chmodSync(file, 0o755);
}

// A release pair: v1.0.0 (installed) and v1.1.0 (newer). `requirements: false`
// keeps requirements.txt identical between them.
function sandbox(options) {
    const changeRequirements = !options || options.requirements !== false;
    const changePanel = !!options && options.panel === true;
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "kisaru-update-"));
    const home = path.join(dir, "home");
    const configHome = path.join(dir, "config");
    const dataHome = path.join(dir, "data");
    const binDir = path.join(dir, "bin");
    for (const folder of [home, configHome, dataHome, binDir])
        fs.mkdirSync(folder, { recursive: true });

    const src = path.join(dir, "src");
    fs.mkdirSync(src);
    writeManifest(src, "1.0.0");
    fs.writeFileSync(path.join(src, "shell.qml"), "// shell\n");
    fs.writeFileSync(path.join(src, "requirements.txt"), "old-pin==1\n");
    git(["init", "-q", "-b", "main"], src);
    git(["config", "user.email", "test@example.invalid"], src);
    git(["config", "user.name", "kisaru test"], src);
    git(["add", "."], src);
    git(["commit", "-qm", "release 1.0.0"], src);
    git(["tag", "v1.0.0"], src);

    writeManifest(src, "1.1.0");
    fs.appendFileSync(path.join(src, "shell.qml"), "// newer\n");
    if (changeRequirements)
        fs.writeFileSync(path.join(src, "requirements.txt"), "new-pin==2\n");
    if (changePanel)
        fs.writeFileSync(path.join(src, "omarchy", "pwnsxb.kisaru", "Panel.qml"), "// newer panel\n");
    git(["add", "."], src);
    git(["commit", "-qm", "release 1.1.0"], src);
    git(["tag", "v1.1.0"], src);
    // A prerelease must never be offered or installed.
    git(["tag", "v9.9.9-rc.1"], src);

    const remote = path.join(dir, "remote.git");
    git(["init", "-q", "--bare", remote], dir);
    git(["symbolic-ref", "HEAD", "refs/heads/main"], remote);
    git(["remote", "add", "origin", remote], src);
    git(["push", "-q", "--tags", "origin", "main"], src);

    const cfg = path.join(configHome, "kisaru");
    git(["clone", "-q", "--branch", "main", remote, cfg], dir);
    git(["checkout", "-q", "-B", "main", "v1.0.0"], cfg);
    git(["config", "user.email", "test@example.invalid"], cfg);
    git(["config", "user.name", "kisaru test"], cfg);

    const venv = path.join(dataHome, "kisaru", "venv");
    fs.mkdirSync(path.join(venv, "bin"), { recursive: true });
    stub(path.join(venv, "bin", "pip"),
        `printf '%s\\n' "$*" >> "\${PIP_LOG:-/dev/null}"\n` +
        `if [[ \${PIP_FAIL_ONCE:-0} == 1 && ! -e \${PIP_FAILED:-/nonexistent} ]]; then\n` +
        "  : > \"${PIP_FAILED}\"\n  exit 1\nfi\nexit 0\n");

    stub(path.join(binDir, "qs"),
        `printf '%s\\n' "$*" >> "\${QS_LOG:-/dev/null}"\n` +
        `if [[ $* == *"ipc show"* ]]; then [[ -e \${QS_RUNNING:-/nonexistent} ]] && exit 0 || exit 1; fi\n` +
        `if [[ $* == *"ipc call"* ]]; then exit 0; fi\n` +
        `if [[ $* == *" kill" ]]; then [[ \${QS_KILL_FAIL:-0} == 1 ]] && exit 0; rm -f "\${QS_RUNNING:-/nonexistent}"; exit 0; fi\n` +
        'if [[ $* == *--no-duplicate* ]]; then [[ ${QS_START_FAIL:-0} == 1 ]] && exit 1; : > "${QS_RUNNING:-/dev/null}"; exit 0; fi\n' +
        "exit 0\n");
    stub(path.join(binDir, "setsid"), 'while [[ ${1-} == -* ]]; do shift; done\nexec "$@"\n');
    stub(path.join(binDir, "uwsm-app"), '[[ ${1-} == -- ]] && shift\nexec "$@"\n');

    const log = (name) => path.join(dir, name + ".log");
    return {
        dir,
        cfg,
        venv,
        env: {
            HOME: home,
            XDG_CONFIG_HOME: configHome,
            XDG_DATA_HOME: dataHome,
            PATH: binDir + path.delimiter + process.env.PATH,
            QS_LOG: log("qs"),
            QS_RUNNING: path.join(dir, "qs.running"),
            PIP_LOG: log("pip"),
            PIP_FAILED: path.join(dir, "pip.failed")
        }
    };
}

function run(args, box, extraEnv) {
    return spawnSync("bash", [BIN, ...args], {
        cwd: box.dir,
        encoding: "utf8",
        timeout: 60000,
        env: { ...process.env, ...box.env, ...extraEnv }
    });
}

function read(file) {
    return fs.existsSync(file) ? fs.readFileSync(file, "utf8") : "";
}

function manifestVersion(box) {
    return JSON.parse(fs.readFileSync(
        path.join(box.cfg, "omarchy", "pwnsxb.kisaru", "manifest.json"), "utf8")).version;
}

// A second valid Kisaru checkout in the same sandbox, at v1.0.0. The default
// clone stays at $XDG_CONFIG_HOME/kisaru; `--config` must act only on this one.
function addSecondClone(box) {
    const other = path.join(box.dir, "second", "kisaru");
    fs.mkdirSync(path.dirname(other), { recursive: true });
    git(["clone", "-q", "--branch", "main", path.join(box.dir, "remote.git"), other], box.dir);
    git(["checkout", "-q", "-B", "main", "v1.0.0"], other);
    return other;
}

test("update fast-forwards, refreshes the venv and restarts with the panel", () => {
    const box = sandbox();
    fs.writeFileSync(box.env.QS_RUNNING, "");

    const result = run(["update", "--reopen", "manga"], box);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Listo\. Kisaru 1\.1\.0/);
    // Every release bumps the manifest; that alone must not ask for a shell
    // restart (F2), so the default release keeps quiet.
    assert.doesNotMatch(result.stdout, /omarchy restart shell/);
    assert.equal(manifestVersion(box), "1.1.0");
    assert.equal(git(["rev-parse", "HEAD"], box.cfg),
        git(["rev-parse", "v1.1.0"], box.cfg));

    const pip = read(box.env.PIP_LOG);
    assert.match(pip, /--require-hashes/);
    assert.match(pip, /requirements\.txt/);
    assert.equal(pip.trim().split("\n").length, 1, "pip must run once");

    const qs = read(box.env.QS_LOG);
    assert.match(qs, / kill/, "the running instance was not stopped");
    assert.match(qs, /--no-duplicate/, "the instance was not started again");
    assert.match(qs, /ipc call mangaReader toggle/, "the panel was not reopened");
});

test("update ignores prerelease tags and stops when already current", () => {
    const box = sandbox();
    git(["checkout", "-q", "-B", "main", "v1.1.0"], box.cfg);

    const result = run(["update"], box);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /ya estás en la última versión/);
    assert.match(result.stdout, /1\.1\.0/);
    assert.doesNotMatch(result.stdout, /9\.9\.9/);
    assert.equal(read(box.env.PIP_LOG), "", "pip must not run when nothing changed");
    assert.equal(read(box.env.QS_LOG), "", "nothing to restart when already current");
});

test("a dirty tree is refused before any command runs", () => {
    const box = sandbox();
    const before = git(["rev-parse", "HEAD"], box.cfg);
    fs.appendFileSync(path.join(box.cfg, "shell.qml"), "// local edit\n");

    const result = run(["update"], box);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /cambios locales/);
    assert.equal(git(["rev-parse", "HEAD"], box.cfg), before);
    assert.equal(read(box.env.PIP_LOG), "");
    assert.equal(read(box.env.QS_LOG), "");
});

test("another branch is refused before any command runs", () => {
    const box = sandbox();
    git(["checkout", "-q", "-b", "feature"], box.cfg);
    const before = git(["rev-parse", "HEAD"], box.cfg);

    const result = run(["update"], box);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /no en main/);
    assert.equal(git(["rev-parse", "HEAD"], box.cfg), before);
    assert.equal(read(box.env.PIP_LOG), "");
});

test("--reopen rejects an unknown panel before touching git", () => {
    const box = sandbox();
    const before = git(["rev-parse", "HEAD"], box.cfg);

    const result = run(["update", "--reopen", "video"], box);
    assert.equal(result.status, 2);
    assert.match(result.stderr, /--reopen/);
    assert.equal(git(["rev-parse", "HEAD"], box.cfg), before);
    assert.equal(read(box.env.QS_LOG), "");
});

test("local main with commits outside the release is refused, not merged", () => {
    const box = sandbox();
    fs.writeFileSync(path.join(box.cfg, "local.txt"), "local\n");
    git(["add", "local.txt"], box.cfg);
    git(["commit", "-qm", "local work"], box.cfg);
    const before = git(["rev-parse", "HEAD"], box.cfg);

    const result = run(["update"], box);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /commits que no están/);
    assert.equal(git(["rev-parse", "HEAD"], box.cfg), before);
    assert.equal(manifestVersion(box), "1.0.0");
});

test("a pip failure rolls the checkout back and reports it", () => {
    const box = sandbox();
    const before = git(["rev-parse", "HEAD"], box.cfg);
    fs.writeFileSync(box.env.QS_RUNNING, "");

    const result = run(["update"], box, { PIP_FAIL_ONCE: "1" });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /falló pip/);
    assert.equal(git(["rev-parse", "HEAD"], box.cfg), before);
    assert.equal(manifestVersion(box), "1.0.0");

    const pip = read(box.env.PIP_LOG).trim().split("\n");
    assert.equal(pip.length, 2, "pip must be retried with the old requirements");
    assert.equal(read(box.env.QS_LOG).includes(" kill"), false,
        "a failed update must not restart Kisaru");
});

test("requirements.txt unchanged means no venv work", () => {
    const box = sandbox({ requirements: false });

    const result = run(["update"], box);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Listo\. Kisaru 1\.1\.0/);
    assert.equal(read(box.env.PIP_LOG), "", "pip must not run when the pins did not change");
});

// F2: a release always bumps omarchy/pwnsxb.kisaru/manifest.json, so the hint
// must depend on the rest of omarchy/, not on the manifest.
test("a release that only bumps the manifest does not ask for a shell restart", () => {
    const box = sandbox();

    const result = run(["update"], box);
    assert.equal(result.status, 0, result.stderr);
    assert.doesNotMatch(result.stdout, /omarchy restart shell/);
});

test("a Panel.qml change does ask for an omarchy shell restart", () => {
    const box = sandbox({ panel: true });

    const result = run(["update"], box);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /omarchy restart shell/);
});

test("a --copy install (no .git) is refused with the reinstall message", () => {
    const box = sandbox();
    const copyHome = path.join(box.dir, "configcopy");
    const copy = path.join(copyHome, "kisaru");
    fs.mkdirSync(copyHome, { recursive: true });
    fs.cpSync(box.cfg, copy, { recursive: true, filter: (item) => !item.includes(`${path.sep}.git`) });
    assert.equal(fs.existsSync(path.join(copy, ".git")), false);
    box.cfg = copy;
    box.env.XDG_CONFIG_HOME = copyHome;

    const result = run(["update"], box);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /checkout git|reinstala/);
    assert.equal(read(box.env.PIP_LOG), "");
});

test("nothing is started when Kisaru was not running and no panel is asked for", () => {
    const box = sandbox();

    const result = run(["update"], box);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Listo\. Kisaru 1\.1\.0/);
    const qs = read(box.env.QS_LOG);
    assert.doesNotMatch(qs, /--no-duplicate/);
    assert.doesNotMatch(qs, / kill/);
});

// The restart must report the truth (A12): if the launcher loses the app, a
// success line would leave the user with no Kisaru and no clue. Both directions are
// polled, so both are pinned here.
test("a relaunch that never comes back is an error, not a success line", () => {
    const box = sandbox();
    fs.writeFileSync(box.env.QS_RUNNING, "");

    const result = run(["update"], box, { QS_START_FAIL: "1" });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /no volvió a arrancar/);
    assert.doesNotMatch(result.stdout, /Listo\. Kisaru/);
});

test("an instance that refuses to stop is an error, not a restart", () => {
    const box = sandbox();
    fs.writeFileSync(box.env.QS_RUNNING, "");

    const result = run(["update"], box, { QS_KILL_FAIL: "1" });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /no se detuvo/);
    assert.doesNotMatch(result.stdout, /Listo\. Kisaru/);
});

// S1-S3: the update acts on the install named by --config, not on the default
// $XDG_CONFIG_HOME/kisaru. Both the restart and the IPC reopen must use that
// exact path, because qs identifies the running instance by it.
test("--config updates and restarts the named install, not the default one", () => {
    const box = sandbox();
    const other = addSecondClone(box);
    const defaultHead = git(["rev-parse", "HEAD"], box.cfg);

    const result = run(["update", "--config", other, "--reopen", "manga"], box);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Listo\. Kisaru 1\.1\.0/);
    assert.equal(git(["rev-parse", "HEAD"], other), git(["rev-parse", "v1.1.0"], other));
    assert.equal(manifestVersion({ cfg: other }), "1.1.0");
    assert.equal(git(["rev-parse", "HEAD"], box.cfg), defaultHead,
        "the default install moved");
    assert.equal(manifestVersion(box), "1.0.0");

    const qs = read(box.env.QS_LOG).trim().split("\n");
    const start = qs.find((line) => line.includes("--no-duplicate"));
    const reopen = qs.find((line) => line.includes("ipc call mangaReader toggle"));
    assert.ok(start && start.includes("-p " + other),
        "the restart did not use --config: " + start);
    assert.ok(reopen && reopen.includes("-p " + other),
        "the reopen did not use --config: " + reopen);
    assert.ok(!qs.some((line) => line.includes("-p " + box.cfg)),
        "a qs call used the default install");
});

test("--config and --reopen work in either order", () => {
    const box = sandbox();
    const other = addSecondClone(box);

    const result = run(["update", "--reopen", "novel", "--config", other], box);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Listo\. Kisaru 1\.1\.0/);
    assert.ok(read(box.env.QS_LOG).includes("-p " + other + " ipc call novelReader toggle"),
        "the reverse order lost the config dir or the panel");
});

test("--config without a folder exits 2 before touching anything", () => {
    const box = sandbox();

    const result = run(["update", "--config"], box);
    assert.equal(result.status, 2);
    assert.match(result.stderr, /--config necesita una carpeta/);
    assert.equal(read(box.env.QS_LOG), "");
    assert.equal(manifestVersion(box), "1.0.0");
});

test("--config with no shell.qml exits 2 and touches neither clone", () => {
    const box = sandbox();
    const other = addSecondClone(box);
    const defaultHead = git(["rev-parse", "HEAD"], box.cfg);
    const otherHead = git(["rev-parse", "HEAD"], other);
    const bad = path.join(box.dir, "not-kisaru");
    fs.mkdirSync(bad);

    const result = run(["update", "--config", bad], box);
    assert.equal(result.status, 2);
    assert.match(result.stderr, new RegExp(bad.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
        + " no es una instalación de Kisaru"));
    assert.equal(git(["rev-parse", "HEAD"], box.cfg), defaultHead);
    assert.equal(git(["rev-parse", "HEAD"], other), otherHead);
    assert.equal(read(box.env.QS_LOG), "", "a qs command ran for a bad config");
});

// Review correction R3-DefaultUpdateDiagnostic: skipping the pre-dispatch check
// must not change the invocation that does not use --config. With no default
// install it keeps its message and exit 1; only --config gets the new error.
test("without --config, a missing default keeps its old message and exit", () => {
    const box = sandbox();
    const empty = path.join(box.dir, "empty-config");
    fs.mkdirSync(empty);
    box.env.XDG_CONFIG_HOME = empty;

    const result = run(["update"], box);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /no hay configuración en .*kisaru \(ejecuta su install\.sh\)/);
    assert.equal(read(box.env.QS_LOG), "");
});

// A1: the whole point of parsing --config before the check is that it works
// even when the default install does not exist.
test("--config works when the default install is missing", () => {
    const box = sandbox();
    const other = addSecondClone(box);
    const empty = path.join(box.dir, "empty-config");
    fs.mkdirSync(empty);
    box.env.XDG_CONFIG_HOME = empty;

    const result = run(["update", "--config", other], box);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Listo\. Kisaru 1\.1\.0/);
    assert.equal(manifestVersion({ cfg: other }), "1.1.0");
});
