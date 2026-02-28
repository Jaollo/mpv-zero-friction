do -- Ch 16.4: Closure-based privacy — all state invisible to other scripts

local mp = require 'mp'

-- Ch 4.2: Local-cache mpv API functions for hot-path performance
local get_mouse_pos = mp.get_mouse_pos
local get_osd_size  = mp.get_osd_size
local get_prop      = mp.get_property_number
local set_prop      = mp.set_property_number
local get_time      = mp.get_time

-- Ch 18 + 4.2: Idiomatic clamp with cached math stdlib
local min, max = math.min, math.max
local abs = math.abs
local function clamp(v, lo, hi) return min(max(v, lo), hi) end

-- Ch 13.4.3: Metatable defaults — uninitialized fields return 0 instead of nil
local drag_defaults = { __index = function() return 0 end }
local drag = setmetatable({
    active = false,
    moved = false,
    cleanup = nil,
    last_x = 0,
    last_y = 0,
    pan_x = 0,
    pan_y = 0,
}, drag_defaults)

-- Momentum state
local momentum_timer = nil
local VELOCITY_HISTORY = 4
local FRICTION = 0.92
local VELOCITY_THRESHOLD = 0.001

local function kill_momentum()
    if momentum_timer then
        momentum_timer:kill()
        momentum_timer = nil
    end
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

local function start_momentum(vx, vy)
    kill_momentum()

    local zoom = get_prop("video-zoom", 0)
    if zoom <= 0 then return end

    -- Only start if velocity is meaningful
    if abs(vx) < VELOCITY_THRESHOLD and abs(vy) < VELOCITY_THRESHOLD then return end

    momentum_timer = mp.add_periodic_timer(1/60, function()
        vx, vy = vx * FRICTION, vy * FRICTION

        if abs(vx) < VELOCITY_THRESHOLD and abs(vy) < VELOCITY_THRESHOLD then
            kill_momentum()
            return
        end

        local current_zoom = get_prop("video-zoom", 0)
        if current_zoom <= 0 then
            kill_momentum()
            return
        end

        local osd_w, osd_h = get_osd_size()
        if not osd_w or osd_w <= 0 or osd_h <= 0 then
            kill_momentum()
            return
        end

        local actual_zoom = 2 ^ current_zoom
        local pan_x = get_prop("video-pan-x", 0)
        local pan_y = get_prop("video-pan-y", 0)

        local new_pan_x = clamp(pan_x + (vx / osd_w) / actual_zoom, -3, 3)
        local new_pan_y = clamp(pan_y + (vy / osd_h) / actual_zoom, -3, 3)

        if new_pan_x ~= pan_x then set_prop("video-pan-x", new_pan_x) end
        if new_pan_y ~= pan_y then set_prop("video-pan-y", new_pan_y) end
    end)
end

local function drag_to_pan_handler(table)
    if table.event == "up" then
        -- Capture velocity history before terminating
        local vx, vy = drag.vel_x, drag.vel_y
        local was_active = drag.active
        force_drag_termination()
        if was_active and (abs(vx) > VELOCITY_THRESHOLD or abs(vy) > VELOCITY_THRESHOLD) then
            start_momentum(vx, vy)
        end
        return
    end

    if table.event == "down" then
        -- Ensure any ghost state is annihilated before starting a new drag
        force_drag_termination()
        kill_momentum()

        local initial_x, initial_y = get_mouse_pos()
        if initial_x == nil or initial_y == nil then return end

        local zoom = get_prop("video-zoom", 0)
        if zoom <= 0 then return end

        drag.active = true
        drag.moved = false
        drag.last_x, drag.last_y = initial_x, initial_y
        drag.vel_x, drag.vel_y = 0, 0
        drag.last_time = get_time()

        -- Cache initial pan values with safe defaults
        drag.pan_x = get_prop("video-pan-x", 0)
        drag.pan_y = get_prop("video-pan-y", 0)

        -- Ch 8.4: pcall-wrapped idle callback — errors self-heal via force_drag_termination
        local idle = function()
            local ok, err = pcall(function()
                if drag.active and drag.moved then
                    local current_x, current_y = get_mouse_pos()
                    local osd_w, osd_h = get_osd_size()

                    -- Defensive check: If mouse lost or window sized to 0, abort
                    if not current_x or not osd_w or osd_w <= 0 or osd_h <= 0 then
                        force_drag_termination()
                        return
                    end

                    local dx = current_x - drag.last_x
                    local dy = current_y - drag.last_y

                    -- Optimization: Only proceed if there is actual motion
                    if dx ~= 0 or dy ~= 0 then
                        -- Track velocity for momentum
                        local now = get_time()
                        local dt = now - drag.last_time
                        if dt > 0 then
                            drag.vel_x = dx / dt
                            drag.vel_y = dy / dt
                        end
                        drag.last_time = now

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
            local vx, vy = drag.vel_x, drag.vel_y
            force_drag_termination()
            if abs(vx) > VELOCITY_THRESHOLD or abs(vy) > VELOCITY_THRESHOLD then
                start_momentum(vx, vy)
            end
        end)

        drag.cleanup = function()
            mp.remove_key_binding("drag_mouse_move")
            mp.remove_key_binding("drag_mouse_up")
            mp.unregister_idle(idle)
        end
    end
end

-- Fail-safe Kill Switches
mp.add_key_binding("mbtn_right", "drag-cancel-rightclick", function()
    kill_momentum()
    force_drag_termination()
end)
mp.add_key_binding("mouse_leave", "drag-cancel-leave", function()
    kill_momentum()
    force_drag_termination()
end)

-- Robust complex binding for native button tracking
mp.add_key_binding(nil, "drag-to-pan", drag_to_pan_handler, {complex=true})

-- Support for external triggers
mp.register_script_message("drag-to-pan-event", function(event)
    if event == "up" or event == "cancel" then
        kill_momentum()
        force_drag_termination()
    else
        drag_to_pan_handler({event = "down"})
    end
end)

-- Zoom Reset Observer: ensures the drag machine and momentum die when zoom does
mp.observe_property("video-zoom", "number", function(_, zoom)
    if zoom and zoom <= 0 then
        kill_momentum()
        force_drag_termination()
    end
end)

end -- do block
