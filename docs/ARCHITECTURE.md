# Architecture

System index for mpv-zero-friction. The map of what exists and how it connects.

## File Inventory

| File | Lines | Purpose |
|---|---|---|
| `mpv.conf` | ~29 | Engine settings, OSC script-opts, OSD suppression |
| `input.conf` | ~60 | Hardware bindings in 8 numbered sections, right-hand optimized |
| `mpvnet.conf` | ~1 | mpv.net host settings (`process-instance=multi`) |
| `scripts/drag-to-pan.lua` | ~158 | Mouse1 drag panning when `video-zoom > 0` |
| `scripts/zoom-toward-cursor.lua` | ~63 | Zoom-toward-cursor: keeps point under mouse fixed during zoom |
| `scripts/double-right-quit.lua` | ~27 | Double-right-click quit (300ms threshold) |
| `scripts/mouse-repeat.lua` | ~43 | Side-button key repeat for frame-by-frame scrubbing |
| `scripts/osc.lua` | ~3000 | Modified stock OSC with ghost mode and color customization |

## Binding Priority Stack

mpv resolves key bindings using a 4-tier priority system. Higher tiers override lower ones. Understanding this is essential for correct script interaction.

```
Tier 4 (highest)  mp.add_forced_key_binding(key, name, fn)
                  Always wins. Used temporarily during active drags.
                  Example: drag-to-pan.lua binds "mouse_move" and
                  "mbtn_left_up" while a drag is in progress, then
                  removes them on release.

Tier 3            mp.set_key_bindings({...}, group, "force")
                  Group-based forced bindings. Active when the group
                  is enabled, scoped to a virtual mouse area.
                  Example: osc.lua's "input" group binds "mbtn_left"
                  with force — this overrides drag-to-pan's script-level
                  binding inside the bar area.

Tier 2            mp.add_key_binding(key, name, fn, opts)
                  Script-level binding. Lower priority than forced.
                  Example: drag-to-pan.lua binds "mbtn_left" at this
                  tier so OSC can override it inside the bar.

Tier 1 (lowest)   input.conf
                  Static config-file bindings. Lowest priority.
                  Example: MBTN_RIGHT → script-binding double-right-quit
```

**Why this matters:** drag-to-pan.lua uses Tier 1 (input.conf `script-binding`) for `mbtn_left` so that mpv's input layer can detect `MBTN_LEFT+WHEEL` combos for zoom-while-dragging. The OSC's Tier 3 forced binding still wins inside the ghost bar area via virtual mouse area scoping. If drag-to-pan used forced bindings for `mbtn_left`, seeking would break. If it used Tier 2 (script-level), combo zoom bindings would break.

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

**Messages:**

| Sender | Receiver | Message | When |
|---|---|---|---|
| `double-right-quit.lua` | `drag-to-pan.lua` | `drag-to-pan-event cancel` | Every right-click down event |
| `osc.lua` | `drag-to-pan.lua` | `drag-to-pan-event down` | `mbtn_left` down inside bar, no element hit |
| `osc.lua` | `drag-to-pan.lua` | `drag-to-pan-event up` | Every `mbtn_left` up event |

## OSC Render Pipeline

```
Event occurs (mouse move, property change, timer, etc.)
        │
        v
  request_tick()
        │
        ├── Creates or resumes state.tick_timer (one-shot mp.add_timeout)
        │   Rate-limited to avoid excessive redraws
        │
        v
    tick()
        │
        ├── Checks for display size changes → request_init() if changed
        ├── Calls osc_init() if state.initREQ is set (rebuilds all elements)
        │
        v
    render()
        │
        ├── Gets current screen size and mouse position
        ├── Updates virtual mouse areas for each element group:
        │     "input", "window-controls", "window-controls-title"
        │   Areas are active when: state.osc_visible OR user_opts.ghostmode
        │
        ├── Enables/disables key binding groups based on mouse area activity
        │
        ├── Draws elements (if visible AND not ghost mode):
        │     state.osc_visible and not user_opts.ghostmode → render_elements()
        │
        ├── Handles animation (fade in/out)
        │
        └── Schedules next tick if animating
```

**Ghost mode behavior:** When `ghostmode=yes`, the OSC forces `visibility=always` so mouse areas stay permanently active. The 224px invisible hit area receives all mouse events. Elements are never drawn — `render_elements()` is skipped. This means seeking, buttons, and drag-to-pan forwarding all work, but nothing is visible.

## MBTN_LEFT Click Routing

The most important interaction in the system. Two paths depending on where the click lands:

### Path A: Click inside the bar area (bottom 224px in ghost mode)

```
1. User clicks mbtn_left
2. OSC's forced "input" group (Tier 3) captures it
3. process_event("mbtn_left", "down") runs
4. OSC iterates elements to find which one was hit
5a. Element hit (seekbar, button, etc.)
    → Element's eventresponder fires (seek, play/pause, etc.)
    → On up: element action fires, drag-to-pan-event "up" also sent
5b. No element hit
    → OSC sends script-message "drag-to-pan-event" "down"
    → drag-to-pan.lua starts a drag (if zoomed in)
    → On up: drag-to-pan-event "up" sent, drag terminates
```

### Path B: Click outside the bar area

```
1. User clicks mbtn_left
2. OSC's forced group does NOT match (outside virtual mouse area)
3. input.conf binding "MBTN_LEFT script-binding drag-to-pan" (Tier 1) fires
4. drag_to_pan_handler({event="down"}) runs
5. If video-zoom > 0: drag starts with idle polling + forced move/up bindings
6. If video-zoom <= 0: event is ignored (falls through to mpv default)
```

### Path C: MBTN_LEFT held + mouse wheel (zoom while dragging)

```
1. User holds mbtn_left (drag starts via Path A or B)
2. User scrolls wheel while holding mbtn_left
3. mpv's input layer detects the MBTN_LEFT+WHEEL combo at Tier 1
4. Combo binding fires: script-binding zoom-in-cursor (or zoom-out-cursor)
5. zoom-toward-cursor.lua adjusts zoom + pan to keep cursor-point fixed
6. Drag and zoom operate simultaneously
```

This only works because both drag-to-pan and zoom-toward-cursor use Tier 1
input.conf `script-binding` routes (named-only bindings with nil key). If
drag-to-pan used a Tier 2 script-level binding, the script would consume
`mbtn_left` before mpv's input layer could form the combo.

### Why both paths send "up"

The OSC always sends `drag-to-pan-event "up"` on every `mbtn_left` release, even if no drag was active. This is a deliberate fail-safe — it guarantees drag termination even if events arrive out of order during concurrent mouse-wheel zoom scrolling.
