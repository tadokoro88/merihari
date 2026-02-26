-- Merihari for Hammerspoon
-- Automatically toggles grayscale based on time window

local config_file = os.getenv("HOME") .. "/.config/merihari/config"
local debug_mode = false
local consecutive_failures = {
    on = 0,
    off = 0,
}

local function debug_log(message)
    if debug_mode then
        print("Merihari [debug]: " .. message)
    end
end

local function reset_failure_count(mode)
    consecutive_failures[mode] = 0
end

local function log_every_five_failures(mode)
    consecutive_failures[mode] = consecutive_failures[mode] + 1
    debug_log(mode .. " failure count=" .. tostring(consecutive_failures[mode]))
    if consecutive_failures[mode] >= 5 then
        if mode == "on" then
            print("Merihari: failed to turn ON (session may be locked/asleep, or accessibility/shortcut settings may be unavailable)")
        else
            print("Merihari: failed to turn OFF (session may be locked/asleep, or accessibility/shortcut settings may be unavailable)")
        end
        consecutive_failures[mode] = 0
    end
end

-- Read config
local function read_config()
    local file = io.open(config_file, "r")
    if not file then
        debug_mode = false
        return "2100", "0600", false  -- defaults
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

-- Check if current time is in window
local function should_be_grayscale(start, end_time)
    local now = os.date("%H%M")
    
    start = tonumber(start)
    end_time = tonumber(end_time)
    now = tonumber(now)
    
    if start < end_time then
        -- Same day window (e.g., 0900-1800)
        return now >= start and now < end_time
    else
        -- Overnight window (e.g., 2100-0600)
        return now >= start or now < end_time
    end
end

-- Get current grayscale state
local function is_grayscale_on()
    local result = hs.execute("defaults read com.apple.universalaccess grayscale 2>/dev/null || echo 0")
    return result:match("1") ~= nil
end

-- Toggle grayscale
local function toggle_grayscale()
    hs.osascript.applescript([[
        tell application "System Events"
            key code 96 using {command down, option down}
        end tell
    ]])
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
    -- Treat unknown session state as inactive to avoid toggling/notify while unavailable.
    if active ~= true then
        return true, "session_inactive", active
    end

    return false, nil, active
end

-- Apply correct state
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
    
    -- Show notification every minute while in time window
    if should_be_on then
        hs.notify.new({
            title="Merihari",
            informativeText="メリハリつけていきましょう",
            soundName="default",
            withdrawAfter=0
        }):send()
    end
end

-- Check every 60 seconds
local apply_state_timer = hs.timer.doEvery(60, function()
    apply_state("timer")
end)

-- Apply immediately on load
apply_state("startup")

-- Coalesce wake/unlock events into one delayed apply_state run.
local wake_apply_timer = nil
local function queue_apply_state(source)
    debug_log("queue apply_state source=" .. tostring(source))
    hs.notify.withdrawAll()
    if wake_apply_timer then
        wake_apply_timer:stop()
    end
    wake_apply_timer = hs.timer.doAfter(1, function()
        apply_state("event:" .. tostring(source))
    end)
end

-- Apply on key session-activation events.
local caffeinate_watcher = hs.caffeinate.watcher.new(function(event)
    if event == hs.caffeinate.watcher.systemDidWake then
        queue_apply_state("systemDidWake")
    elseif event == hs.caffeinate.watcher.screensDidUnlock then
        queue_apply_state("screensDidUnlock")
    elseif event == hs.caffeinate.watcher.sessionDidBecomeActive then
        queue_apply_state("sessionDidBecomeActive")
    end
end)
caffeinate_watcher:start()

print("Merihari loaded")
