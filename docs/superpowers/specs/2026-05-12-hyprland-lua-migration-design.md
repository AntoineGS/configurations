# Hyprland 0.55 Lua Configuration Migration

**Date:** 2026-05-12
**Status:** Design / pre-implementation
**Scope:** `Linux/hypr/` (the Hyprland compositor config tree only)

## Goal

Migrate the existing hyprlang-based Hyprland configuration to Lua, introduced
in Hyprland 0.55, with:

- **No behavioral changes** — every setting, bind, rule, env var, and animation
  remains semantically identical after the migration.
- **A 1:1 file structure mirror** of the current modular layout so that diffs
  remain reviewable and the mental model is unchanged.
- **Sibling Hypr\* configs left alone** — only the compositor itself supports
  Lua in 0.55; `hyprlock`, `hypridle`, `hyprsunset`, and `xdph` continue using
  hyprlang.

## Sources

- Release notes: <https://hypr.land/news/26_lua/>, <https://hypr.land/news/update55/>
- Example config: <https://github.com/hyprwm/Hyprland/blob/main/example/hyprland.lua>
- Wiki binds: <https://wiki.hypr.land/Configuring/Basics/Binds/>
- Wiki dispatchers: <https://wiki.hypr.land/Configuring/Basics/Dispatchers/>
- Hyprland source (authoritative for API surface):
  - `src/config/lua/bindings/LuaBindingsDispatchers.cpp`
  - `src/config/lua/bindings/LuaBindingsToplevel.cpp`
  - `src/config/lua/bindings/LuaBindingsConfigRules.cpp`
  - `src/config/lua/bindings/LuaBindingsRegistration.cpp`

## File Layout (after migration)

```
Linux/hypr/
├── hyprland.lua              # entry point, replaces hyprland.conf
├── autostart.lua             # exec-once via hl.on("hyprland.start", ...)
├── monitors.lua              # runtime hostname branching, replaces monitors.conf.tmpl
├── input.lua
├── envs.lua
├── windows.lua               # requires apps.lua
├── apps.lua                  # requires apps/*
├── looknfeel.lua
├── theme/
│   └── hyprland.lua
├── bindings/
│   ├── media.lua
│   ├── tiling.lua
│   ├── utilities.lua
│   └── apps.lua
├── apps/                     # 15 files, one per app (unchanged structure)
│   ├── 1password.lua
│   ├── bitwarden.lua
│   ├── browser.lua
│   ├── geforce.lua
│   ├── hyprshot.lua
│   ├── jetbrains.lua
│   ├── localsend.lua
│   ├── moonlight.lua
│   ├── pip.lua
│   ├── qemu.lua
│   ├── retroarch.lua
│   ├── steam.lua
│   ├── system.lua
│   ├── telegram.lua
│   ├── terminals.lua
│   └── webcam-overlay.lua
│
# unchanged (not Hyprland the compositor):
├── hyprlock.conf
├── hypridle.conf.tmpl (and symlink)
├── hyprsunset.conf
├── xdph.conf
├── hyprlandd.conf            # standalone TTY testing config
├── scripts/
├── shaders/
├── theme/hyprlock.conf
└── watch-rustdesk-submap.{service,sh}
```

### Files to delete

- `hyprland.conf`
- `autostart.conf`
- `monitors.conf` (symlink), `monitors.conf.tmpl`, `monitors.conf.tmpl.rendered`
- `input.conf`, `envs.conf`, `windows.conf`, `apps.conf`, `looknfeel.conf`
- `theme/hyprland.conf`
- `bindings/{media,tiling,utilities,apps}.conf`
- `apps/*.conf` (15 files)

The `*.conflict` artifact (`hypridle.conf.tmpl.conflict`) is unrelated and stays.

## API Reference (verified from Hyprland source)

### Top-level `hl.*`

