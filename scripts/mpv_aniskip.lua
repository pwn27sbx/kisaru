-- Clean-room mpv skip-intro / outro actor for Kisaru.
--
-- Configured exclusively via --script-opts=kisaru_skip-<key>=<val>:
--   api     : full backend base URL (e.g. from Anime.apiUrl; never hardcoded)
--   show_id : Kisaru show id
--   ep      : episode number
--   title   : URL-encoded show title (optional, used for JKAnime fallback)
--   mode    : "auto" | "prompt" | "off"
--   recap   : true | false (skip recap segments)
--   lang    : "es" | "en"
--
-- Forced keybindings (TAB/ESC for prompt, BS for undo) are registered ONLY
-- while the corresponding OSD message is visible, and removed immediately on
-- press, timeout, or leaving the interval so mpv's defaults (e.g. BS=reset
-- speed, ESC=leave fullscreen) remain intact during normal playback.

local mp = require("mp")
local options = require("mp.options")
local utils = require("mp.utils")

local opts = {
    api = "",
    show_id = "",
    ep = "",
    title = "",
    mode = "auto",
    recap = false,
    lang = "en",
}

options.read_options(opts, "kisaru_skip")

local EOF_MARGIN_SEC = 2.0
local PRE_TRIGGER_SEC = 0.5
local END_MARGIN_SEC = 1.0
local UNDO_WINDOW_SEC = 5.0
local PROMPT_WINDOW_SEC = 4.0

local STRINGS = {
    en = {
        op = "Opening",
        ed = "Ending",
        recap = "Recap",
        ["mixed-op"] = "Mixed Opening",
        ["mixed-ed"] = "Mixed Ending",
        skipped = "Skipped %s · [Backspace] Undo",
        undone = "Restored %s",
        prompt = "Skip %s · [Tab] Skip · [Esc] Hide",
        prompt_eof = "Finish episode (%s) · [Tab] Finish · [Esc] Hide",
        ch_intro = "Intro",
        ch_episode = "Episode",
        ch_post = "Post-credits",
    },
    es = {
        op = "Opening",
        ed = "Ending",
        recap = "Resumen",
        ["mixed-op"] = "Opening mixto",
        ["mixed-ed"] = "Ending mixto",
        skipped = "%s saltado · [Backspace] Deshacer",
        undone = "%s restaurado",
        prompt = "Saltar %s · [Tab] Saltar · [Esc] Ocultar",
        prompt_eof = "Terminar episodio (%s) · [Tab] Terminar · [Esc] Ocultar",
        ch_intro = "Intro",
        ch_episode = "Episodio",
        ch_post = "Post-créditos",
    },
}

local function tr(key)
    local lang = (opts.lang == "es") and "es" or "en"
    return (STRINGS[lang] and STRINGS[lang][key]) or STRINGS.en[key] or key
end

