do -- Ch 16.4: Closure-based privacy

local mp = require 'mp'

local ZONE = 90  -- pixel square in top-right corner

-- Tier 3 forced binding group — overrides drag-to-pan inside the zone
mp.set_key_bindings({
    {"mbtn_left", function() mp.command("quit") end},
}, "corner-exit", "force")
mp.enable_key_bindings("corner-exit", "allow-vo-dragging+allow-hide-cursor")

-- Position the mouse area in the top-right corner, update on resize
local function update_area()
    local w, h = mp.get_osd_size()
    if w and w > 0 then
        mp.set_mouse_area(w - ZONE, 0, w, ZONE, "corner-exit")
    end
end

mp.observe_property("osd-width", "number", update_area)
mp.observe_property("osd-height", "number", update_area)

end
