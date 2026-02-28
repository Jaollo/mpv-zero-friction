# mpv.net Zero-Friction

A zero-friction video workstation config for [mpv.net](https://github.com/mpvnet-player/mpv.net) on Windows.

## Features

- **Drag-to-Pan** — Mouse1 panning with fail-safes and high-polling-rate support
- **Ghost Mode OSC** — Invisible bottom bar with fully active seek and controls
- **Double-Right-Click Quit** — Two right-clicks within 300ms to close
- **Mouse-Repeat** — Side buttons simulate key repeat for frame-by-frame scrubbing
- **Minimal UI** — Suppressed OSD, transparent OSC, one-handed right-side bindings

## Install

Copy to `%AppData%\mpv.net\`:

```
mpv.conf, input.conf          → root
scripts/*.lua                  → scripts/
```

## Files

| File | Purpose |
|---|---|
| `mpv.conf` | Engine settings, OSC config, OSD suppression |
| `input.conf` | Hardware bindings (8 sections, right-hand optimized) |
| `scripts/drag-to-pan.lua` | Mouse1 drag panning when zoomed in |
| `scripts/double-right-quit.lua` | Double-right-click quit |
| `scripts/mouse-repeat.lua` | Side button key repeat simulation |
| `scripts/osc.lua` | Modified OSC with ghost mode and color customization |

See [docs/](docs/) for architecture, Lua patterns, and system invariants. See [CLAUDE.md](CLAUDE.md) for AI agent conventions.
