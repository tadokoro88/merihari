-- Merihari for Hammerspoon
-- Automatically toggles grayscale based on time window

-- ============================================================================
-- Runtime and config
-- ============================================================================

local config_file = os.getenv("HOME") .. "/.config/merihari/config"
_G.merihari_runtime = _G.merihari_runtime or {}
local runtime = _G.merihari_runtime

local debug_mode = false
local failure_reset_interval_sec = 1800
local failure_state = {
    on = { count = 0, last_failure_ts = nil },
    off = { count = 0, last_failure_ts = nil },
}

local function read_config()
    local file = io.open(config_file, "r")
    if not file then
        debug_mode = false
        return "2100", "0600", false
    end

    local start, end_time, debug = "2100", "0600", "0"
    for line in file:lines() do
        local s = line:match("START=(%d+)")
        local e = line:match("END=(%d+)")
        local d = line:match("DEBUG=(%d+)")
        if s then start = s end
        if e then end_time = e end
        if d then debug = d end
    end
    file:close()

    debug_mode = (debug == "1")
    return start, end_time, debug_mode
end

-- ============================================================================
-- Logging and counters
-- ============================================================================

local function debug_log(message)
    if debug_mode then
        print("Merihari [debug]: " .. message)
    end
end

local function reset_failure_count(mode)
    failure_state[mode].count = 0
    failure_state[mode].last_failure_ts = nil
end

local function log_every_five_failures(mode)
    local now_ts = os.time()
    local state = failure_state[mode]

    if state.last_failure_ts and (now_ts - state.last_failure_ts) > failure_reset_interval_sec then
        debug_log(mode .. " failure count reset (gap > " .. tostring(failure_reset_interval_sec) .. "s)")
        state.count = 0
    end

    state.count = state.count + 1
    state.last_failure_ts = now_ts
    debug_log(mode .. " failure count=" .. tostring(state.count))

    if state.count >= 5 then
        if mode == "on" then
            print("Merihari: failed to turn ON (session may be locked/asleep, or accessibility/shortcut settings may be unavailable)")
        else
            print("Merihari: failed to turn OFF (session may be locked/asleep, or accessibility/shortcut settings may be unavailable)")
        end
        state.count = 0
        state.last_failure_ts = nil
    end
end

-- ============================================================================
-- State probes
-- ============================================================================

local function should_be_grayscale(start, end_time)
    local now = tonumber(os.date("%H%M"))
    local start_num = tonumber(start)
    local end_num = tonumber(end_time)

    if start_num < end_num then
        return now >= start_num and now < end_num
    end
    return now >= start_num or now < end_num
end

local function is_grayscale_on()
    local result = hs.execute("defaults read com.apple.universalaccess grayscale 2>/dev/null || echo 0")
    return result:match("1") ~= nil
end

local function session_looks_active()
    local ok, props = pcall(hs.caffeinate.sessionProperties)
    if not ok or type(props) ~= "table" then
        return nil
    end
    if props.CGSSessionScreenIsLocked == 1 then
        return false
    end
    if props.kCGSSessionOnConsoleKey == 0 then
        return false
    end
    return true
end

local function should_skip_for_inactive_session()
    local active = session_looks_active()
    if active ~= true then
        return true, "session_inactive", active
    end
    return false, nil, active
end

-- ============================================================================
-- Actions
-- ============================================================================

local function toggle_grayscale()
    hs.osascript.applescript([[
        tell application "System Events"
            key code 96 using {command down, option down}
        end tell
    ]])
end

local function send_in_window_notification()
    hs.notify.new({
        title = "Merihari",
        informativeText = "メリハリつけていきましょう",
        soundName = "default",
        withdrawAfter = 0
    }):send()
end

local function flush_notifications()
    hs.notify.withdrawAll()
end

-- ============================================================================
-- Controller
-- ============================================================================

local function apply_state(source)
    local start, end_time = read_config()
    local skip, reason, active = should_skip_for_inactive_session()
    if skip then
        debug_log("skip apply_state source=" .. tostring(source) .. " reason=" .. tostring(reason) .. " active=" .. tostring(active))
        return
    end

    local should_be_on = should_be_grayscale(start, end_time)
    local is_on = is_grayscale_on()
    debug_log("apply_state source=" .. tostring(source) .. " should_be_on=" .. tostring(should_be_on) .. " is_on=" .. tostring(is_on))

    if should_be_on and not is_on then
        debug_log("attempt turn ON")
        toggle_grayscale()
        hs.timer.usleep(300000)
        if is_grayscale_on() then
            reset_failure_count("on")
            print("Merihari: turned ON")
        else
            log_every_five_failures("on")
        end
    elseif not should_be_on and is_on then
        debug_log("attempt turn OFF")
        toggle_grayscale()
        hs.timer.usleep(300000)
        if not is_grayscale_on() then
            reset_failure_count("off")
            print("Merihari: turned OFF")
        else
            log_every_five_failures("off")
        end
    end

    if should_be_on then
        send_in_window_notification()
    end
end

local function queue_apply_state(source)
    debug_log("queue apply_state source=" .. tostring(source))
    flush_notifications()
    if runtime.wake_apply_timer then
        runtime.wake_apply_timer:stop()
    end
    runtime.wake_apply_timer = hs.timer.doAfter(1, function()
        apply_state("event:" .. tostring(source))
    end)
end

-- ============================================================================
-- Runtime wiring
-- ============================================================================

if runtime.apply_state_timer then
    runtime.apply_state_timer:stop()
end
runtime.apply_state_timer = hs.timer.doEvery(60, function()
    apply_state("timer")
end)

if runtime.caffeinate_watcher then
    runtime.caffeinate_watcher:stop()
end
runtime.caffeinate_watcher = hs.caffeinate.watcher.new(function(event)
    if event == hs.caffeinate.watcher.systemDidWake then
        queue_apply_state("systemDidWake")
    elseif event == hs.caffeinate.watcher.screensDidUnlock then
        queue_apply_state("screensDidUnlock")
    elseif event == hs.caffeinate.watcher.sessionDidBecomeActive then
        queue_apply_state("sessionDidBecomeActive")
    end
end)
runtime.caffeinate_watcher:start()

apply_state("startup")
print("Merihari loaded")
