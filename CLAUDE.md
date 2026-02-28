# CLAUDE.md

Canonical technical reference for AI agents (Claude Code, GitHub Copilot) working on this codebase.

## Project Overview

mpv-zero-friction is a config + Lua script collection for **mpv.net** (Windows), designed as a zero-friction video workstation. No build step, no tests, no linter. The repo root contains pre-built mpv.net binaries — **never modify** `.exe`, `.dll`, or `.com` files.

## Deployment

All config and script files deploy to `%AppData%\mpv.net\`:

| Source | Target |
|---|---|
| `mpv.conf`, `input.conf` | root of AppData folder |
| `scripts/*.lua` | `scripts/` subfolder |

After editing any file, **always copy it to the AppData target**. mpv.net reads only from AppData, not from this repo directory. Restart mpv.net to pick up changes.

## Documentation

Detailed reference docs live in `docs/`:

| Doc | Purpose |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System index — file inventory, binding priority stack, inter-script communication, OSC render pipeline, MBTN_LEFT click routing |
| [docs/LUA-PATTERNS.md](docs/LUA-PATTERNS.md) | Style guide — required patterns for new scripts, PiL pattern catalog, timer/binding patterns, anti-patterns |
| [docs/INVARIANTS.md](docs/INVARIANTS.md) | Guardrails — invariant checklist with "what breaks if changed" for every critical setting |

## Coding Conventions

- **PiL references**: Comments cite Programming in Lua chapter numbers (e.g., `-- Ch 16.4: Closure-based privacy`)
- **`do...end` blocks**: Custom scripts wrap everything in a `do...end` block for namespace isolation
- **Local caching**: Cache `mp.get_mouse_pos`, `mp.get_osd_size`, `math.min`, `math.max` etc. as locals at script top
- **Variable naming**: `drag.*` (state fields), `dx`/`dy` (deltas), `osd_w`/`osd_h` (screen dimensions)
- **OSC config**: All options on a single `script-opts=` line. Custom colors use `#RRGGBB` hex validated by `^#%x%x%x%x%x%x$`
- **input.conf sections**: 8 numbered comment headers. Add new bindings to the appropriate section

## Debugging

1. Edit the `.lua` file
2. Restart mpv.net (no hot-reload)
3. Press `Shift+I` to view script console for errors

mpv Lua API docs: https://mpv.io/manual/master/#lua-scripting
