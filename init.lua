-- Merihari for Hammerspoon
-- Automatically toggles grayscale based on time window

local config_file = os.getenv("HOME") .. "/.config/merihari/config"

-- Read config
local function read_config()
    local file = io.open(config_file, "r")
    if not file then
        return "2100", "0600"  -- defaults
    end
    
    local start, end_time = "2100", "0600"
    for line in file:lines() do
        local s = line:match("START=(%d+)")
        local e = line:match("END=(%d+)")
        if s then start = s end
        if e then end_time = e end
    end
    file:close()
    return start, end_time
end

-- Check if current time is in window
local function should_be_grayscale()
    local start, end_time = read_config()
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
        return true
    end

    -- Also skip when display is idle (e.g., dark/background wake before user interaction).
    local ok, display_idle = pcall(hs.caffeinate.get, "displayIdle")
    if ok and display_idle == true then
        return true
    end

    return false
end

-- Apply correct state
local function apply_state()
    if should_skip_for_inactive_session() then
        return
    end

    local should_be_on = should_be_grayscale()
    local is_on = is_grayscale_on()
    
    if should_be_on and not is_on then
        toggle_grayscale()
        hs.timer.usleep(300000)
        if is_grayscale_on() then
            print("Merihari: turned ON")
        else
            print("Merihari: failed to turn ON (check accessibility permission and color filter shortcut settings)")
        end
    elseif not should_be_on and is_on then
        toggle_grayscale()
        hs.timer.usleep(300000)
        if not is_grayscale_on() then
            print("Merihari: turned OFF")
        else
            print("Merihari: failed to turn OFF (check accessibility permission and color filter shortcut settings)")
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
hs.timer.doEvery(60, apply_state)

-- Apply immediately on load
apply_state()

-- Coalesce wake/unlock events into one delayed apply_state run.
local wake_apply_timer = nil
local function queue_apply_state()
    hs.notify.withdrawAll()
    if wake_apply_timer then
        wake_apply_timer:stop()
    end
    wake_apply_timer = hs.timer.doAfter(1, apply_state)
end

-- Apply on key session-activation events.
hs.caffeinate.watcher.new(function(event)
    if event == hs.caffeinate.watcher.systemDidWake then
        queue_apply_state()
    elseif event == hs.caffeinate.watcher.screensDidUnlock then
        queue_apply_state()
    elseif event == hs.caffeinate.watcher.sessionDidBecomeActive then
        queue_apply_state()
    end
end):start()

print("Merihari loaded")
