# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

mpv-zero-friction is a config + Lua script collection for **mpv.net** (Windows), designed as a zero-friction video workstation. No build step, no tests, no linter. The repo root contains pre-built mpv.net binaries — **never modify** `.exe`, `.dll`, or `.com` files.

## Deployment

All config and script files deploy to `%AppData%\mpv.net\`:

| Source | Target |
|---|---|
| `mpv.conf`, `input.conf` | root of AppData folder |
| `scripts/*.lua` | `scripts/` subfolder |

After editing any file, **always copy it to the AppData target**. mpv.net reads only from AppData, not from this repo directory. Restart mpv.net to pick up changes.

Deploy commands (bash):
```bash
cp mpv.conf input.conf "$APPDATA/mpv.net/"
cp scripts/*.lua "$APPDATA/mpv.net/scripts/"
```

## File Inventory

| File | Lines | Purpose |
|---|---|---|
| `mpv.conf` | ~29 | Engine settings, OSC script-opts, OSD suppression |
| `input.conf` | ~60 | Hardware bindings in 8 numbered sections, right-hand optimized |
| `mpvnet.conf` | ~1 | mpv.net host settings (`process-instance=multi`) |
| `scripts/drag-to-pan.lua` | ~163 | Mouse1 drag panning when `video-zoom > 0` |
| `scripts/zoom-toward-cursor.lua` | ~65 | Zoom-toward-cursor: keeps point under mouse fixed during zoom |
| `scripts/double-right-quit.lua` | ~28 | Double-right-click quit (300ms threshold) |
| `scripts/mouse-repeat.lua` | ~43 | Side-button key repeat for frame-by-frame scrubbing |
| `scripts/osc.lua` | ~3000 | **Heavily modified** stock mpv OSC — ghost mode, `drag-to-pan-event` forwarding, `mouse_in_window` refresh fix, suppressed double-click fullscreen. Grep for `ghostmode` and `drag-to-pan-event` to find custom sections. |

## Binding Priority Stack

mpv resolves key bindings using a 4-tier priority system. Higher tiers override lower ones.

```
Tier 4 (highest)  mp.add_forced_key_binding(key, name, fn)
                  Always wins. Used temporarily during active drags.
                  drag-to-pan.lua binds "mouse_move" and "mbtn_left_up"
                  while a drag is in progress, removes them on release.

Tier 3            mp.set_key_bindings({...}, group, "force")
                  Group-based forced bindings scoped to a virtual mouse area.
                  osc.lua's "input" group binds "mbtn_left" with force —
                  overrides drag-to-pan inside the bar area.

Tier 2            mp.add_key_binding(key, name, fn, opts)
                  Script-level binding. Lower priority than forced.

Tier 1 (lowest)   input.conf
                  Static config-file bindings.
```

### Critical rule: NEVER use Tier 2 for MBTN_LEFT

A Tier 2 script binding (`mp.add_key_binding("mbtn_left", ...)`) **consumes** the key before mpv's input layer can form combos like `MBTN_LEFT+WHEEL_UP/DOWN`, breaking zoom-while-dragging. **Correct approach:** `mp.add_key_binding(nil, "name", fn, opts)` (named-only) + `MBTN_LEFT script-binding name` in `input.conf` (Tier 1).

### When to use each binding type

| Function | Tier | Use when... |
|---|---|---|
| `mp.add_key_binding(key, name, fn, opts)` | 2 | Permanent binding that can be overridden by forced bindings |
| `mp.add_key_binding(nil, name, fn, opts)` | 1 | Named-only binding triggered from `input.conf` via `script-binding name` |
| `mp.add_forced_key_binding(key, name, fn)` | 4 | **Temporary** override during active operation. Always remove when done. |
| `mp.set_key_bindings({...}, group, "force")` | 3 | Grouped forced bindings scoped to a virtual mouse area (OSC) |

### The drag-to-pan binding dance

1. **Permanent Tier 1** via input.conf (`MBTN_LEFT script-binding drag-to-pan`) — routes the initial click. Preserves `MBTN_LEFT+WHEEL` combo detection. OSC's Tier 3 overrides inside bar.
2. **Temporary Tier 4** on `mouse_move` and `mbtn_left_up` — added only while drag is active, removed on termination.

## MBTN_LEFT Click Routing

The most important interaction in the system. Three paths depending on context:

### Path A: Click inside the bar area (bottom 224px in ghost mode)

```
1. OSC's forced "input" group (Tier 3) captures it
2. process_event iterates elements to find hit
3a. Element hit → element action fires, drag-to-pan-event "up" sent on release
3b. No element hit → OSC sends drag-to-pan-event "down", drag starts if zoomed
```

### Path B: Click outside the bar area

```
1. OSC's forced group does NOT match (outside virtual mouse area)
2. input.conf "MBTN_LEFT script-binding drag-to-pan" (Tier 1) fires
3. If video-zoom > 0: drag starts with idle polling + forced move/up bindings
4. If video-zoom <= 0: ignored (falls through to mpv default)
```

### Path C: MBTN_LEFT held + mouse wheel (zoom while dragging)

```
1. User holds mbtn_left (drag starts via Path A or B)
2. User scrolls wheel — mpv's input layer detects MBTN_LEFT+WHEEL combo at Tier 1
3. zoom-toward-cursor.lua adjusts zoom + pan to keep cursor-point fixed
4. Drag and zoom operate simultaneously
```

This only works because both scripts use Tier 1 `script-binding` routes. Why both paths send "up": the OSC always sends `drag-to-pan-event "up"` on every release as a fail-safe — guarantees drag termination even if events arrive out of order.

## Inter-Script Communication

```
                         ┌──────────────────┐
                         │  input.conf      │
                         │  (Tier 1)        │
                         └────────┬─────────┘
                                  │ MBTN_RIGHT → script-binding
                                  v
┌─────────────────────┐    ┌──────────────────┐
│  osc.lua            │    │ double-right-     │
│                     │    │ quit.lua          │
│  Forced "input"     │    │                   │
│  group captures     │    │ Every right-click │
│  mbtn_left inside   │    │ sends cancel:     │
│  bar area           │    └────────┬──────────┘
│                     │             │
│  Non-element click: │             │ script-message
│  forwards "down"    │             │ drag-to-pan-event cancel
│                     │             │
│  Every up event:    │             v
│  forwards "up"      │    ┌──────────────────┐
│                     ├───>│ drag-to-pan.lua   │
│  script-message     │    │                   │
│  drag-to-pan-event  │    │ Receives:         │
│  down/up            │    │  - "down" → start │
└─────────────────────┘    │  - "up"   → stop  │
                           │  - "cancel"→ stop │
                           └──────────────────┘
```

All scripts communicate via `mp.commandv("script-message", "drag-to-pan-event", event)`. The message name must be **exactly** `drag-to-pan-event` — mpv silently drops undelivered script-messages (no error).

| Sender | Receiver | Message | When |
|---|---|---|---|
| `double-right-quit.lua` | `drag-to-pan.lua` | `cancel` | Every right-click down |
| `osc.lua` | `drag-to-pan.lua` | `down` | mbtn_left down inside bar, no element hit |
| `osc.lua` | `drag-to-pan.lua` | `up` | **Every** mbtn_left up (fail-safe) |
| `osc.lua` | `drag-to-pan.lua` | `cancel` | Every mouse_leave |

## OSC Render Pipeline

```
Event occurs (mouse move, property change, timer)
        │
        v
  request_tick() → creates/resumes state.tick_timer (rate-limited)
        │
        v
    tick() → checks display size → request_init() if changed
        │
        v
    render()
        ├── Updates virtual mouse areas for element groups
        │   Areas active when: state.osc_visible OR user_opts.ghostmode
        ├── Enables/disables key binding groups based on mouse area
        ├── Draws elements only if: visible AND NOT ghost mode
        └── Handles fade animation, schedules next tick
```

**Ghost mode:** Forces `visibility=always` so mouse areas stay permanently active. The 224px invisible hit area receives all mouse events. `render_elements()` is skipped — seeking/buttons/forwarding work, nothing visible.

## Coding Conventions

### Required patterns for new scripts

1. **`do...end` wrapper** (Ch 16.4) — Wrap entire script body for namespace isolation. mpv loads all scripts into a shared Lua state; without this, top-level locals collide.

2. **Local caching** (Ch 4.2) — Cache mpv API and math stdlib at script top. Locals resolve from registers (O(1)) vs hash lookups.
   ```lua
   local get_mouse_pos = mp.get_mouse_pos
   local min, max = math.min, math.max
   ```

3. **`{complex=true}`** — All key bindings needing down/up tracking. Without it, handler fires only on "press" (combined down+up) — breaks hold-to-drag and hold-to-repeat.

4. **PiL references** — Comments cite Programming in Lua chapter numbers (e.g., `-- Ch 16.4: Closure-based privacy`)

5. **Variable naming** — `drag.*` (state fields), `dx`/`dy` (deltas), `osd_w`/`osd_h` (screen dimensions)

6. **input.conf sections** — 8 numbered comment headers. Add new bindings to the appropriate section.

7. **OSC config** — All options on single `script-opts=` line. Custom colors: `#RRGGBB` hex validated by `^#%x%x%x%x%x%x$`.

### PiL pattern catalog

| Pattern | Chapter | Used in | Purpose |
|---|---|---|---|
| Local caching | Ch 4.2 | All scripts | O(1) register lookup vs hash |
| pcall error self-healing | Ch 8.4 | drag-to-pan.lua | Idle callback catches errors, calls `force_drag_termination()` |
| Metatable defaults | Ch 13.4.3 | drag-to-pan.lua | Uninitialized drag fields return 0 instead of nil |
| Closure-based privacy | Ch 16.4 | All custom scripts | `do...end` block scoping |
| Idiomatic clamp | Ch 18 | drag-to-pan, zoom-toward-cursor | `min(max(v, lo), hi)` |

### Timer patterns

**One-shot to periodic chaining** (mouse-repeat.lua): Fire immediately on down, start 200ms one-shot, then replace with 50ms periodic. `timer:kill()` on up always kills whichever is active since the variable is reassigned.

**Monotonic clock comparison** (double-right-quit.lua): `mp.get_time()` measures intervals between events. Immune to system clock changes.

### Anti-patterns

- **Never use globals** — all variables must be `local`
- **Never omit `{complex=true}`** for down/up tracking
- **Never use forced bindings permanently** — add on start, remove on finish
- **Never consume events that should fall through** — if zoom <= 0, return without blocking
- **Never shadow `table`** in handler nested scopes (shadows the stdlib)

## Invariants

Settings and contracts that **must not change**. Each entry documents what breaks.

### mpv.conf

| Setting | What breaks if changed |
|---|---|
| `window-dragging=no` | mpv's C++ layer intercepts MBTN_LEFT before Lua. Panning stops entirely. |
| `osc=no` | Built-in C++ OSC loads instead of custom osc.lua. Ghost mode, color customization, drag-to-pan forwarding all gone. |
| `osd-on-seek=no` | Large OSD overlay on every seek/frame-step. |
| `osd-bar=no` | Graphical volume bar renders center-screen. |
| Single `script-opts=` line | mpv only reads the **last** line. Split = silently ignored options. |

### Binding priority

| Invariant | What breaks if changed |
|---|---|
| drag-to-pan via input.conf Tier 1 | Tier 2 → zoom-while-dragging breaks. Tier 4 → seeking breaks. |
| OSC "input" group uses `"force"` | Without force, winner is load-order-dependent. |
| Forced drag bindings removed on termination | Leaked bindings permanently override OSC mouse handling. |
| "input" group must NOT bind wheel events | Bottom 224px becomes a zoom dead zone. |
| "input" group binds `mbtn_left_dbl` → `"ignore"` | Fast clicks trigger fullscreen toggle, conflicts with drag. |
| "input" group is always enabled | OSC loses all mouse input — no seeking, no buttons, no forwarding. |
| "showhide" groups use `"allow-vo-dragging+allow-hide-cursor"` flags | Cursor stays visible permanently. |

### Inter-script contracts

| Invariant | What breaks if changed |
|---|---|
| OSC sends "up" on **every** mbtn_left release | Drags from OSC forwarding may never terminate. |
| OSC sends "down" only when no element hit | Every seekbar click also starts a drag. |
| double-right-quit sends "cancel" on every right-click | Right-click during drag doesn't cancel it. |
| OSC mouse_leave sends "cancel" | Drags survive mouse-leave; seekbar stops responding (stale `mouse_in_window`). |
| `process_event` sets `mouse_in_window = true` on button events | After drags, `get_virt_mouse_pos()` returns -1,-1; seeking breaks. |
| Message name is exactly `drag-to-pan-event` | IPC breaks silently — no error on undelivered script-messages. |

### Zoom-toward-cursor

| Invariant | What breaks if changed |
|---|---|
| Pan resets to 0 when zoom transitions to <= 0 | Video stays offset from center at zero zoom. |
| `{repeatable = true}` on zoom bindings | Holding z/x or rapid scroll only fires once. |

### Ghost mode rendering

| Invariant | What breaks if changed |
|---|---|
| Forces `visibility=always` | Bar deactivates on idle; seeking unreachable. |
| Bar height is 224px | Too small → hard to aim. Too large → steals drag clicks. |
| Suppresses `render_elements()` | "Invisible" bar becomes visible. |
| Suppresses OSD messages for visibility/idle changes | Toggling shows confusing "OSC visibility: always" text. |
| `minmousemove=0` in script-opts | Dead zones where mouse movement is ignored. |

### drag-to-pan state machine

| Invariant | What breaks if changed |
|---|---|
| `force_drag_termination()` is idempotent | Multiple kill-switch triggers crash instead of no-oping. |
| Zoom observer terminates drag when zoom <= 0 | Zoom reset leaves user stuck in drag mode. |
| Ghost-state annihilation on re-press | Second press layers new drag on old, leaking bindings. |

## Debugging

1. Edit the `.lua` file
2. Restart mpv.net (no hot-reload)
3. Press `Shift+I` to view script console for errors

mpv Lua API docs: https://mpv.io/manual/master/#lua-scripting
