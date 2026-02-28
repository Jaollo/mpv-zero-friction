# Invariants

Guardrails checklist. If any invariant is violated, the system breaks in the specific way documented here. Check this before modifying any file.

## mpv.conf Mandatory Settings

| Invariant | Location | What breaks if changed |
|---|---|---|
| `window-dragging=no` | `mpv.conf` line 4 | mpv's C++ layer intercepts `MBTN_LEFT` before any Lua script sees it. drag-to-pan.lua never receives mouse events. Panning stops working entirely. |
| `osc=no` | `mpv.conf` line 7 | mpv loads its built-in C++ OSC instead of `scripts/osc.lua`. Ghost mode, color customization, custom button commands, and drag-to-pan forwarding all disappear. The built-in OSC has no `drag-to-pan-event` messaging. |
| `osd-on-seek=no` | `mpv.conf` line 23 | Seek operations display a large OSD bar/timestamp overlay. Breaks the "zero-friction" minimal UI since every frame step or seek shows visual noise. |
| `osd-bar=no` | `mpv.conf` line 17 | A large graphical volume bar renders in the center of the screen on volume/seek changes. Obstructs the video. |
| All OSC opts on one `script-opts=` line | `mpv.conf` line 26 | mpv only reads the **last** `script-opts=` line. If split across multiple lines, earlier options are silently ignored. Ghost mode, layout, and scaling would use wrong defaults. |

## Binding Priority Requirements

| Invariant | Location | What breaks if changed |
|---|---|---|
| drag-to-pan binds `mbtn_left` via input.conf `script-binding` (Tier 1), not script-level or forced | `input.conf` section 7, `drag-to-pan.lua` line 139 | If changed to Tier 2 (script-level `mp.add_key_binding("mbtn_left", ...)`), the script consumes `mbtn_left` before mpv's input layer can form `MBTN_LEFT+WHEEL` combos. Zoom-while-dragging stops working. If changed to forced (Tier 4), it overrides OSC's bar area handler and seeking breaks. |
| OSC's "input" group uses `"force"` flag | `osc.lua` line 2820 | Without `"force"`, the OSC's `mbtn_left` binding is Tier 2 — same priority as script-level bindings. The winner becomes load-order-dependent and unpredictable. Seeking may randomly work or not work depending on which script loads first. |
| drag-to-pan uses `add_forced_key_binding` for `mouse_move` and `mbtn_left_up` during active drag | `drag-to-pan.lua` lines 120-123 | Without forced bindings during drag, mouse move events may be consumed by OSC's forced `mouse_move` group. Dragging becomes unreliable — the pan jumps or stops tracking. |
| Forced drag bindings are removed on termination | `drag-to-pan.lua` lines 126-128 | If forced bindings leak (not removed), they permanently override OSC's `mouse_move` handling. The OSC never sees mouse movement, so it never shows/hides. Mouse cursor auto-hide also breaks. |

## Zoom-Toward-Cursor Requirements

| Invariant | Location | What breaks if changed |
|---|---|---|
| Zoom bindings use input.conf `script-binding` (Tier 1), not direct `add video-zoom` | `input.conf` section 4, `zoom-toward-cursor.lua` lines 60-61 | If zoom bindings bypass the script (e.g., `no-osd add video-zoom 0.05`), zoom drifts toward video center instead of the cursor position. If `MBTN_LEFT+WHEEL` combos are moved to Tier 2 script-level bindings, combo detection breaks — same root cause as the drag-to-pan binding tier invariant. |
| Pan resets to 0 when zoom transitions from positive to <= 0 | `zoom-toward-cursor.lua` lines 23-27 | If pan is not reset on zoom-out past zero, the video stays offset from center at zero zoom. The user sees a shifted frame with no way to correct it (panning has no visual effect at zoom <= 0). |
| Zoom bindings have `{repeatable = true}` | `zoom-toward-cursor.lua` lines 60-61 | Without `repeatable`, holding `z`/`x` keys or rapid scroll-wheel events only fire once. Continuous zoom-in/out requires lifting and re-pressing the key or re-scrolling. |

## Inter-Script Message Contracts

