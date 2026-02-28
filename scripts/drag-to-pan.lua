local mp = require 'mp'

local cleanup = nil
local moved = false

-- Local state context to bypass expensive IPC overhead during the rapid mouse movement loop
local drag_state = {
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
    if cleanup then
        cleanup()
        cleanup = nil
    end
end

local function drag_to_pan_handler(table)
    -- We only care about press and release. "repeat" is ignored for drag starts.
    if table.event == "up" then
        force_drag_termination()
        return
    end
    
    if table.event == "down" then
        force_drag_termination()
        
        moved = false
        drag_state.last_x, drag_state.last_y = mp.get_mouse_pos()
        
        -- Cache current video vectors STRICTLY ONCE when the click begins
        drag_state.pan_x = mp.get_property_number("video-pan-x", 0)
        drag_state.pan_y = mp.get_property_number("video-pan-y", 0)

        local idle = function()
            if moved then
                local current_x, current_y = mp.get_mouse_pos()
                local dx = current_x - drag_state.last_x
                local dy = current_y - drag_state.last_y
                
                drag_state.last_x, drag_state.last_y = current_x, current_y
                
                local zoom = mp.get_property_number("video-zoom", 0)
                
                -- Only apply the mathematics to the video pan if we are actually zoomed in
                if zoom > 0 then
                    local osd_w, osd_h = mp.get_osd_size()
                    if osd_w and osd_w > 0 then
                        local actual_zoom = 2 ^ zoom
                        
                        drag_state.pan_x = drag_state.pan_x + (dx / osd_w) / actual_zoom
                        drag_state.pan_y = drag_state.pan_y + (dy / osd_h) / actual_zoom
                        
                        drag_state.pan_y = clamp(drag_state.pan_y, -3, 3)
                        drag_state.pan_x = clamp(drag_state.pan_x, -3, 3)
                        
                        mp.set_property_number("video-pan-x", drag_state.pan_x)
                        mp.set_property_number("video-pan-y", drag_state.pan_y)
                    end
                end
                
                moved = false
            end
        end
        
        mp.register_idle(idle)
        mp.add_forced_key_binding("mouse_move", "drag_mouse_move", function() moved = true end)
        
        -- Structural Edge Case: Force an UP binding locally to catch releases if global is blocked
        mp.add_forced_key_binding("mbtn_left_up", "drag_mouse_up", force_drag_termination)
        
        cleanup = function()
            mp.remove_key_binding("drag_mouse_move")
            mp.remove_key_binding("drag_mouse_up")
            mp.unregister_idle(idle)
        end
    end
end

-- Global Kill-Switches: 
mp.add_key_binding("mbtn_right", "drag-cancel-rightclick", force_drag_termination)
mp.add_key_binding("mouse_leave", "drag-cancel-leave", force_drag_termination)

-- Use complex binding to handle down/up properly within the mpv state machine
mp.add_key_binding(nil, "drag-to-pan", drag_to_pan_handler, {complex=true})

-- Legacy support for external scripts sending messages
mp.register_script_message("drag-to-pan-event", function(event)
    if event == "up" or event == "cancel" then
        force_drag_termination()
    else
        drag_to_pan_handler({event = "down"})
    end
end)

-- Observer: annihilate state if zoom resets
mp.observe_property("video-zoom", "number", function(_, zoom)
    if zoom and zoom <= 0 then
        force_drag_termination()
    end
end)

