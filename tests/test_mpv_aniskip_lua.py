"""Tests for scripts/mpv_aniskip.lua — mpv Lua skip actor (WU-3).

Runs syntax validation (`luac -p`) and executes the real Lua script under
`luajit`/`lua` with an in-memory mock of mpv's `mp`, `mp.options`, and
`mp.utils` modules. Zero real mpv windows, zero network calls.

Run: python3 -m unittest tests/test_mpv_aniskip_lua.py
"""

import json
import os
import shutil
import subprocess
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LUA_SCRIPT = os.path.join(ROOT, "scripts", "mpv_aniskip.lua")
LUA_BIN = shutil.which("luajit") or shutil.which("lua")
LUAC_BIN = shutil.which("luac")


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
            "fire_file_loaded(1440.0)",
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


if __name__ == "__main__":
    unittest.main()
