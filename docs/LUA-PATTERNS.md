# Lua Patterns

Style guide and best practices for mpv-zero-friction scripts. New scripts written using this guide will be correct by default.

## Required Patterns for New Scripts

Every custom script in this codebase must follow these three patterns:

### 1. `do...end` wrapper

Wrap the entire script body in a `do...end` block for namespace isolation. Nothing leaks to the global scope.

```lua
do -- Ch 16.4: Closure-based privacy

local mp = require 'mp'

-- all script code here

end -- do block
```

### 2. Local caching

Cache mpv API functions and math stdlib at the script top, before any function definitions. This avoids repeated table lookups on the hot path.

```lua
-- Ch 4.2: Local-cache mpv API functions
local get_mouse_pos = mp.get_mouse_pos
local get_osd_size  = mp.get_osd_size
local get_prop      = mp.get_property_number
local set_prop      = mp.set_property_number

-- Ch 4.2: Cache math stdlib
local min, max = math.min, math.max
```

### 3. `{complex=true}` for key bindings

All key bindings that need down/up tracking must use `{complex=true}`. The handler receives a table with an `event` field (`"down"`, `"up"`, `"repeat"`, `"press"`).

```lua
mp.add_key_binding(nil, "my-handler", function(table)
    if table.event == "down" then
        -- start action
    elseif table.event == "up" then
        -- stop action
    end
end, {complex = true})
```

## PiL Pattern Catalog

Each pattern used in the codebase, with Programming in Lua chapter reference.

### Ch 4.2: Local Caching

**What:** Assign frequently-called functions to local variables at the top of the script.

**Why:** Lua resolves locals from registers (O(1)) vs globals/table fields through hash lookups. On hot paths called every frame, this matters.

**Used in:** `drag-to-pan.lua` (lines 6-12), `double-right-quit.lua` (line 6)

```lua
local get_mouse_pos = mp.get_mouse_pos
local min, max = math.min, math.max
```

### Ch 8.4: pcall Error Self-Healing

**What:** Wrap error-prone code in `pcall()` and handle failure gracefully instead of crashing.

**Why:** The idle callback in drag-to-pan runs every frame. If it throws (e.g., nil mouse position edge case), the entire drag system would die permanently. pcall catches the error, logs it, and calls `force_drag_termination()` to reset to a clean state.

**Used in:** `drag-to-pan.lua` (lines 64-116)

```lua
local ok, err = pcall(function()
    -- code that might fail
end)
if not ok then
    mp.msg.warn("error: " .. tostring(err))
    force_drag_termination()  -- reset to clean state
end
```

### Ch 13.4.3: Metatable Defaults

**What:** Set a `__index` metamethod that returns a default value for missing keys instead of nil.

**Why:** The drag state table has many fields that may not be initialized yet. Without the metatable, accessing `drag.some_field` before it's set returns nil, which causes arithmetic errors (`nil + 1`). The metatable makes uninitialized numeric fields return 0.

**Used in:** `drag-to-pan.lua` (lines 16-25)

```lua
local drag_defaults = { __index = function() return 0 end }
local drag = setmetatable({
    active = false,
    moved = false,
    -- explicitly set fields override the metatable
}, drag_defaults)
```

### Ch 16.4: Closure-Based Privacy

**What:** Wrap the entire script in a `do...end` block so all locals are invisible to other scripts.

**Why:** mpv loads all Lua scripts into the same Lua state. Without the `do...end` block, top-level locals could collide with identically-named locals in other scripts. The block creates a closure scope that makes everything private.

**Used in:** `drag-to-pan.lua`, `double-right-quit.lua`

```lua
do -- Ch 16.4: Closure-based privacy
local mp = require 'mp'
-- everything here is invisible to other scripts
end
```

### Ch 18: Idiomatic Clamp

**What:** A one-liner clamp function using `min` and `max`.

**Why:** Pan values must stay within bounds (-3 to +3). This is the standard Lua idiom — no branching, no temporaries.

**Used in:** `drag-to-pan.lua` (line 13)

```lua
local function clamp(v, lo, hi) return min(max(v, lo), hi) end
```

## Timer Patterns

### One-Shot to Periodic Chaining (mouse-repeat.lua)

Simulates key repeat: fire once immediately on down, start a one-shot delay timer, then on expiry replace it with a periodic timer. Kill everything on up.

```lua
local function handle(table)
    if table.event == "down" then
        mp.command("frame-step")             -- immediate first action
        timer = mp.add_timeout(0.2, function()  -- 200ms initial delay
            timer = mp.add_periodic_timer(0.05, function()  -- then 50ms repeat
                mp.command("frame-step")
            end)
        end)
    elseif table.event == "up" then
        if timer then timer:kill() end       -- stop everything
        timer = nil
    end
end
```