local function url_encode(str)
    return (tostring(str or ""):gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local intervals = {}
local interval_state = {} -- skip_id -> "pending" | "skipped" | "undone" | "dismissed"
local fetched = false
local active_prompt_id = nil
local prompt_timer = nil
local undo_ctx = nil
local undo_timer = nil

local function clear_prompt()
    if prompt_timer ~= nil then
        prompt_timer:kill()
        prompt_timer = nil
    end
    if active_prompt_id ~= nil then
        mp.remove_key_binding("kisaru-skip-now")
        mp.remove_key_binding("kisaru-skip-dismiss")
        active_prompt_id = nil
    end
end

local function clear_undo()
    if undo_timer ~= nil then
        undo_timer:kill()
        undo_timer = nil
    end
    if undo_ctx ~= nil then
        mp.remove_key_binding("kisaru-skip-undo")
        undo_ctx = nil
    end
end

local function is_near_eof(iv, duration)
    return iv.skip_type == "ed" and duration and duration > 0 and (duration - iv.end_time) < EOF_MARGIN_SEC
end

local function is_enabled_type(skip_type)
    if skip_type == "recap" then
        return opts.recap == true or opts.recap == "yes" or opts.recap == "1"
    end
    return skip_type == "op" or skip_type == "ed" or skip_type == "mixed-op" or skip_type == "mixed-ed"
end

local function should_auto_skip(skip_type)
    if opts.mode ~= "auto" then
        return false
    end
    -- mixed-op / mixed-ed contain plot content: prompt-only by default.
    if skip_type == "mixed-op" or skip_type == "mixed-ed" then
        return false
    end
    return true
end

local function perform_skip(iv, pre_pos, duration)
    clear_prompt()
    interval_state[iv.skip_id] = "skipped"

    -- Near-EOF ending: finish the episode cleanly so mpv exits with code 0
    -- and Kisaru leaves the episode marked watched.
    if is_near_eof(iv, duration) then
        clear_undo()
        mp.command("quit 0")
        return
    end

    mp.set_property_number("time-pos", iv.end_time)
    clear_undo()

    local label = tr(iv.skip_type)
    undo_ctx = {
        skip_id = iv.skip_id,
        pre_pos = pre_pos,
        label = label,
    }

    mp.add_forced_key_binding("BS", "kisaru-skip-undo", function()
        local ctx = undo_ctx
        clear_undo()
        if ctx then
            interval_state[ctx.skip_id] = "undone"
            mp.set_property_number("time-pos", ctx.pre_pos)
            mp.osd_message(string.format(tr("undone"), ctx.label), 2.5)
        end
    end)

    mp.osd_message(string.format(tr("skipped"), label), UNDO_WINDOW_SEC)
    undo_timer = mp.add_timeout(UNDO_WINDOW_SEC, function()
        clear_undo()
    end)
end

local function show_prompt(iv, pos, duration)
    if active_prompt_id == iv.skip_id then
        return
    end
    clear_prompt()
    active_prompt_id = iv.skip_id

    local label = tr(iv.skip_type)
    local msg_key = is_near_eof(iv, duration) and "prompt_eof" or "prompt"

    mp.add_forced_key_binding("TAB", "kisaru-skip-now", function()
        local cur = mp.get_property_number("time-pos", pos) or pos
        local dur = mp.get_property_number("duration", duration) or duration
        perform_skip(iv, cur, dur)
    end)

    mp.add_forced_key_binding("ESC", "kisaru-skip-dismiss", function()
        interval_state[iv.skip_id] = "dismissed"
        clear_prompt()
        mp.osd_message("", 0.1)
    end)

    mp.osd_message(string.format(tr(msg_key), label), PROMPT_WINDOW_SEC)
    prompt_timer = mp.add_timeout(PROMPT_WINDOW_SEC, function()
        interval_state[iv.skip_id] = "dismissed"
        clear_prompt()
    end)
end

local function inject_chapters(list, duration)
    local existing = mp.get_property_native("chapter-list", {})
    if type(existing) == "table" and #existing > 0 then
        return
    end
    local chapters = {}
    local function add_ch(title, t)
        if t < 0 then t = 0 end
        if duration and duration > 0 and t >= duration then return end
        if #chapters > 0 and math.abs(chapters[#chapters].time - t) < 1.0 then
            chapters[#chapters].title = title
            return
        end
        table.insert(chapters, { title = title, time = t })
    end

    if #list > 0 and list[1].start_time > 5.0 then
        add_ch(tr("ch_intro"), 0)
    end
    for _, iv in ipairs(list) do
        add_ch(tr(iv.skip_type), iv.start_time)
        if not is_near_eof(iv, duration) then
            local after = (iv.skip_type == "ed" or iv.skip_type == "mixed-ed")
                and tr("ch_post") or tr("ch_episode")
            add_ch(after, iv.end_time)
        end
    end
    if #chapters > 0 then
        mp.set_property_native("chapter-list", chapters)
    end
end

local function on_time_pos(_name, pos)
    if type(pos) ~= "number" or #intervals == 0 then
        return
    end
    local duration = mp.get_property_number("duration", 0) or 0
    local active_iv = nil

    for _, iv in ipairs(intervals) do
        local st = interval_state[iv.skip_id] or "pending"
        if st == "pending" and is_enabled_type(iv.skip_type) then
            if pos >= (iv.start_time - PRE_TRIGGER_SEC) and pos < (iv.end_time - END_MARGIN_SEC) then
                active_iv = iv
                break
            end
        end
    end

    if not active_iv then
        clear_prompt()
        return
    end

    if should_auto_skip(active_iv.skip_type) then
        perform_skip(active_iv, pos, duration)
    else
        show_prompt(active_iv, pos, duration)
    end
end

local function fetch_skip_times()
    if fetched then
        return
    end
    if opts.mode == "off" or opts.api == "" or opts.show_id == "" or opts.ep == "" then
        return
    end
    fetched = true

    local duration = mp.get_property_number("duration", 0) or 0
    local base = opts.api:gsub("/+$", "")
    local url = string.format(
        "%s/skip-times?id=%s&ep=%s&duration=%.3f",
        base,
        url_encode(opts.show_id),
        url_encode(opts.ep),
        duration
    )
    if opts.title ~= "" then
        -- Title is already percent-encoded by mpv_args.js; pass through cleanly.
        url = url .. "&title=" .. opts.title
    end

    mp.command_native_async({
        name = "subprocess",
        playback_only = true,
        capture_stdout = true,
        capture_stderr = true,
        -- Backend enforces an 8s total budget; 10s gives clean headroom.
        args = { "curl", "-fsS", "--max-time", "10", url },
    }, function(success, result)
        if not success or not result or result.status ~= 0 or not result.stdout then
            return
        end
        local data = utils.parse_json(result.stdout)
        if type(data) ~= "table" or not data.found or type(data.intervals) ~= "table" then
            return
        end
        local cur_dur = mp.get_property_number("duration", duration) or duration
        local valid = {}
        for _, iv in ipairs(data.intervals) do
            if type(iv) == "table"
                and type(iv.start_time) == "number"
                and type(iv.end_time) == "number"
                and iv.end_time > iv.start_time
                and iv.skip_type
            then
                local sid = iv.skip_id or string.format("%s:%.1f:%.1f", iv.skip_type, iv.start_time, iv.end_time)
                table.insert(valid, {
                    skip_id = sid,
                    skip_type = iv.skip_type,
                    start_time = iv.start_time,
                    end_time = iv.end_time,
                })
                interval_state[sid] = "pending"
            end
        end
        intervals = valid
        if #intervals > 0 then
            inject_chapters(intervals, cur_dur)
        end
    end)
end

mp.register_event("file-loaded", fetch_skip_times)
mp.observe_property("time-pos", "number", on_time_pos)
