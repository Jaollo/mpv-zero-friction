# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

mpv-zero-friction is a configuration and Lua script collection for **mpv.net** (Windows), designed as a zero-friction video workstation. It is NOT a compiled application — there is no build step, no tests, no linting. The project consists of mpv config files and Lua scripts that mpv loads at runtime.

The `mpv.net/` directory contains the mpv.net binary distribution (pre-built, not source). Do not modify files there.

## Installation Target

All config and script files deploy to `%AppData%\Roaming\mpv.net\` on Windows:
- `mpv.conf` and `input.conf` → root of that folder
- `scripts/*.lua` → `scripts/` subfolder

## Architecture

### Config Layer
- **mpv.conf** — Engine settings. Key: `window-dragging=no` (required for drag-to-pan.lua to own MBTN_LEFT), `osc=no` (disables built-in OSC so custom osc.lua loads).
- **input.conf** — Hardware event mapping. Binds MBTN_LEFT to `script-binding drag-to-pan`, mouse wheel to zoom, side buttons to `script-binding mouse-back-repeat`/`mouse-forward-repeat`. All bindings are one-handed right-side optimized.

### Script Layer (scripts/)

**drag-to-pan.lua** (~135 lines, custom) — The most complex and debugged script. Mouse1 drag panning when `video-zoom > 0`. Architecture:
- State machine with `drag.active` / `drag.moved` / `drag.cleanup` fields
- Uses `mp.register_idle` + `mp.add_forced_key_binding` pattern to poll mouse delta during drag
- `force_drag_termination()` is the central kill switch — called from up events, right-click, mouse-leave, zoom-reset observer
- Pan math: `delta / osd_size / 2^zoom`, clamped to ±3
- **Known bug on line 72**: `drag_state.last_y` references old variable name (should be `drag.last_y`). This causes vertical panning drift during drag.
- Fail-safes: right-click cancel, mouse-leave cancel, zoom-to-zero observer, ghost-state annihilation on re-press
- Supports external triggers via `mp.register_script_message("drag-to-pan-event", ...)`

**mouse-repeat.lua** (~43 lines, custom) — Simulates key repeat for MBTN_BACK/MBTN_FORWARD (mouse side buttons) since mpv doesn't natively repeat them. Uses `mp.add_timeout` → `mp.add_periodic_timer` pattern (200ms delay, then 50ms interval). Both handlers use `{complex=true}` for down/up tracking.

**osc.lua** (~3000 lines, modified stock) — Fork of mpv's built-in On-Screen Controller. Adds color customization options (`background_color`, `timecode_color`, `buttons_color`, etc.) and up to 10 custom button slots. Configured via `script-opts` in mpv.conf with aggressive transparency/fade settings for minimal visual footprint.

### Critical Invariants
- `window-dragging=no` in mpv.conf is **mandatory** — without it, mpv's C++ layer steals MBTN_LEFT before Lua sees it, breaking drag-to-pan entirely
- `osc=no` in mpv.conf is **mandatory** — without it, mpv loads its built-in OSC instead of scripts/osc.lua
- drag-to-pan only activates when `video-zoom > 0` (user must scroll-zoom first before panning works)
- All Lua scripts use `{complex=true}` key binding pattern for proper down/up event tracking

## Debugging Lua Scripts

mpv.net loads Lua scripts from the scripts/ directory automatically. To test changes:
1. Edit the .lua file
2. Restart mpv.net (or press Shift+I to view script console for errors)

There is no REPL or hot-reload. The mpv Lua API docs are at: https://mpv.io/manual/master/#lua-scripting

## Key mpv Lua API Patterns Used

- `mp.add_key_binding(nil, "name", handler, {complex=true})` — named-only binding (bound via input.conf `script-binding name`)
- `mp.add_forced_key_binding` — temporary bindings that override input.conf (used during active drag)
- `mp.register_idle(fn)` / `mp.unregister_idle(fn)` — frame-synced polling loop
- `mp.get_mouse_pos()` → x, y (can return nil)
- `mp.get_osd_size()` → w, h (can be 0 during init)
- `mp.get_property_number("video-zoom", 0)` — zoom is logarithmic, actual scale = `2^zoom`
- `mp.observe_property("video-zoom", "number", fn)` — reactive observer
