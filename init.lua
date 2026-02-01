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

-- Track if screen is locked/asleep
local screen_is_locked = false

-- Apply correct state
local function apply_state()
    -- Skip everything if screen is locked or asleep
    if screen_is_locked then
        return
    end
    
    local should_be_on = should_be_grayscale()
    local is_on = is_grayscale_on()
    
    if should_be_on and not is_on then
        toggle_grayscale()
        print("Merihari: turned ON")
    elseif not should_be_on and is_on then
        toggle_grayscale()
        print("Merihari: turned OFF")
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

-- Apply on wake from sleep
hs.caffeinate.watcher.new(function(event)
    if event == hs.caffeinate.watcher.systemDidWake then
        screen_is_locked = false
        hs.timer.doAfter(1, apply_state)
    elseif event == hs.caffeinate.watcher.screensDidUnlock then
        screen_is_locked = false
        hs.timer.doAfter(1, apply_state)
    elseif event == hs.caffeinate.watcher.screensDidLock or 
           event == hs.caffeinate.watcher.systemWillSleep then
        screen_is_locked = true
    end
end):start()

print("Merihari loaded")
