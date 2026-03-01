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

local STEP = 0.1
local PAN_LIMIT = 1.5
local PAN_EPSILON = 0.0001  -- skip writes below this delta (debounce at boundaries)

local function zoom_step(direction)
    local old_zoom = get_prop("video-zoom", 0)
    local new_zoom = old_zoom + direction * STEP

    -- Edge case: zoom transitions to <= 0 — center the video
    if new_zoom <= 0 and old_zoom > 0 then
        set_prop("video-zoom", new_zoom)
        set_prop("video-pan-x", 0)
        set_prop("video-pan-y", 0)
        return
    end

    -- Edge case: already at or below zero — just adjust zoom, no pan math
    if old_zoom <= 0 then
        set_prop("video-zoom", new_zoom)
        return
    end

    local mx, my = get_mouse_pos()
    local osd_w, osd_h = get_osd_size()

    -- Edge case: no mouse or OSD — fall back to center zoom
    if not mx or not osd_w or osd_w <= 0 or osd_h <= 0 then
        set_prop("video-zoom", new_zoom)
        return
    end

    -- Ch 11.1: Normalized cursor offset from screen center
    local nx = (mx - osd_w / 2) / osd_w
    local ny = (my - osd_h / 2) / osd_h

    -- Keep cursor-point fixed: pan_delta = normalized_offset * (1/2^new - 1/2^old)
    local scale_diff = 1 / 2 ^ new_zoom - 1 / 2 ^ old_zoom
    local old_pan_x = get_prop("video-pan-x", 0)
    local old_pan_y = get_prop("video-pan-y", 0)

    local new_pan_x = clamp(old_pan_x + nx * scale_diff, -PAN_LIMIT, PAN_LIMIT)
    local new_pan_y = clamp(old_pan_y + ny * scale_diff, -PAN_LIMIT, PAN_LIMIT)

    set_prop("video-zoom", new_zoom)
    -- Skip redundant pan writes at boundaries — prevents event flood to OSC
    if new_pan_x - old_pan_x > PAN_EPSILON or old_pan_x - new_pan_x > PAN_EPSILON then
        set_prop("video-pan-x", new_pan_x)
    end
    if new_pan_y - old_pan_y > PAN_EPSILON or old_pan_y - new_pan_y > PAN_EPSILON then
        set_prop("video-pan-y", new_pan_y)
    end
end

-- Named-only bindings (nil key) — input.conf routes keys here via script-binding.
-- Tier 1 preserves MBTN_LEFT+WHEEL combo detection for zoom-while-dragging.
mp.add_key_binding(nil, "zoom-in-cursor", function() zoom_step(1) end, {repeatable = true})
mp.add_key_binding(nil, "zoom-out-cursor", function() zoom_step(-1) end, {repeatable = true})

end -- do block
