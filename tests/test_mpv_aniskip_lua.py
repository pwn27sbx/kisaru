"""Tests for scripts/mpv_aniskip.lua — mpv Lua skip actor (WU-3).

Runs syntax validation (`luac -p`) and executes the real Lua script under
`luajit`/`lua` with an in-memory mock of mpv's `mp`, `mp.options`, and
`mp.utils` modules. Zero real mpv windows, zero network calls.

Run: python3 -m unittest tests/test_mpv_aniskip_lua.py
"""

import http.server
import json
import os
import shutil
import subprocess
import threading
import unittest
import urllib.parse

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LUA_SCRIPT = os.path.join(ROOT, "scripts", "mpv_aniskip.lua")
LUA_BIN = shutil.which("luajit") or shutil.which("lua")
LUAC_BIN = shutil.which("luac")
MPV_BIN = shutil.which("mpv")
NODE_BIN = shutil.which("node")


def _to_lua_value(v) -> str:
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, list):
        return "{ " + ", ".join(_to_lua_value(x) for x in v) + " }"
    if isinstance(v, dict):
        return "{ " + ", ".join(f"[{json.dumps(str(k))}] = {_to_lua_value(val)}" for k, val in v.items()) + " }"
    raise TypeError(f"Unsupported type: {type(v)}")