**Key detail:** The one-shot callback replaces the `timer` variable with the periodic timer. This means `timer:kill()` on up always kills whichever timer is currently active.

### Monotonic Clock Comparison (double-right-quit.lua)

Uses `mp.get_time()` (monotonic, not wall-clock) to measure intervals between events. Immune to system clock changes.

```lua
local clock = mp.get_time
local last_down = 0
local THRESHOLD = 0.3

if table.event == "down" then
    local now = clock()
    if now - last_down < THRESHOLD then
        mp.command("quit")
        last_down = 0           -- reset to prevent triple-click
    else
        last_down = now
    end
end
```

## Binding Patterns

### When to use each binding type

| Function | Priority | Use when... |
|---|---|---|
| `mp.add_key_binding(key, name, fn, opts)` | Tier 2 | You want a **permanent** binding that **can be overridden** by forced bindings. Normal case for most scripts. |
| `mp.add_key_binding(nil, name, fn, opts)` | Tier 1 | You want a **named-only** binding triggered from `input.conf` via `script-binding name`. The script doesn't claim the key directly. |
| `mp.add_forced_key_binding(key, name, fn)` | Tier 4 | You need a **temporary** override during an active operation (e.g., tracking mouse movement during a drag). **Always remove it when done.** |
| `mp.set_key_bindings({...}, group, "force")` | Tier 3 | You need **grouped forced bindings** scoped to a virtual mouse area. Used by OSC for element interaction. |

### The drag-to-pan binding dance

drag-to-pan.lua uses two tiers in sequence:

1. **Permanent Tier 1** binding via `input.conf` (`MBTN_LEFT script-binding drag-to-pan`) — routes the initial click to the script. Using Tier 1 preserves `MBTN_LEFT+WHEEL` combo detection for zoom-while-dragging. OSC's Tier 3 still overrides this inside the bar area.
2. **Temporary Tier 4** bindings on `mouse_move` and `mbtn_left_up` — added only while a drag is active, removed on termination. These override everything to ensure the drag tracks reliably.

```lua
-- Permanent: named-only binding (nil key), triggered via input.conf script-binding
mp.add_key_binding(nil, "drag-to-pan", handler, {complex=true})

-- In input.conf:
-- MBTN_LEFT  script-binding drag-to-pan

-- Temporary: forced (Tier 4), added in handler, removed in cleanup
mp.add_forced_key_binding("mouse_move", "drag_mouse_move", fn)
mp.add_forced_key_binding("mbtn_left_up", "drag_mouse_up", fn)
```

**Why Tier 1, not Tier 2?** A Tier 2 script-level binding (`mp.add_key_binding("mbtn_left", ...)`) consumes the `mbtn_left` event before mpv's input layer can form combos like `MBTN_LEFT+WHEEL_UP`. This breaks zoom-while-dragging. Keeping `MBTN_LEFT` in input.conf alongside the combo bindings lets mpv handle combo detection at the same tier.

## Anti-Patterns

### Never use globals

All variables must be `local`. mpv loads scripts into a shared Lua state — globals from one script can overwrite globals from another.

### Never omit `{complex=true}` for down/up tracking

Without it, the handler fires only on "press" (down+up combined). You cannot distinguish between press and release, which breaks hold-to-drag and hold-to-repeat patterns.

```lua
-- WRONG: fires once on press, no up event
mp.add_key_binding("mbtn_left", "name", handler)

-- RIGHT: fires separately for down, up, repeat
mp.add_key_binding("mbtn_left", "name", handler, {complex=true})
```

### Never use forced bindings permanently

Forced bindings override everything, including other scripts. If left active permanently, they break other scripts' ability to handle the same key. Use forced bindings only during temporary operations (active drag, active resize) and always remove them when done.

```lua
-- WRONG: forced binding stays forever
mp.add_forced_key_binding("mouse_move", "my_move", fn)

-- RIGHT: add on start, remove on finish
mp.add_forced_key_binding("mouse_move", "my_move", fn)
-- ... later, in cleanup:
mp.remove_key_binding("my_move")
```

### Never consume events that should fall through

If your script handles a key but the event isn't relevant (e.g., `mbtn_left` down when `video-zoom <= 0`), return without doing anything. Don't call `mp.set_key_bindings` to block the event — let it fall through to lower-priority bindings.

### Never shadow `table` in nested scopes

The handler parameter is conventionally named `table` in this codebase (matching mpv docs). Don't redefine `table` inside the handler — it shadows the Lua standard library's `table` module, which could cause subtle bugs if any library code runs inside the handler.