| Function | Purpose |
|---|---|
| `hl.config({section = {...}})` | Set config blocks (`general`, `decoration`, `animations`, `dwindle`, `master`, `scrolling`, `misc`, `input`, `cursor`, `group`, `binds`, `xwayland`, `ecosystem`, `layout`) |
| `hl.monitor({output=, mode=, position=, scale=, mirror=, ...})` | Monitor config |
| `hl.env(name, value)` | Environment variable |
| `hl.workspace_rule({workspace=, monitor=, persistent=, default=, ...})` | Workspace rule |
| `hl.window_rule({name=, match={...}, ...})` | Window rule |
| `hl.layer_rule({name=, match={namespace=}, ...})` | Layer rule |
| `hl.device({name=, ...})` | Per-device config |
| `hl.gesture({fingers=, direction=, action=})` | Trackpad gesture |
| `hl.curve(name, {type="bezier", points={{x0,y0},{x1,y1}}})` | Define bezier or spring curve |
| `hl.animation({leaf=, enabled=, speed=, bezier=, style=})` | Animation override |
| `hl.permission(path, type, mode)` | Permission rule |
| `hl.bind(keys, dispatcher, opts)` | Keybind |
| `hl.unbind(keys, ...)` | Remove keybind |
| `hl.on(event, fn)` | Event handler (`"hyprland.start"`) |
| `hl.define_submap(name, [resetKey,] fn)` | Submap definition |
| `hl.dispatch(dispatcher)` | Invoke a dispatcher immediately |
| `hl.exec_cmd(cmd)` | Spawn a process |
| `hl.timer({timeout=, type=, callback=})` | Timer |

### Bind options table

`{repeating, locked, release, non_consuming, auto_consuming, transparent, ignore_mods, dont_inhibit, long_press, submap_universal, description (or desc), click, drag, mouse, device}`

### `hl.dsp.*` dispatchers (verified)

- **window**: `close`, `kill`, `signal`, `float`, `fullscreen`, `fullscreen_state`,
  `pseudo`, `move`, `swap`, `center`, `cycle_next`, `tag`, `clear_tags`,
  `toggle_swallow`, `pin`, `bring_to_top`, `alter_zorder`, `set_prop`,
  `deny_from_group`, `drag`, `resize`
- **workspace**: `rename`, `move`, `swap_monitors`, `toggle_special`
- **focus**: `focus({direction|monitor|workspace|window|urgent_or_last|last})`
- **group**: `toggle`, `next`, `prev`, `active`, `move_window`, `lock`,
  `lock_active`
- **cursor**: `move_to_corner`, `move`
- **top-level**: `exec_cmd`, `exec_raw`, `exit`, `submap`, `pass`,
  `send_shortcut`, `send_key_state`, `layout` (takes a string,
  e.g. `"togglesplit"`, `"swapwithmaster"`), `dpms`, `event`, `global`,
  `force_renderer_reload`, `force_idle`, `no_op`

## Translation Mappings (high-priority cases)

### Keybind flags (hyprlang suffix → Lua opts)

| Suffix | Meaning | Lua opts entry |
|---|---|---|
| `bind` | base | (none) |
| `bindd` | descriptive | `description = "..."` |
| `binde` | repeating | `repeating = true` |
| `bindl` | locked | `locked = true` |
| `bindm` | mouse | `mouse = true` |
| `bindr` | release | `release = true` |
| `bindeld` | e+l+d | `{repeating=true, locked=true, description="..."}` |
| `bindld` | l+d | `{locked=true, description="..."}` |
| `bindmd` | m+d | `{mouse=true, description="..."}` |

### Key string format

Modifiers and keys are joined by `+` (with optional spaces).

- `SUPER, Q` → `"SUPER + Q"`
- `SUPER SHIFT, F` → `"SUPER + SHIFT + F"`
- `SUPER, code:10` → `"SUPER + code:10"` (scancode passthrough confirmed in `parseKeyString`)
- empty mods + `XF86PowerOff` → `"XF86PowerOff"`
- `SUPER, mouse:272` → `"SUPER + mouse:272"` (with `{mouse=true}`)

### Dispatchers