def _run_lua_scenario(script_opts: dict, response_json: str, actions_lua: str) -> dict:
    """Load scripts/mpv_aniskip.lua inside a mocked mpv environment and run actions."""
    parsed_response_lua = _to_lua_value(json.loads(response_json))
    harness = f"""
local script_opts = {_to_lua_value(script_opts)}
local mock_response = {json.dumps(response_json)}
local mock_parsed = {parsed_response_lua}

local state = {{
    props = {{
        duration = 1440.0,
        ["time-pos"] = 0.0,
        ["chapter-list"] = {{}},
    }},
    events = {{}},
    observers = {{}},
    bindings = {{}},
    binding_history = {{}},
    timers = {{}},
    osd = {{}},
    commands = {{}},
    async_calls = {{}},
}}

local mp = {{}}

function mp.register_event(name, fn)
    state.events[name] = fn
end

function mp.observe_property(name, _ptype, fn)
    state.observers[name] = fn
end

function mp.get_property_number(name, default)
    local v = state.props[name]
    if type(v) == "number" then return v end
    return default
end

function mp.get_property_native(name, default)
    local v = state.props[name]
    if v == nil then return default end
    return v
end

function mp.set_property_number(name, val)
    state.props[name] = val
end

function mp.set_property_native(name, val)
    state.props[name] = val
end

function mp.osd_message(text, dur)
    table.insert(state.osd, {{ text = text, dur = dur }})
end

function mp.add_forced_key_binding(key, name, fn)
    state.bindings[name] = {{ key = key, fn = fn }}
    table.insert(state.binding_history, {{ op = "add", key = key, name = name }})
end

function mp.remove_key_binding(name)
    state.bindings[name] = nil
    table.insert(state.binding_history, {{ op = "remove", name = name }})
end

function mp.command(cmd)
    table.insert(state.commands, cmd)
end

function mp.add_timeout(sec, fn)
    local t = {{ sec = sec, fn = fn, killed = false }}
    function t:kill() self.killed = true end
    table.insert(state.timers, t)
    return t
end

function mp.command_native_async(tbl, cb)
    table.insert(state.async_calls, tbl)
    cb(true, {{ status = 0, stdout = mock_response, stderr = "" }}, nil)
end

package.preload["mp"] = function() return mp end
package.preload["mp.msg"] = function()
    return {{
        verbose = function(...) end,
        info = function(...) end,
        warn = function(...) end,
        debug = function(...) end,
    }}
end
package.preload["mp.options"] = function()
    return {{
        read_options = function(defaults, _ident)
            for k, v in pairs(script_opts) do
                defaults[k] = v
            end
        end
    }}
end
package.preload["mp.utils"] = function()
    return {{
        parse_json = function(_str)
            return mock_parsed
        end
    }}
end

dofile({json.dumps(LUA_SCRIPT)})

local function tick(pos)
    state.props["time-pos"] = pos
    if state.observers["time-pos"] then
        state.observers["time-pos"]("time-pos", pos)
    end
end

local function fire_file_loaded(dur)
    if dur then state.props.duration = dur end
    if state.events["file-loaded"] then
        state.events["file-loaded"]()
    end
end

local function press(name)
    assert(state.bindings[name], "Expected active binding: " .. name)
    state.bindings[name].fn()
end

local function active_binding_names()
    local names = {{}}
    for k, _ in pairs(state.bindings) do table.insert(names, k) end
    table.sort(names)
    return names
end

{actions_lua}

-- Serialize summary as JSON-ish key lines for Python assertions
local out = {{
    time_pos = state.props["time-pos"],
    chapters = #state.props["chapter-list"],
    osd_count = #state.osd,
    last_osd = #state.osd > 0 and state.osd[#state.osd].text or "",
    commands = state.commands,
    async_count = #state.async_calls,
    async_url = #state.async_calls > 0 and state.async_calls[1].args[#state.async_calls[1].args] or "",
    active_bindings = active_binding_names(),
    binding_history_count = #state.binding_history,
}}

local function enc(v)
    if type(v) == "number" then return tostring(v) end
    if type(v) == "boolean" then return tostring(v) end
    if type(v) == "string" then
        return '"' .. v:gsub('\\\\', '\\\\\\\\'):gsub('"', '\\\\"'):gsub('\\n', '\\\\n') .. '"'
    end
    if type(v) == "table" then
        local is_arr = (#v > 0) or (next(v) == nil)
        local parts = {{}}
        if is_arr then
            for i = 1, #v do table.insert(parts, enc(v[i])) end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            for k, val in pairs(v) do
                table.insert(parts, enc(tostring(k)) .. ":" .. enc(val))
            end
            return "{{" .. table.concat(parts, ",") .. "}}"
        end
    end
    return "null"
end

print(enc(out))
"""
    proc = subprocess.run(
        [LUA_BIN, "-e", harness],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise AssertionError(f"Lua failed ({proc.returncode}):\nSTDERR:\n{proc.stderr}\nSTDOUT:\n{proc.stdout}")
    return json.loads(proc.stdout.strip().splitlines()[-1])


@unittest.skipIf(LUA_BIN is None, "lua/luajit not installed")
class MpvAniSkipLuaTest(unittest.TestCase):
    def test_lua_file_exists_and_passes_syntax_check(self):
        self.assertTrue(os.path.isfile(LUA_SCRIPT), "scripts/mpv_aniskip.lua missing")
        if LUAC_BIN:
            proc = subprocess.run([LUAC_BIN, "-p", LUA_SCRIPT], capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_no_hardcoded_api_port_disables_cleanly_when_api_empty(self):
        res = _run_lua_scenario(
            {"api": "", "show_id": "abc", "ep": "1", "mode": "auto", "recap": False, "lang": "en"},
            json.dumps({"found": False, "intervals": []}),
            "fire_file_loaded(1440.0); tick(90.0)",
        )
        self.assertEqual(res["async_count"], 0)
        self.assertEqual(res["active_bindings"], [])

    def test_uses_custom_backend_url_from_script_opts(self):
        res = _run_lua_scenario(
            {"api": "http://127.0.0.1:6123", "show_id": "abc", "ep": "2", "mode": "auto", "recap": False, "lang": "en"},
            json.dumps({"found": False, "intervals": []}),
            """
            fire_file_loaded(1440.0)
            local args = state.async_calls[1].args
            local max_t = nil
            for i = 1, #args - 1 do
                if args[i] == "--max-time" then max_t = args[i + 1] end
            end
            assert(max_t == "10", "Expected curl --max-time 10, got: " .. tostring(max_t))
            """,
        )
        self.assertEqual(res["async_count"], 1)
        self.assertTrue(res["async_url"].startswith("http://127.0.0.1:6123/skip-times?"))

    def test_auto_skip_op_undo_and_no_reskip_loop_with_temporary_binding(self):
        payload = json.dumps({
            "found": True,
            "intervals": [
                {"skip_type": "op", "skip_id": "op-1", "start_time": 85.0, "end_time": 175.0},
            ],
        })
        # 1) Before OP: no forced bindings active.
        # 2) Enter OP at 86.0 -> auto-skips to 175.0, BS binding becomes active.
        # 3) Press Undo -> jumps back to 86.0, BS binding removed immediately.
        # 4) Advance inside OP (90.0, 120.0) -> NEVER re-skips!
        res = _run_lua_scenario(
            {"api": "http://127.0.0.1:5050", "show_id": "abc", "ep": "1", "mode": "auto", "recap": False, "lang": "es"},
            payload,
            """
            fire_file_loaded(1440.0)
            assert(#active_binding_names() == 0, "No forced bindings before OSD")
            tick(86.0)
            assert(math.abs(state.props["time-pos"] - 175.0) < 0.01, "Expected auto-skip to 175")
            assert(state.bindings["kisaru-skip-undo"] ~= nil, "BS undo binding should be active while toast visible")
            press("kisaru-skip-undo")
            assert(math.abs(state.props["time-pos"] - 86.0) < 0.01, "Expected undo back to 86")
            assert(state.bindings["kisaru-skip-undo"] == nil, "BS undo binding must be removed after press")
            tick(90.0)
            tick(120.0)
            assert(math.abs(state.props["time-pos"] - 120.0) < 0.01, "Must not re-skip after undo")
            """,
        )
        self.assertEqual(res["active_bindings"], [])
        self.assertGreaterEqual(res["chapters"], 2)

    def test_prompt_mode_binds_tab_and_esc_only_while_prompt_visible(self):
        payload = json.dumps({
            "found": True,
            "intervals": [
                {"skip_type": "op", "skip_id": "op-1", "start_time": 85.0, "end_time": 175.0},
            ],
        })
        res = _run_lua_scenario(
            {"api": "http://127.0.0.1:5050", "show_id": "abc", "ep": "1", "mode": "prompt", "recap": False, "lang": "en"},
            payload,
            """
            fire_file_loaded(1440.0)
            tick(86.0)
            assert(math.abs(state.props["time-pos"] - 86.0) < 0.01, "Prompt mode must not auto-skip")
            assert(state.bindings["kisaru-skip-now"] ~= nil, "TAB binding active during prompt")
            assert(state.bindings["kisaru-skip-dismiss"] ~= nil, "ESC binding active during prompt")
            press("kisaru-skip-now")
            assert(math.abs(state.props["time-pos"] - 175.0) < 0.01, "TAB must skip to endTime")
            assert(state.bindings["kisaru-skip-now"] == nil, "TAB removed after skip")
            assert(state.bindings["kisaru-skip-dismiss"] == nil, "ESC removed after skip")
            """,
        )
        self.assertAlmostEqual(res["time_pos"], 175.0)

    def test_prompt_timeout_removes_forced_bindings_and_does_not_rebind(self):
        payload = json.dumps({
            "found": True,
            "intervals": [
                {"skip_type": "op", "skip_id": "op-1", "start_time": 85.0, "end_time": 175.0},
            ],
        })
        res = _run_lua_scenario(
            {"api": "http://127.0.0.1:5050", "show_id": "abc", "ep": "1", "mode": "prompt", "recap": False, "lang": "en"},
            payload,
            """
            fire_file_loaded(1440.0)
            tick(86.0)
            assert(state.bindings["kisaru-skip-now"] ~= nil, "TAB active while prompt visible")
            assert(state.bindings["kisaru-skip-dismiss"] ~= nil, "ESC active while prompt visible")
            assert(#state.timers >= 1, "Prompt must schedule an expiration timer")
            state.timers[#state.timers].fn()
            assert(state.bindings["kisaru-skip-now"] == nil, "TAB must be removed when prompt OSD expires")
            assert(state.bindings["kisaru-skip-dismiss"] == nil, "ESC must be removed when prompt OSD expires")
            tick(92.0)
            assert(state.bindings["kisaru-skip-now"] == nil, "Must not re-bind TAB after prompt timeout")
            assert(state.bindings["kisaru-skip-dismiss"] == nil, "Must not re-bind ESC after prompt timeout")
            """,
        )
        self.assertEqual(res["active_bindings"], [])

    def test_near_eof_ed_skip_finishes_episode_cleanly(self):
        payload = json.dumps({
            "found": True,
            "intervals": [
                {"skip_type": "ed", "skip_id": "ed-eof", "start_time": 1350.0, "end_time": 1440.0},
            ],
        })
        res = _run_lua_scenario(
            {"api": "http://127.0.0.1:5050", "show_id": "abc", "ep": "1", "mode": "auto", "recap": False, "lang": "en"},
            payload,
            """
            fire_file_loaded(1440.0)
            tick(1351.0)
            """,
        )
        self.assertIn("quit 0", res["commands"])

    def test_ed_with_post_credits_seeks_instead_of_quitting(self):
        payload = json.dumps({
            "found": True,
            "intervals": [
                {"skip_type": "ed", "skip_id": "ed-pc", "start_time": 1260.0, "end_time": 1350.0},
            ],
        })
        res = _run_lua_scenario(
            {"api": "http://127.0.0.1:5050", "show_id": "abc", "ep": "1", "mode": "auto", "recap": False, "lang": "en"},
            payload,
            """
            fire_file_loaded(1440.0)
            tick(1261.0)
            """,
        )
        self.assertEqual(res["commands"], [])
        self.assertAlmostEqual(res["time_pos"], 1350.0)

    def test_mixed_op_never_auto_skipped_even_in_auto_mode(self):
        payload = json.dumps({
            "found": True,
            "intervals": [
                {"skip_type": "mixed-op", "skip_id": "mix-1", "start_time": 50.0, "end_time": 140.0},
            ],
        })
        res = _run_lua_scenario(
            {"api": "http://127.0.0.1:5050", "show_id": "abc", "ep": "1", "mode": "auto", "recap": False, "lang": "en"},
            payload,
            """
            fire_file_loaded(1440.0)
            tick(52.0)
            assert(math.abs(state.props["time-pos"] - 52.0) < 0.01, "mixed-op must not auto-skip")
            assert(state.bindings["kisaru-skip-now"] ~= nil, "mixed-op should show prompt binding")
            """,
        )
        self.assertAlmostEqual(res["time_pos"], 52.0)

    def test_recap_ignored_when_disabled_and_skipped_when_enabled(self):
        payload = json.dumps({
            "found": True,
            "intervals": [
                {"skip_type": "recap", "skip_id": "rec-1", "start_time": 10.0, "end_time": 70.0},
            ],
        })
        r_off = _run_lua_scenario(
            {"api": "http://127.0.0.1:5050", "show_id": "abc", "ep": "1", "mode": "auto", "recap": False, "lang": "en"},
            payload,
            "fire_file_loaded(1440.0); tick(12.0)",
        )
        self.assertAlmostEqual(r_off["time_pos"], 12.0)

        r_on = _run_lua_scenario(
            {"api": "http://127.0.0.1:5050", "show_id": "abc", "ep": "1", "mode": "auto", "recap": True, "lang": "en"},
            payload,
            "fire_file_loaded(1440.0); tick(12.0)",
        )
        self.assertAlmostEqual(r_on["time_pos"], 70.0)


@unittest.skipIf(MPV_BIN is None or NODE_BIN is None, "mpv or node not installed")
class RealHeadlessMpvIntegrationTest(unittest.TestCase):
    def test_real_headless_mpv_parses_opts_fetches_and_seeks(self):
        received = []

        class StubHandler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                parsed = urllib.parse.urlparse(self.path)
                qs = urllib.parse.parse_qs(parsed.query)
                received.append((parsed.path, qs))
                body = json.dumps({
                    "found": True,
                    "mal_id": 21,
                    "source": "stub",
                    "intervals": [
                        {"skip_type": "op", "skip_id": "op-live", "start_time": 1.0, "end_time": 6.0},
                    ],
                }).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, fmt, *args):
                pass

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), StubHandler)
        port = server.server_address[1]
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.shutdown)
        self.addCleanup(server.server_close)

        api_url = f"http://127.0.0.1:{port}"
        node_code = (
            "const m = require('./services/mpv_args.js');"
            "console.log(JSON.stringify(m.buildMpvArgs({"
            "  url: 'av://lavfi:testsrc=duration=8',"
            "  title: 'Test — Ep. 3',"
            f"  skipScriptPath: {json.dumps(LUA_SCRIPT)},"
            f"  apiUrl: {json.dumps(api_url)},"
            "  showId: 'test-show-42',"
            "  episode: '3',"
            "  showTitle: 'Solo Leveling, S=2',"
            "  skipMode: 'auto',"
            "  skipRecap: false,"
            "  lang: 'en',"
            "  showSkipDisabled: false"
            "})));"
        )
        built = json.loads(subprocess.check_output(
            [NODE_BIN, "-e", node_code], cwd=ROOT, text=True,
        ))
        # Extract the --script and --script-opts* flags produced by mpv_args.js
        skip_flags = [a for a in built if a.startswith("--script")]

        cmd = [
            MPV_BIN,
            "--no-config",
            "--vo=null",
            "--ao=null",
            "--msg-level=all=warn,mpv_aniskip=v",
            *skip_flags,
            "--",
            "av://lavfi:testsrc=duration=8",
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=20, check=False)
        output = proc.stdout + "\n" + proc.stderr

        self.assertEqual(proc.returncode, 0, output)
        self.assertIn(f"api={api_url}", output)
        self.assertIn("show_id=test-show-42", output)
        self.assertIn("ep=3", output)
        self.assertIn("mode=auto", output)
        self.assertGreaterEqual(len(received), 1, f"Expected /skip-times HTTP hit. Output:\n{output}")
        self.assertEqual(received[0][0], "/skip-times")
        self.assertEqual(received[0][1].get("id"), ["test-show-42"])
        self.assertEqual(received[0][1].get("ep"), ["3"])
        self.assertIn("seeking to 6.000", output)


if __name__ == "__main__":
    unittest.main()
