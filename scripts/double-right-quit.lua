do -- Ch 16.4: Closure-based privacy

local mp = require 'mp'

-- Ch 4.2: Cache monotonic clock for hot-path
local clock = mp.get_time
local last_down = 0
local THRESHOLD = 0.3 -- 300ms double-click window

local function handler(table)
    if table.event == "down" then
        -- Cancel any active drag (replaces drag-to-pan.lua's own MBTN_RIGHT binding)
        mp.commandv("script-message", "drag-to-pan-event", "cancel")

        local now = clock()
        if now - last_down < THRESHOLD then
            mp.command("quit")
            last_down = 0
        else
            last_down = now
        end
    end
end

mp.add_key_binding(nil, "double-right-quit", handler, {complex = true})

end
