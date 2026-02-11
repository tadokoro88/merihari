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

-- Track session activity as a fallback for lock detection.
local session_is_active = true

-- Detect whether current GUI session is locked/inactive.
local function is_session_locked()
    local ok, props = pcall(hs.caffeinate.sessionProperties)
    if ok and type(props) == "table" then
        if props.CGSSessionScreenIsLocked == 1 then
            return true
        end
        if props.kCGSSessionOnConsoleKey == 0 then
            return true
        end
    end
    return not session_is_active
end

-- Apply correct state
local function apply_state()
    if is_session_locked() then
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

-- Apply on wake from sleep
hs.caffeinate.watcher.new(function(event)
    if event == hs.caffeinate.watcher.systemDidWake then
        session_is_active = true
        hs.timer.doAfter(1, apply_state)
    elseif event == hs.caffeinate.watcher.screensDidUnlock then
        session_is_active = true
        hs.timer.doAfter(1, apply_state)
    elseif event == hs.caffeinate.watcher.sessionDidBecomeActive then
        session_is_active = true
        hs.timer.doAfter(1, apply_state)
    elseif event == hs.caffeinate.watcher.screensDidLock then
        session_is_active = false
    elseif event == hs.caffeinate.watcher.systemWillSleep then
        session_is_active = false
    elseif event == hs.caffeinate.watcher.sessionDidResignActive then
        session_is_active = false
    elseif event == hs.caffeinate.watcher.screensDidSleep then
        session_is_active = false
    elseif event == hs.caffeinate.watcher.screensDidWake then
        session_is_active = true
        hs.timer.doAfter(1, apply_state)
    end
end):start()

print("Merihari loaded")
