local mp = require 'mp'

-- Persistent state encapsulated in a local table
local drag = {
    active = false,
    moved = false,
    cleanup = nil,
    last_x = 0,
    last_y = 0,
    pan_x = 0,
    pan_y = 0
}

local function clamp(value, low, high)
    if value <= low then return low
    elseif value >= high then return high
    end
    return value
end

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
        
        local initial_x, initial_y = mp.get_mouse_pos()
        if initial_x == nil or initial_y == nil then return end

        local zoom = mp.get_property_number("video-zoom", 0)
        if zoom <= 0 then return end

        drag.active = true
        drag.moved = false
        drag.last_x, drag.last_y = initial_x, initial_y
        
        -- Cache initial pan values with safe defaults
        drag.pan_x = mp.get_property_number("video-pan-x", 0)
        drag.pan_y = mp.get_property_number("video-pan-y", 0)

        local idle = function()
            if drag.active and drag.moved then
                local current_x, current_y = mp.get_mouse_pos()
                local osd_w, osd_h = mp.get_osd_size()
                
                -- Defensive check: If mouse lost or window sized to 0, abort
                if not current_x or not osd_w or osd_w <= 0 or osd_h <= 0 then
                    force_drag_termination()
                    return
                end

                local dx = current_x - drag.last_x
                local dy = current_y - drag.last_y
                
                -- Optimization: Only proceed if there is actual motion
                if dx ~= 0 or dy ~= 0 then
                    drag.last_x, drag.last_y = current_x, current_y
                    
                    -- Re-query zoom inside the loop in case it changed (e.g., via script)
                    local current_zoom = mp.get_property_number("video-zoom", 0)
                    if current_zoom <= 0 then
                        force_drag_termination()
                        return
                    end

                    local actual_zoom = 2 ^ current_zoom
                    
                    -- Delta calculation relative to current OSD size (handles resizes mid-drag)
                    local new_pan_x = clamp(drag.pan_x + (dx / osd_w) / actual_zoom, -3, 3)
                    local new_pan_y = clamp(drag.pan_y + (dy / osd_h) / actual_zoom, -3, 3)
                    
                    if new_pan_x ~= drag.pan_x then
                        mp.set_property_number("video-pan-x", new_pan_x)
                        drag.pan_x = new_pan_x
                    end
                    if new_pan_y ~= drag.pan_y then
                        mp.set_property_number("video-pan-y", new_pan_y)
                        drag.pan_y = new_pan_y
                    end
                end
                drag.moved = false
            end
        end
        
        mp.register_idle(idle)
        mp.add_forced_key_binding("mouse_move", "drag_mouse_move", function() drag.moved = true end)
        mp.add_forced_key_binding("mbtn_left_up", "drag_mouse_up", force_drag_termination)
        
        drag.cleanup = function()
            mp.remove_key_binding("drag_mouse_move")
            mp.remove_key_binding("drag_mouse_up")
            mp.unregister_idle(idle)
        end
    end
end

-- Fail-safe Kill Switches
mp.add_key_binding("mbtn_right", "drag-cancel-rightclick", force_drag_termination)
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

