-- Merihari for Hammerspoon
-- Automatically toggles grayscale based on time window

-- ============================================================================
-- Runtime and config
-- ============================================================================

local config_file = os.getenv("HOME") .. "/.config/merihari/config"
_G.merihari_runtime = _G.merihari_runtime or {}
local runtime = _G.merihari_runtime

local debug_mode = false
local screen_resync_cooldown_sec = 20
local screen_resync_recent_window_sec = 300
local failure_reset_interval_sec = 1800
local failure_state = {
    on = { count = 0, last_failure_ts = nil },
    off = { count = 0, last_failure_ts = nil },
}
runtime.screen_resync_allowed = (runtime.screen_resync_allowed ~= false)
runtime.last_screen_resync_ts = runtime.last_screen_resync_ts or 0
runtime.last_toggle_ts = runtime.last_toggle_ts or 0
runtime.last_activation_ts = runtime.last_activation_ts or 0

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
            runtime.last_toggle_ts = os.time()
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
            runtime.last_toggle_ts = os.time()
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

local function resync_after_screen_change()
    if not runtime.screen_resync_allowed then
        debug_log("skip resync source=screenChanged reason=await_unlock")
        return
    end

    local now_ts = os.time()
    if (now_ts - runtime.last_screen_resync_ts) < screen_resync_cooldown_sec then
        debug_log("skip resync source=screenChanged reason=cooldown")
        return
    end

    local has_recent_toggle = (runtime.last_toggle_ts > 0) and ((now_ts - runtime.last_toggle_ts) <= screen_resync_recent_window_sec)
    local has_recent_activation = (runtime.last_activation_ts > 0) and ((now_ts - runtime.last_activation_ts) <= screen_resync_recent_window_sec)
    if not has_recent_toggle and not has_recent_activation then
        debug_log("skip resync source=screenChanged reason=no_recent_transition")
        return
    end

    runtime.last_screen_resync_ts = now_ts

    local start, end_time = read_config()
    local skip, reason, active = should_skip_for_inactive_session()
    if skip then
        debug_log("skip resync source=screenChanged reason=" .. tostring(reason) .. " active=" .. tostring(active))
        return
    end

    local should_be_on = should_be_grayscale(start, end_time)
    local is_on = is_grayscale_on()
    debug_log("screenChanged resync should_be_on=" .. tostring(should_be_on) .. " is_on=" .. tostring(is_on))

    -- Force a global re-apply across displays by toggling to opposite then back to desired.
    if should_be_on then
        if is_on then
            debug_log("screenChanged resync: ON->OFF->ON")
            toggle_grayscale()
            hs.timer.usleep(400000)
            toggle_grayscale()
        else
            debug_log("screenChanged resync: OFF->ON")
            toggle_grayscale()
        end
    else
        if not is_on then
            debug_log("screenChanged resync: OFF->ON->OFF")
            toggle_grayscale()
            hs.timer.usleep(400000)
            toggle_grayscale()
        else
            debug_log("screenChanged resync: ON->OFF")
            toggle_grayscale()
        end
    end

    -- Run normal state correction after resync.
    hs.timer.doAfter(1, function()
        apply_state("event:screenChanged")
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
        runtime.screen_resync_allowed = false
        runtime.last_activation_ts = os.time()
        queue_apply_state("systemDidWake")
    elseif event == hs.caffeinate.watcher.screensDidUnlock then
        runtime.screen_resync_allowed = true
        runtime.last_activation_ts = os.time()
        queue_apply_state("screensDidUnlock")
    elseif event == hs.caffeinate.watcher.sessionDidBecomeActive then
        runtime.screen_resync_allowed = true
        runtime.last_activation_ts = os.time()
        queue_apply_state("sessionDidBecomeActive")
    elseif event == hs.caffeinate.watcher.screensDidLock then
        runtime.screen_resync_allowed = false
    elseif event == hs.caffeinate.watcher.systemWillSleep then
        runtime.screen_resync_allowed = false
    elseif event == hs.caffeinate.watcher.sessionDidResignActive then
        runtime.screen_resync_allowed = false
    elseif event == hs.caffeinate.watcher.screensDidSleep then
        runtime.screen_resync_allowed = false
    end
end)
runtime.caffeinate_watcher:start()

if runtime.screen_watcher then
    runtime.screen_watcher:stop()
end
if runtime.screen_apply_timer then
    runtime.screen_apply_timer:stop()
end
runtime.screen_watcher = hs.screen.watcher.new(function()
    debug_log("queue resync source=screenChanged")
    if runtime.screen_apply_timer then
        runtime.screen_apply_timer:stop()
    end
    runtime.screen_apply_timer = hs.timer.doAfter(2, resync_after_screen_change)
end)
runtime.screen_watcher:start()

apply_state("startup")
print("Merihari loaded")