| Hyprlang | Lua |
|---|---|
| `exec, X` | `hl.dsp.exec_cmd("X")` |
| `killactive` | `hl.dsp.window.close()` |
| `fullscreen, 0` | `hl.dsp.window.fullscreen({mode="fullscreen", action="toggle"})` |
| `fullscreen, 1` | `hl.dsp.window.fullscreen({mode="maximized", action="toggle"})` |
| `togglefloating` | `hl.dsp.window.float({action="toggle"})` |
| `pseudo` | `hl.dsp.window.pseudo()` |
| `workspace, N` | `hl.dsp.focus({workspace = N})` |
| `workspace, previous` | `hl.dsp.focus({workspace = "previous"})` |
| `workspace, e+1` / `m+1` | `hl.dsp.focus({workspace = "e+1"})` / `"m+1"` |
| `movetoworkspace, N` | `hl.dsp.window.move({workspace = N})` |
| `movefocus, l/r/u/d` | `hl.dsp.focus({direction = "left"/"right"/"up"/"down"})` |
| `movewindow, l/r/u/d` | `hl.dsp.window.move({direction = "..."})` |
| `swapwindow, l/r/u/d` | `hl.dsp.window.swap({direction = "..."})` |
| `cyclenext` | `hl.dsp.window.cycle_next()` |
| `cyclenext, prev` | `hl.dsp.window.cycle_next({prev = true})` — **VERIFY** |
| `bringactivetotop` | `hl.dsp.window.bring_to_top()` |
| `resizeactive, X Y` | `hl.dsp.window.resize({x=X, y=Y, relative=true})` |
| `movewindow` (drag) | `hl.dsp.window.drag()` |
| `resizewindow` (drag) | `hl.dsp.window.resize()` (no args) |
| `togglespecialworkspace, X` | `hl.dsp.workspace.toggle_special("X")` |
| `togglesplit` | `hl.dsp.layout("togglesplit")` |
| `layoutmsg, X Y Z` | `hl.dsp.layout("X Y Z")` |
| `submap, X` | `hl.dsp.submap("X")` |
| `submap, reset` | `hl.dsp.submap("reset")` |
| `movecurrentworkspacetomonitor, l/r` | `hl.dsp.workspace.move({monitor = "l"/"r"})` |

### Window-rule fields

The hyprlang v1 form `windowrule = field value, match:X Y` becomes:

```lua
hl.window_rule({
    match = { X = "Y" },
    field = value,
})
```

The hyprlang v2 form `windowrule { name=...; match:class=...; rule=value }` becomes:

```lua
hl.window_rule({
    name = "...",
    match = { class = "..." },
    rule = value,
})
```

Rule field names appear to map snake_case 1:1 from hyprlang (`no_focus`,
`no_screen_share`, `idle_inhibit`, `stay_focused`, `border_size`, `min_size`,
`keep_aspect_ratio`, `border_size`, `no_initial_focus`, `no_anim`, `no_dim`,
`no_follow_mouse`, `tag`, `opacity`, `move`, `size`, `center`, `float`,
`pin`, `fullscreen`, `workspace`, `animation`).

**Unverified rule fields** (no example coverage):

- `scroll_touchpad <N>` — used in `input.lua` and `apps/system.lua`. If Lua
  rejects this at runtime, fall back to a shell `hyprctl keyword` invocation or
  document the regression.
- `opacity` with two numbers — represented in hyprlang as `opacity 0.97 0.9`;
  in Lua likely either `opacity = "0.97 0.9"` (string passthrough) or
  `opacity = {0.97, 0.9}`. Will try string first.

### Variables

Hyprlang `$var` becomes Lua `local var`. Where a `$var` is referenced across
files (e.g. `$activeBorderColor` referenced in both `theme/hyprland.lua` and
`looknfeel.lua`), the variable is duplicated in each file (Lua module scope is
file-local; `require` returns are not threaded through current files). This is
acceptable because the value is a constant.

`$osdclient = swayosd-client --monitor "$(hyprctl monitors -j | jq ...)"` — the
`$()` shell substitution still works because `hl.exec_cmd` spawns through a
shell. Pure string variable.

### `exec-once`

```lua
hl.on("hyprland.start", function()
    hl.exec_cmd("uwsm-app -- hypridle")
    hl.exec_cmd("uwsm-app -- mako")
    -- ... preserving original order
end)
```

