local mp = require 'mp'

local timer_back = nil
local timer_forward = nil

local function repeat_back()
    mp.command("frame-back-step")
end

local function repeat_forward()
    mp.command("frame-step")
end

local function handle_back(table)
    if table.event == "down" then
        mp.command("frame-back-step")
        if timer_back then timer_back:kill() end
        -- 200ms initial delay, then 50ms interval for smooth continuous stepping
        timer_back = mp.add_timeout(0.2, function()
            timer_back = mp.add_periodic_timer(0.05, repeat_back)
        end)
    elseif table.event == "up" then
        if timer_back then timer_back:kill() end
        timer_back = nil
    end
end

local function handle_forward(table)
    if table.event == "down" then
        mp.command("frame-step")
        if timer_forward then timer_forward:kill() end
        timer_forward = mp.add_timeout(0.2, function()
            timer_forward = mp.add_periodic_timer(0.05, repeat_forward)
        end)
    elseif table.event == "up" then
        if timer_forward then timer_forward:kill() end
        timer_forward = nil
    end
end

mp.add_key_binding(nil, "mouse-back-repeat", handle_back, {complex=true})
mp.add_key_binding(nil, "mouse-forward-repeat", handle_forward, {complex=true})
