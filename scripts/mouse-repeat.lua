do -- Ch 16.4: Closure-based privacy

local mp = require 'mp'

-- Ch 4.2: Local caching of hot-path functions
local mp_command = mp.command
local add_timeout = mp.add_timeout
local add_periodic_timer = mp.add_periodic_timer

local timer_back = nil
local timer_forward = nil

local function repeat_back()
    mp_command("frame-back-step")
end

local function repeat_forward()
    mp_command("frame-step")
end

local function handle_back(t)
    if not t or not t.event then return end

    if t.event == "down" or t.event == "press" then
        mp_command("frame-back-step")
        if timer_back then timer_back:kill() end
        if t.event == "down" then
            -- 200ms initial delay, then 120ms interval (frame-back-step needs time to decode)
            timer_back = add_timeout(0.2, function()
                timer_back = add_periodic_timer(0.12, repeat_back)
            end)
        end
    elseif t.event == "repeat" then
        mp_command("frame-back-step")
    elseif t.event == "up" then
        if timer_back then timer_back:kill() end
        timer_back = nil
    end
end

local function handle_forward(t)
    if not t or not t.event then return end

    if t.event == "down" or t.event == "press" then
        mp_command("frame-step")
        if timer_forward then timer_forward:kill() end
        if t.event == "down" then
            -- 200ms initial delay, then 50ms interval for smooth forward stepping
            timer_forward = add_timeout(0.2, function()
                timer_forward = add_periodic_timer(0.05, repeat_forward)
            end)
        end
    elseif t.event == "repeat" then
        mp_command("frame-step")
    elseif t.event == "up" then
        if timer_forward then timer_forward:kill() end
        timer_forward = nil
    end
end

-- Named-only bindings for input.conf script-binding routing
mp.add_key_binding(nil, "mouse-back-repeat", handle_back, {complex = true})
mp.add_key_binding(nil, "mouse-forward-repeat", handle_forward, {complex = true})

-- Direct Tier 2 bindings as fallback in case input.conf binding is missed
mp.add_key_binding("mbtn_back", "mouse-back-direct", handle_back, {complex = true})
mp.add_key_binding("mbtn_forward", "mouse-forward-direct", handle_forward, {complex = true})

end