### Submaps

```lua
-- Enter submap:
hl.bind("SUPER + R", hl.dsp.submap("resize"))

hl.define_submap("resize", function()
    hl.bind("l", hl.dsp.window.resize({x=10, y=0, relative=true}), {repeating=true})
    hl.bind("h", hl.dsp.window.resize({x=-10, y=0, relative=true}), {repeating=true})
    hl.bind("k", hl.dsp.window.resize({x=0, y=-10, relative=true}), {repeating=true})
    hl.bind("j", hl.dsp.window.resize({x=0, y=10, relative=true}), {repeating=true})
    hl.bind("escape", hl.dsp.submap("reset"))
end)
```

The `clean` submap (used to disable most keybinds, currently used by
RustDesk auto-switch) is translated similarly.

## Per-File Migration Plan

### `hyprland.lua` (entry point)

```lua
require("autostart")
require("monitors")
require("input")
require("envs")
require("theme.hyprland")
require("looknfeel")
require("windows")
require("bindings.media")
require("bindings.tiling")
require("bindings.utilities")
require("bindings.apps")

hl.env("GTK_USE_PORTAL", "0")
hl.env("NVD_BACKEND", "direct")
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
```

### `monitors.lua` (host-conditional)

Hostname detected via `io.popen("hostname"):read("*l")`. Branches on
`omarchbook` vs. desktop, producing the same final set of `hl.monitor`,
`hl.workspace_rule`, and `hl.window_rule` calls as today's rendered template.

### `autostart.lua`

Single `hl.on("hyprland.start", function() ... end)` block containing
all original `exec-once` lines in their existing order. The `sleep N && ...`
shell commands run through `hl.exec_cmd` which uses a shell — behavior
preserved.

### `bindings/tiling.lua`

Most binds straightforward. Two submaps (`resize` for arrow-key resizing,
`clean` for disable-most-keybinds during RustDesk) translated via
`hl.define_submap`. The `code:N` numeric-key bindings for workspace switching
pass through unchanged.

### `looknfeel.lua`

Largest file. Strategy: one `hl.config({...})` call per top-level block
(general, decoration, animations enabled, dwindle, master, misc, cursor,
binds, layout); curves via `hl.curve()`; per-leaf animation overrides via
`hl.animation()`. Where hyprlang defines `animation = border` twice, only
the second value is materialized in Lua (the same end-state hyprlang reaches).
Local color variables (`activeBorderColor`, `inactiveBorderColor`) preserved
as Lua locals.

### `theme/hyprland.lua`

Just `hl.config({general = {col = {active_border = "..."}}, group = {col = {border_active = "..."}}})`.

### `envs.lua`

A sequence of `hl.env(name, value)` calls plus
`hl.config({xwayland = {force_zero_scaling = true}})` and
`hl.config({ecosystem = {no_update_news = true}})`.

### `input.lua`

`hl.config({input = {...}})` with the kb_*, repeat_*, follow_mouse,
sensitivity, numlock_by_default, touchpad sub-table settings.
`hl.config({misc = {key_press_enables_dpms = true, mouse_move_enables_dpms = true}})`.
Two `hl.window_rule` calls for terminal scroll factors.

### `windows.lua`

```lua
hl.window_rule({name = "suppress-maximize", match = {class = ".*"}, suppress_event = "maximize"})
hl.window_rule({name = "default-opacity-tag", match = {class = ".*"}, tag = "+default-opacity"})
hl.window_rule({name = "fix-xwayland-drags", match = {class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false}, no_focus = true})
require("apps")
hl.window_rule({name = "apply-default-opacity", match = {tag = "default-opacity"}, opacity = "0.97 0.9"})
```

### `apps.lua` and `apps/*.lua`

`apps.lua` is a `require()` chain mirroring today's `source =` list.
Each `apps/X.lua` is a direct translation of its `.conf` counterpart.

### `bindings/media.lua`

