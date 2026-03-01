do -- Ch 16.4: Closure-based privacy

local mp = require 'mp'

-- Ch 4.2: Cache monotonic clock for hot-path
local clock = mp.get_time
local last_down = 0
local THRESHOLD = 0.3 -- 300ms double-click window
local pause_timer = nil

local function handler(t)
    if t.event == "down" then
        -- Cancel any active drag
        mp.commandv("script-message", "drag-to-pan-event", "cancel")

        local now = clock()
        if now - last_down < THRESHOLD then
            -- Double click — quit
            if pause_timer then pause_timer:kill() end
            pause_timer = nil
            mp.command("quit")
            last_down = 0
        else
            -- First click — wait to see if a second comes, then pause
            last_down = now
            if pause_timer then pause_timer:kill() end
            pause_timer = mp.add_timeout(THRESHOLD, function()
                mp.commandv("cycle", "pause")
                pause_timer = nil
            end)
        end
    end
end

mp.add_key_binding(nil, "double-right-quit", handler, {complex = true})

end
