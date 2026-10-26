do -- Ch 16.4: Closure-based privacy

local mp = require 'mp'

-- Ch 4.2: Local caching of hot-path functions
local mp_command = mp.command
local add_timeout = mp.add_timeout
local add_periodic_timer = mp.add_periodic_timer

local timer_back = nil
local timer_forward = nil

-- Tuning constants for hold-to-repeat scrubbing
local INITIAL_DELAY    = 0.25  -- 250ms initial delay before repeating starts
local BACK_INTERVAL    = 0.12  -- 120ms interval (~8.3 frames/sec)
local FORWARD_INTERVAL = 0.12  -- 120ms interval (slowed down from 50ms for controlled precision)

local function repeat_back()
    mp_command("frame-back-step")
end

local function repeat_forward()
    mp_command("frame-step")
end

local function handle_back(t)
    local event = (type(t) == "table" and t.event) or "press"

    if event == "down" or event == "press" then
        mp_command("frame-back-step")
        if timer_back then timer_back:kill() end
        if event == "down" then
            timer_back = add_timeout(INITIAL_DELAY, function()
                timer_back = add_periodic_timer(BACK_INTERVAL, repeat_back)
            end)
        end
    elseif event == "repeat" then
        mp_command("frame-back-step")
    elseif event == "up" then
        if timer_back then timer_back:kill() end
        timer_back = nil
    end
end

local function handle_forward(t)
    local event = (type(t) == "table" and t.event) or "press"

    if event == "down" or event == "press" then
        mp_command("frame-step")
        if timer_forward then timer_forward:kill() end
        if event == "down" then
            timer_forward = add_timeout(INITIAL_DELAY, function()
                timer_forward = add_periodic_timer(FORWARD_INTERVAL, repeat_forward)
            end)
        end
    elseif event == "repeat" then
        mp_command("frame-step")
    elseif event == "up" then
        if timer_forward then timer_forward:kill() end
        timer_forward = nil
    end
end

-- Named-only bindings for input.conf script-binding routing
mp.add_key_binding(nil, "mouse-back-repeat", handle_back, {complex = true})
mp.add_key_binding(nil, "mouse-forward-repeat", handle_forward, {complex = true})

-- Direct Tier 2 bindings for all possible mouse side-button and nav key aliases
local back_keys = {
    "mbtn_back", "MBTN_BACK", "MBTN_Back",
    "mouse_btn7", "MOUSE_BTN7",
    "mouse_btn5", "MOUSE_BTN5",
    "go_back", "GO_BACK",
    "xf86_back", "XF86_BACK",
    "prev", "Prev"
}
for _, key in ipairs(back_keys) do
    mp.add_key_binding(key, "back-direct-" .. key, handle_back, {complex = true})
end

local forward_keys = {
    "mbtn_forward", "MBTN_FORWARD", "MBTN_Forward",
    "mouse_btn8", "MOUSE_BTN8",
    "mouse_btn6", "MOUSE_BTN6",
    "go_forward", "GO_FORWARD",
    "xf86_forward", "XF86_FORWARD",
    "next", "Next"
}
for _, key in ipairs(forward_keys) do
    mp.add_key_binding(key, "forward-direct-" .. key, handle_forward, {complex = true})
end

end