```lua
local osdclient = [[swayosd-client --monitor "$(hyprctl monitors -j | jq -r '.[] | select(.focused == true).name')"]]

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(osdclient .. " --output-volume raise"),
    {locked = true, repeating = true, description = "Volume up"})
-- ...etc
```

### `bindings/utilities.lua`

Mostly `hl.bind(..., hl.dsp.exec_cmd("..."), {description = "..."})`.
The `setprop` toggle is kept as a shell command (string includes `$()` and
`hyprctl`) for safety since `hl.dsp.window.set_prop` requires literal values.

### `bindings/apps.lua`

Same pattern as `utilities.lua`. The `##` escape for `#` in URLs is no
longer needed in Lua strings (no comment parsing), but values that don't
contain `#` can stay either way.

## Risks and Unknowns

1. **`hl.dsp.window.cycle_next` argument for previous direction.** Source
   shows the function exists but signature for "prev" isn't confirmed.
   Will check the example or wiki during implementation; fallback is
   `hl.dsp.exec_cmd("hyprctl dispatch cyclenext prev")`.

2. **`scroll_touchpad` window-rule field.** Not in the official example. If
   it rejects, fall back to dispatcher-based scroll handling or remove.

3. **`opacity 0.97 0.9` two-arg form.** Try `opacity = "0.97 0.9"` first;
   fall back to `{0.97, 0.9}` if rejected.

4. **`no_screen_share`, `idle_inhibit`, `no_dim`, `no_anim`, `no_follow_mouse`,
   `no_initial_focus`, `stay_focused`, `keep_aspect_ratio`.** Assumed
   identical snake_case names. Will verify against runtime errors.

5. **Submap fall-through reset.** Hyprlang `submap = reset` exits to the
   global submap. Lua `hl.dsp.submap("reset")` should do the same — the
   example file shows this pattern.

6. **`hl.config` is additive.** Calling `hl.config({general = {gaps_in = 4}})`
   then `hl.config({general = {border_size = 2}})` should merge, not
   overwrite. The example file makes multiple `hl.config` calls so this is
   the expected pattern.

7. **`tag` field accepting `+name` / `-name` syntax.** Verified in the
   example (`tag = "+default-opacity"` is implied by hyprlang `tag +X`).
   If `tag = "+X"` doesn't work, the alternative is a `tags` array.

## Verification Strategy

After implementing each file:

1. **`luac -p file.lua`** — confirms the file is syntactically valid Lua.
   Run on every migrated file before committing.

2. **Audit pass** — for each old `.conf`, manually verify every directive
   has a Lua equivalent. Diff-style review.

3. **Runtime test (user)** — after committing, you `hyprctl reload` (or
   restart the session) and walk a checklist:
   - All monitors come up correctly on your host.
   - Workspaces land on the right monitors.
   - Autostart processes spawn.
   - Every keybind in your daily workflow.
   - Each submap (resize, clean) enters and exits.
   - Window rules: jetbrains popups, browser opacity, terminals,
     screenshot screenshots, etc.

Any runtime errors land in Hyprland's stderr / its log file
(`~/.cache/hyprland/hyprland.log` typically).

## Out of Scope

- `hyprlock.conf`, `hypridle.conf.tmpl`, `hyprsunset.conf`, `xdph.conf` —
  separate programs, separate config languages, no Lua support in 0.55.
- `hyprlandd.conf` — your standalone TTY testing config; remains hyprlang.
- `scripts/`, `shaders/`, `theme/hyprlock.conf` — non-Hyprland-config assets.
- Behavioral improvements, refactors, or new features. **No behavioral
  changes** is a hard goal.
- `tidydots.yaml` does not need changes: the mapping symlinks the whole
  `Linux/hypr/` directory, so adding `.lua` files and removing `.conf`
  files is transparent to it.

## Implementation Order

1. Create the design (this file) and get user approval.
2. Write the spec / implementation plan as a separate document (via
   `writing-plans` skill) with a step-by-step task breakdown.
3. Implement file-by-file in roughly the order listed under "Per-File
   Migration Plan", running `luac -p` after each.
4. Delete the old `.conf` files in the final commit.
5. User runtime verification.
