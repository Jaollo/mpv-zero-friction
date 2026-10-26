# agents.md

This file provides guidance to AI coding agents when working with code in this repository.

## Project Overview

mpv-zero-friction is a config + Lua script collection for **mpv.net** (Windows), designed as a zero-friction video workstation. No build step, no tests, no linter. The repo root contains pre-built mpv.net binaries — **never modify** `.exe`, `.dll`, or `.com` files.

## Deployment

All config and script files deploy to `%AppData%\mpv.net\`:

| Source | Target |
|---|---|
| `mpv.conf`, `input.conf`, `mpvnet.conf` | root of AppData folder |
| `scripts/*.lua` | `scripts/` subfolder |

After editing any file, **always copy it to the AppData target**. mpv.net reads only from AppData, not from this repo directory. Restart mpv.net to pick up changes.

Deploy commands (bash):
```bash
cp mpv.conf input.conf mpvnet.conf "$APPDATA/mpv.net/"
cp scripts/*.lua "$APPDATA/mpv.net/scripts/"
```

## Versioning Policy

- Future version bumps follow semantic patch versions: the bump after `v0.9` is `v0.9.1`, followed by `v0.9.2`, `v0.9.3`, etc.
- When performing a version bump:
  1. Update version headers in `readme.md` and `input.conf`.
  2. Deploy updated files to `%AppData%\mpv.net\`.
  3. Commit and push to git with all markdown documentation remaining strictly lowercase (`readme.md`, `agents.md`).

## File Inventory

| File | Lines | Purpose |
|---|---|---|
| `mpv.conf` | ~29 | Engine settings, OSC script-opts, OSD suppression |
| `input.conf` | ~63 | Hardware bindings in 9 sections, right-hand optimized |
| `mpvnet.conf` | ~1 | mpv.net host settings (`process-instance=multi`) |
| `scripts/drag-to-pan.lua` | ~163 | Mouse1 drag panning when `video-zoom > 0` |
| `scripts/zoom-toward-cursor.lua` | ~70 | Zoom-toward-cursor with pan boundary debounce |
| `scripts/double-right-quit.lua` | ~37 | Mouse3 single=pause (300ms delay), double=quit |
| `scripts/mouse-repeat.lua` | ~94 | Side-button key repeat for frame-by-frame scrubbing |
| `scripts/corner-exit.lua` | ~24 | Invisible 90px quit zone in top-right corner |
| `scripts/osc.lua` | ~3000 | **Heavily modified** stock mpv OSC — ghost mode, `drag-to-pan-event` forwarding, `mouse_in_window` refresh fix, suppressed double-click fullscreen. Grep for `ghostmode` and `drag-to-pan-event` to find custom sections. |

## Architecture

### Binding Priority Stack

```
Tier 4 (highest)  mp.add_forced_key_binding(key, name, fn)
                  Always wins. Used temporarily during active drags.

Tier 3            mp.set_key_bindings({...}, group, "force")
                  Group-based forced bindings scoped to a virtual mouse area.
                  osc.lua "input" group: captures mbtn_left inside the bar.
                  corner-exit.lua: captures mbtn_left in top-right 90px.

Tier 2            mp.add_key_binding(key, name, fn, opts)
                  Script-level binding. Lower priority than forced.

Tier 1 (lowest)   input.conf
                  Static config-file bindings.
```

### Critical rule: NEVER use Tier 2 for MBTN_LEFT

A Tier 2 script binding (`mp.add_key_binding("mbtn_left", ...)`) **consumes** the key before mpv's input layer can form combos like `MBTN_LEFT+WHEEL_UP/DOWN`, breaking zoom-while-dragging. **Correct approach:** `mp.add_key_binding(nil, "name", fn, opts)` (named-only) + `MBTN_LEFT script-binding name` in `input.conf` (Tier 1).

### MBTN_LEFT Click Routing

Three paths depending on cursor position:

**Path A: Click inside the bar area (bottom 224px)**
```
OSC's forced "input" group (Tier 3) captures it → seeking/buttons
```

**Path B: Click in top-right corner (90px)**
```
corner-exit.lua's forced group (Tier 3) captures it → quit
```

**Path C: Click anywhere else**
```
input.conf Tier 1 fires → drag-to-pan starts if zoomed
```

### Inter-Script Communication

| Sender | Receiver | Message | When |
|---|---|---|---|
| `double-right-quit.lua` | `drag-to-pan.lua` | `cancel` | Every Mouse3 down |
| `osc.lua` | `drag-to-pan.lua` | `down` | mbtn_left down inside bar, no element hit |
| `osc.lua` | `drag-to-pan.lua` | `up` | **Every** mbtn_left up (fail-safe) |
| `osc.lua` | `drag-to-pan.lua` | `cancel` | Every mouse_leave |

All via `mp.commandv("script-message", "drag-to-pan-event", event)`.

## Resolved Issue: Ghost Seekbar and Top Bar Desync / Crash

Previously, rapid window resizes or mouse interaction near the top bar caused the seekbar and top bar to freeze permanently until mpv was restarted. The root causes were:
1. `get_virt_mouse_pos()` performed `x * sx` without checking if `x` was nil, which threw a fatal arithmetic error when mouse position was queryable as nil during resizes or when the cursor left the window.
2. In `render()`, an out-of-scope reference `wc_geo.w` was indexed when cursor hovered near the top bar, throwing `attempt to index global 'wc_geo' (a nil value)`.
3. Zero-size OSD dimensions during resize/minimization caused division by zero in `set_virt_mouse_area()`.
4. `mouse_leave()` did not reset `state.active_element`, locking the init pipeline.

All paths now defensively check nil/zero values, geometry coordinates are properly aligned, and `render()` and `process_event()` are wrapped in `pcall` guards so errors cannot kill `osc.lua`.

## Resolved Issue: Mouse4 & Mouse5 Side Buttons

Previously, Mouse4 and Mouse5 side buttons did not work reliably or failed to register. The causes were:
1. `scripts/mouse-repeat.lua` had a strict guard `if not t or not t.event then return end`. When triggered via non-complex pathways, direct commands, or fallback invocations where `t` was nil or lacked `event`, the action was silently dropped. `handle_back` and `handle_forward` now safely fallback to `event = "press"` when `t.event` is absent.
2. Incomplete key alias coverage: depending on mouse software (Logitech G Hub, Razer, SteelSeries) or Windows driver configurations, side buttons could be emitted as `MBTN_BACK`/`MBTN_FORWARD`, `MOUSE_BTN7`/`MOUSE_BTN8`, `MOUSE_BTN5`/`MOUSE_BTN6`, `GO_BACK`/`GO_FORWARD`, `XF86_BACK`/`XF86_FORWARD`, `Prev`/`Next`, or `Alt+LEFT`/`Alt+RIGHT`. Full coverage is now bound in `input.conf` and registered in `mouse-repeat.lua`.
3. External mouse hook conflicts: Third-party mouse utilities (e.g., OpenLogi / Logitech background software) can install global low-level mouse hooks (`WH_MOUSE_LL`) that swallow or re-route XButton1/XButton2 events before they reach the mpv.net window. If side buttons stop responding, check for conflicting background mouse tools.

## Coding Conventions

1. **`do...end` wrapper** (Ch 16.4) — namespace isolation in shared Lua state.
2. **Local caching** (Ch 4.2) — `local get_mouse_pos = mp.get_mouse_pos`
3. **`{complex=true}`** — all bindings needing down/up tracking.
4. **PiL references** — comments cite Programming in Lua chapters.
5. **OSC config** — all options on single `script-opts=` line (mpv reads only the last one).

### Anti-patterns

- **Never use globals** — all variables must be `local`
- **Never omit `{complex=true}`** for down/up tracking
- **Never use forced bindings permanently** — add on start, remove on finish
- **Never consume events that should fall through** — if zoom <= 0, return without blocking

## Invariants

### mpv.conf

| Setting | What breaks if changed |
|---|---|
| `window-dragging=no` | mpv intercepts MBTN_LEFT before Lua. Drag-to-pan dies. |
| `osc=no` | Built-in C++ OSC loads instead of custom osc.lua. Ghost mode gone. |
| `osd-on-seek=no` | Large OSD overlay on every seek. |
| `osd-bar=no` | Graphical volume bar renders center-screen. |
| Single `script-opts=` line | mpv only reads the last line. Split = silently ignored. |

### Binding priority

| Invariant | What breaks |
|---|---|
| drag-to-pan via input.conf Tier 1 | Tier 2 → zoom-while-dragging breaks. |
| OSC "input" group uses `"force"` | Without force, winner is load-order-dependent. |
| "input" group must NOT bind wheel events | Bottom 224px becomes a zoom dead zone. |
| "input" group binds `mbtn_left_dbl` → `"ignore"` | Fast clicks trigger fullscreen. |

### Zoom-toward-cursor

| Invariant | What breaks |
|---|---|
| Pan resets to 0 when zoom transitions to <= 0 | Video stays offset at zero zoom. |
| `{repeatable = true}` on zoom bindings | Scroll only fires once. |
| Pan debounce skips writes below epsilon | Boundary event flood returns. |

## Debugging

1. Edit the `.lua` file in the repo
2. Deploy: `cp scripts/*.lua "$APPDATA/mpv.net/scripts/"`
3. Restart mpv.net (no hot-reload)
4. `Shift+I` for script console

mpv Lua API docs: https://mpv.io/manual/master/#lua-scripting
