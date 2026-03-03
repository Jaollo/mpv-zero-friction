# Zero-Friction v0.7

Drag to move, scroll to volume, click to seek — no menus, no toolbar, no second hand needed.

## Install

Copy to `%AppData%\mpv.net\`:

```
mpv.conf, input.conf, mpvnet.conf  → root
scripts/*.lua                      → scripts/
```

## Bindings

| Input | Action |
|---|---|
| Mouse1 drag | Move window |
| Mouse2 | Quit |
| Mouse3 | Pause / double-click quit |
| Mouse4 / Mouse5 | Frame step (hold to repeat) |
| Scroll wheel | Volume ±2 |
| Top-right corner | Quit (invisible 90px zone) |
| ← → | Frame step |
| , . | Seek ±2s |
| ↑ ↓ | Speed ±0.05x |
| m / M | AB-loop / loop file |
| ' | Crop to 9:16 |
| RCtrl / - | Pause |
| p | Mute |
| ESC | Quit |

The bottom seekbar is invisible but active — click the bottom of the screen to seek.

## License

Public domain. `scripts/osc.lua` retains its original license (GPLv2+).
