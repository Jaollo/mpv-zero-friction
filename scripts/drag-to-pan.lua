do -- Ch 16.4: Closure-based privacy — all state invisible to other scripts

local mp = require 'mp'

-- Ch 4.2: Local-cache mpv API functions for hot-path performance
local get_mouse_pos = mp.get_mouse_pos
local get_osd_size  = mp.get_osd_size
local get_prop      = mp.get_property_number
local set_prop      = mp.set_property_number

-- Ch 18 + 4.2: Idiomatic clamp with cached math stdlib
local min, max = math.min, math.max
local function clamp(v, lo, hi) return min(max(v, lo), hi) end

-- Ch 13.4.3: Metatable defaults — uninitialized fields return 0 instead of nil
local drag_defaults = { __index = function() return 0 end }
local drag = setmetatable({
    active = false,
    moved = false,
    cleanup = nil,
    last_x = nil,
    last_y = nil,
    pan_x = 0,
    pan_y = 0,
}, drag_defaults)

local function force_drag_termination()
    if drag.active then
        if drag.cleanup then
            drag.cleanup()
            drag.cleanup = nil
        end
        drag.active = false
        drag.moved = false
    end
end

local function drag_to_pan_handler(table)
    if table.event == "up" then
        force_drag_termination()
        return
    end

    if table.event == "down" then
        -- Ensure any ghost state is annihilated before starting a new drag
        force_drag_termination()

        local zoom = get_prop("video-zoom", 0)
        if zoom <= 0 then return end

        drag.active = true
        drag.moved = false
        -- Mouse pos may be nil at startup; idle loop will pick up the first valid position
        local initial_x, initial_y = get_mouse_pos()
        drag.last_x = initial_x
        drag.last_y = initial_y

        -- Cache initial pan values with safe defaults
        drag.pan_x = get_prop("video-pan-x", 0)
        drag.pan_y = get_prop("video-pan-y", 0)

        -- Ch 8.4: pcall-wrapped idle callback — errors self-heal via force_drag_termination
        local idle = function()
            local ok, err = pcall(function()
                if drag.active and drag.moved then
                    local current_x, current_y = get_mouse_pos()
                    local osd_w, osd_h = get_osd_size()

                    -- Defensive check: If mouse lost or window sized to 0, skip this tick
                    if not current_x or not osd_w or osd_w <= 0 or osd_h <= 0 then
                        return
                    end

                    -- Late anchor: if initial mouse pos was nil, adopt first valid pos
                    if not drag.last_x then
                        drag.last_x, drag.last_y = current_x, current_y
                        drag.moved = false
                        return
                    end

                    local dx = current_x - drag.last_x
                    local dy = current_y - drag.last_y

                    -- Optimization: Only proceed if there is actual motion
                    if dx ~= 0 or dy ~= 0 then
                        drag.last_x, drag.last_y = current_x, current_y

                        -- Re-query zoom inside the loop in case it changed (e.g., via script)
                        local current_zoom = get_prop("video-zoom", 0)
                        if current_zoom <= 0 then
                            force_drag_termination()
                            return
                        end

                        local actual_zoom = 2 ^ current_zoom

                        -- Delta calculation relative to current OSD size (handles resizes mid-drag)
                        local new_pan_x = clamp(drag.pan_x + (dx / osd_w) / actual_zoom, -3, 3)
                        local new_pan_y = clamp(drag.pan_y + (dy / osd_h) / actual_zoom, -3, 3)

                        if new_pan_x ~= drag.pan_x then
                            set_prop("video-pan-x", new_pan_x)
                            drag.pan_x = new_pan_x
                        end
                        if new_pan_y ~= drag.pan_y then
                            set_prop("video-pan-y", new_pan_y)
                            drag.pan_y = new_pan_y
                        end
                    end
                    drag.moved = false
                end
            end)
            if not ok then
                mp.msg.warn("drag-to-pan idle error: " .. tostring(err))
                force_drag_termination()
            end
        end

        mp.register_idle(idle)
        mp.add_forced_key_binding("mouse_move", "drag_mouse_move", function() drag.moved = true end)
        mp.add_forced_key_binding("mbtn_left_up", "drag_mouse_up", function()
            force_drag_termination()
        end)

        drag.cleanup = function()
            mp.remove_key_binding("drag_mouse_move")
            mp.remove_key_binding("drag_mouse_up")
            mp.unregister_idle(idle)
        end
    end
end

-- Fail-safe Kill Switches
mp.add_key_binding("mouse_leave", "drag-cancel-leave", force_drag_termination)

-- Robust complex binding for native button tracking
mp.add_key_binding(nil, "drag-to-pan", drag_to_pan_handler, {complex=true})

-- Support for external triggers
mp.register_script_message("drag-to-pan-event", function(event)
    if event == "up" or event == "cancel" then
        force_drag_termination()
    else
        drag_to_pan_handler({event = "down"})
    end
end)

-- Zoom Reset Observer: ensures the drag machine dies when zoom does
mp.observe_property("video-zoom", "number", function(_, zoom)
    if zoom and zoom <= 0 then
        force_drag_termination()
    end
end)

end -- do block
