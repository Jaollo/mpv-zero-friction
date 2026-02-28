# mpv.net Zero-Friction Config

A highly optimized configuration and script collection for mpv.net, designed for
a "Zero-Friction" video workstation experience.

## Key Features

- **Drag-to-Pan**: Robust mouse-based panning with high-polling rate support and
  complex binding fail-safes.
- **Mouse-Repeat**: Simulated key-repeat for side mouse buttons, enabling smooth
  frame-by-frame scrubbing.
- **Minimal UI**: Transparent, glass-morphic OSC and suppressed OSD clutter for
  maximum focus.
- **Custom Bindings**: Optimized hardware mappings for one-handed operation.

## Installation

1. Copy `mpv.conf` and `input.conf` to your `AppData\Roaming\mpv.net\` folder.
2. Copy the contents of the `scripts/` folder to
   `AppData\Roaming\mpv.net\scripts\`.

## Files

- `mpv.conf`: Core engine settings and UI suppression.
- `input.conf`: High-performance hardware event remapping.
- `scripts/drag-to-pan.lua`: Coordinate-aware panning logic.
- `scripts/mouse-repeat.lua`: Frame-stepping timer logic.
- `scripts/osc.lua`: Custom minimal On-Screen Controller.
