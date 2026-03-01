# Zero-Friction v0.6

Drag to pan, scroll to zoom, click to seek — no menus, no toolbar, no second hand needed.

## Install

Copy to `%AppData%\mpv.net\`:

```
mpv.conf, input.conf, mpvnet.conf  → root
scripts/*.lua                      → scripts/
```

## Bindings

| Input | Action |
|---|---|
| Mouse1 drag | Pan when zoomed |
| Mouse2 | Mute |
| Mouse3 | Pause / double-click quit |
| Mouse4 / Mouse5 | Frame step (hold to repeat) |
| Scroll wheel | Zoom toward cursor |
| Top-right corner | Quit (invisible 90px zone) |
| ← → | Frame step |
| , . | Seek ±2s |
| ↑ ↓ | Speed ±0.05x |
| Z / X | Zoom in/out |
| Shift+← | Reset zoom |
| m / M | AB-loop / loop file |
| ' | Crop to 9:16 |
| RCtrl / - / p | Pause / mute |
| ESC | Quit |

The bottom seekbar is invisible but active — click the bottom of the screen to seek.

## Known Issues

The seekbar breaks after aggressive zoom+pan. Workaround: ESC or top-right corner to quit and reopen.

## Contributing

Ideas and PRs welcome. Hotkey ideas for less friction are encouraged — try different variations and share what works for your workflow. The v1.0 blocker is fixing the seekbar desync in osc.lua. An MMO mouse binding layout would also be interesting.

## License

Public domain. `scripts/osc.lua` retains its original license (GPLv2+).