| Invariant | Location | What breaks if changed |
|---|---|---|
| OSC sends `drag-to-pan-event "up"` on **every** `mbtn_left` release | `osc.lua` lines 2345-2346 | If the "up" is only sent conditionally (e.g., only when a drag was active), then drags started via the OSC's forwarded "down" may never terminate. The user would be stuck in permanent drag mode after clicking in the bar area while zoomed. |
| OSC sends `drag-to-pan-event "down"` only when **no element** was hit | `osc.lua` lines 2320-2322 | If sent unconditionally, every seekbar click or button press would also start a drag. The user would pan instead of seeking. |
| double-right-quit sends `drag-to-pan-event "cancel"` on every right-click | `double-right-quit.lua` line 13 | If removed, right-clicking during an active drag doesn't cancel the drag. The user must release `mbtn_left` to stop dragging — the right-click quit gesture becomes difficult to trigger while zoomed and dragging. |
| Message name is exactly `drag-to-pan-event` | All three scripts | If renamed in one script but not others, the IPC link breaks silently. mpv doesn't error on undelivered script-messages. Drags from OSC forwarding stop working, or right-click cancel stops working, with no error message. |

## Ghost Mode Rendering Rules

| Invariant | Location | What breaks if changed |
|---|---|---|
| Ghost mode forces `visibility=always` | `osc.lua` line 2856 | If visibility is allowed to be `auto` in ghost mode, the invisible bar area deactivates when the mouse is idle. Seeking and buttons become unreachable until the user moves the mouse enough to trigger show_osc(). Defeats the purpose of ghost mode. |
| Ghost mode bar height is 224px | `osc.lua` line 1559 (`user_opts.ghostmode and 224 or 56`) | If reduced, the invisible hit area becomes too small — users must aim precisely at the narrow bottom strip to seek. If increased, the invisible bar consumes too much of the video area and steals clicks that should go to drag-to-pan. |
| Ghost mode suppresses `render_elements()` | `osc.lua` line 2581 | If elements are rendered in ghost mode, the "invisible" bar becomes visible. The entire point of ghost mode — an active but invisible UI — is defeated. |
| Ghost mode suppresses OSD messages for visibility/idle changes | `osc.lua` lines 2875, 2907 | If OSD messages fire in ghost mode, toggling visibility shows "OSC visibility: always" text on screen, which is confusing since nothing visible changed. |
| `minmousemove=0` in script-opts | `mpv.conf` line 26 | If `minmousemove > 0`, the OSC requires the mouse to move at least that many pixels before triggering show_osc(). In ghost mode this doesn't affect visibility (forced always), but in non-ghost mode it adds dead zones where mouse movement is ignored. |

## OSC Forced Binding Group Requirements

| Invariant | Location | What breaks if changed |
|---|---|---|
| "input" group includes `mbtn_left_dbl` → `"ignore"` | `osc.lua` line 2817 | Without this, double-clicking `mbtn_left` triggers mpv's default fullscreen toggle. This conflicts with drag-to-pan (a fast click-release-click looks like a double-click to mpv). |
| "input" group is always enabled | `osc.lua` line 2821 | If disabled, the OSC loses all mouse input. No seeking, no buttons, no drag-to-pan forwarding inside the bar area. |
| "showhide" groups use `"allow-vo-dragging+allow-hide-cursor"` flags | `osc.lua` line 2380 | Without these flags, the forced `mouse_move` binding blocks mpv's cursor auto-hide. The cursor would stay visible permanently. |

## drag-to-pan State Machine

| Invariant | Location | What breaks if changed |
|---|---|---|
| `force_drag_termination()` is idempotent | `drag-to-pan.lua` lines 27-36 | If calling it twice causes errors (e.g., removing already-removed bindings), then the fail-safe pattern breaks. Multiple kill-switch triggers (mouse-leave + up event + zoom observer) would crash instead of safely no-oping. |
| Zoom observer calls `force_drag_termination()` when zoom <= 0 | `drag-to-pan.lua` lines 149-153 | If removed, resetting zoom to 0 (via `Shift+LEFT`) while dragging leaves the drag active with forced bindings. The user is stuck in drag mode with no way to pan (zoom is 0) and forced bindings block normal mouse interaction. |
| Ghost-state annihilation on re-press | `drag-to-pan.lua` line 46 | The handler calls `force_drag_termination()` at the start of every "down" event, even if no drag is active. If removed, a second `mbtn_left` press while a ghost drag is stuck would layer a new drag on top of the old one, leaking forced bindings and idle callbacks. |
