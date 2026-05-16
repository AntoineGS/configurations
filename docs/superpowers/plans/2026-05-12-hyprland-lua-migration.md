# Hyprland 0.55 Lua Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the Hyprland compositor configuration from hyprlang to Lua (introduced in Hyprland 0.55) with no behavioral changes.

**Architecture:** 1:1 file structure mirror. Every `.conf` becomes a `.lua` with the same name and responsibility. `hyprland.lua` requires modules in the same order as today's `source =` chain. Host-specific monitor branching moves from the tidydots `.tmpl` to Lua runtime via `io.popen("hostname")`.

**Tech Stack:** Lua 5.4 (Hyprland-embedded runtime), Hyprland 0.55+ Lua API (`hl.*` globals from `src/config/lua/bindings/`).

**Spec reference:** [`docs/superpowers/specs/2026-05-12-hyprland-lua-migration-design.md`](../specs/2026-05-12-hyprland-lua-migration-design.md)

**Verification limitation:** This environment cannot run `hyprctl reload`. Per-file verification is syntactic (`luac -p`) plus a diff audit against the original `.conf`. End-to-end behavioral verification requires the user to reload Hyprland.

**Rollback:** Each task is a single commit. If any reload reveals a regression, `git revert <commit-sha>` restores the matching `.conf` files for that task. The full migration is reversible up to the cleanup commit (Task 17), which deletes the old `.conf` files — keep this commit last for easy rollback.

---

## File Plan

**Files to create** (target Lua files):

```
Linux/hypr/
├── hyprland.lua
├── autostart.lua
├── monitors.lua
├── input.lua
├── envs.lua
├── windows.lua
├── apps.lua
├── looknfeel.lua
├── theme/hyprland.lua
├── bindings/{media,tiling,utilities,apps}.lua
└── apps/{1password,bitwarden,browser,geforce,hyprshot,jetbrains,
        localsend,moonlight,pip,qemu,retroarch,steam,system,
        telegram,terminals,webcam-overlay}.lua
```

**Files to delete (final cleanup commit):**

```
Linux/hypr/
├── hyprland.conf
├── autostart.conf
├── monitors.conf (symlink), monitors.conf.tmpl, monitors.conf.tmpl.rendered
├── input.conf, envs.conf, windows.conf, apps.conf, looknfeel.conf
├── theme/hyprland.conf
├── bindings/{media,tiling,utilities,apps}.conf
└── apps/*.conf (16 files)
```

**Files NOT touched** (separate programs):

- `hyprlock.conf`, `hypridle.conf.tmpl` (+ symlink + rendered + conflict), `hyprsunset.conf`, `xdph.conf`, `hyprlandd.conf`, `scripts/*`, `shaders/*`, `theme/hyprlock.conf`, `watch-rustdesk-submap.{service,sh}`.

---

## Task 0: Verify Lua tooling is available

**Files:** none

- [ ] **Step 1: Confirm `luac` exists**

Run: `which luac && luac -v`
Expected: a path like `/usr/bin/luac` and a version line like `Lua 5.4.x`.

If `luac` is missing, install it: `sudo pacman -S lua` (Arch).

- [ ] **Step 2: Confirm working directory**

Run: `pwd`
Expected: `/home/antoinegs/gits/configurations`

All file paths in this plan are relative to that directory.

---

## Task 1: Create `hyprland.lua` (entry point)

The new top-level entry. Mirrors the require order to today's `source =` chain in `hyprland.conf`. Requires don't resolve at write-time (Lua loads modules lazily), so we can write this first even though the required modules don't exist yet.

**Files:**
- Create: `Linux/hypr/hyprland.lua`

- [ ] **Step 1: Write `Linux/hypr/hyprland.lua`**

```lua
-- Hyprland 0.55+ Lua entrypoint. Mirrors the source-chain that hyprland.conf used.
-- Wiki: https://wiki.hypr.land/Configuring/Start/

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

-- Bypass GTK portal for URI opening (enables custom URI scheme handlers)
hl.env("GTK_USE_PORTAL", "0")

-- NVIDIA environment variables
hl.env("NVD_BACKEND", "direct")
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
```

- [ ] **Step 2: Syntax check**

Run: `luac -p Linux/hypr/hyprland.lua`
Expected: no output (success). Non-zero exit / error message = stop and fix.

- [ ] **Step 3: Commit**

```bash
git add Linux/hypr/hyprland.lua
git commit -m "feat(hypr): add lua entrypoint (0.55 migration)"
```

---

## Task 2: Create `envs.lua`

Source: `Linux/hypr/envs.conf`. Pure env-var declarations plus two config blocks (`xwayland`, `ecosystem`).

**Files:**
- Create: `Linux/hypr/envs.lua`

- [ ] **Step 1: Write `Linux/hypr/envs.lua`**

```lua
-- Cursor size
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Force all apps to use Wayland
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_STYLE_OVERRIDE", "kvantum")
hl.env("SDL_VIDEODRIVER", "wayland,x11")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
hl.env("OZONE_PLATFORM", "wayland")
hl.env("XDG_SESSION_TYPE", "wayland")

-- Allow better support for screen sharing (Google Meet, Discord, etc)
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

hl.config({
    xwayland = {
        force_zero_scaling = true,
    },
})

-- Use XCompose file
hl.env("XCOMPOSEFILE", "~/.XCompose")

-- Don't show update on first launch
hl.config({
    ecosystem = {
        no_update_news = true,
    },
})
```

- [ ] **Step 2: Syntax check**

Run: `luac -p Linux/hypr/envs.lua`
Expected: no output.

- [ ] **Step 3: Audit against original**

Run: `cat Linux/hypr/envs.conf` and verify every directive (env, xwayland, ecosystem) has a Lua equivalent above. Count: 13 envs, 1 xwayland block, 1 ecosystem block.

- [ ] **Step 4: Commit**

```bash
git add Linux/hypr/envs.lua
git commit -m "feat(hypr): migrate envs to lua"
```

---

## Task 3: Create `theme/hyprland.lua`

Source: `Linux/hypr/theme/hyprland.conf`. Tiny — one variable, two config blocks.

**Files:**
- Create: `Linux/hypr/theme/hyprland.lua`

- [ ] **Step 1: Write `Linux/hypr/theme/hyprland.lua`**

```lua
local activeBorderColor = "rgb(89b4fa)"

hl.config({
    general = {
        col = {
            active_border = activeBorderColor,
        },
    },
    group = {
        col = {
            border_active = activeBorderColor,
        },
    },
})
```

- [ ] **Step 2: Syntax check**

Run: `luac -p Linux/hypr/theme/hyprland.lua`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add Linux/hypr/theme/hyprland.lua
git commit -m "feat(hypr): migrate theme/hyprland to lua"
```

---

## Task 4: Create `input.lua`

Source: `Linux/hypr/input.conf`. Input config block + misc DPMS wake + two terminal scroll window rules.

**Files:**
- Create: `Linux/hypr/input.lua`

- [ ] **Step 1: Write `Linux/hypr/input.lua`**

```lua
-- Control your input devices
-- See https://wiki.hypr.land/Configuring/Variables/#input
hl.config({
    input = {
        kb_layout  = "us",
        kb_variant = "intl",
        kb_options = "compose:caps",
        kb_model   = "",
        kb_rules   = "",

        repeat_rate  = 40,
        repeat_delay = 600,

        numlock_by_default = false,

        follow_mouse = 1,
        sensitivity  = 0,

        touchpad = {
            scroll_factor  = 0.4,
            natural_scroll = false,
        },
    },
})

-- Scroll nicely in the terminal
hl.window_rule({
    match = { class = "(Alacritty|kitty)" },
    scroll_touchpad = 1.5,
})
hl.window_rule({
    match = { class = "com.mitchellh.ghostty" },
    scroll_touchpad = 0.2,
})

hl.config({
    misc = {
        key_press_enables_dpms  = true, -- key press will trigger wake
        mouse_move_enables_dpms = true, -- mouse move will trigger wake
    },
})
```

- [ ] **Step 2: Syntax check**

Run: `luac -p Linux/hypr/input.lua`
Expected: no output.

- [ ] **Step 3: Audit against original**

Run: `cat Linux/hypr/input.conf`. Confirm every active (non-commented) directive maps.

- [ ] **Step 4: Commit**

```bash
git add Linux/hypr/input.lua
git commit -m "feat(hypr): migrate input to lua"
```

---

## Task 5: Create `autostart.lua`

Source: `Linux/hypr/autostart.conf`. All `exec-once` lines wrapped in a single `hl.on("hyprland.start", ...)` to preserve startup ordering. Shell quoting must match exactly (the `hyprctl --batch` chain is sensitive to it).

**Files:**
- Create: `Linux/hypr/autostart.lua`

- [ ] **Step 1: Write `Linux/hypr/autostart.lua`**

```lua
-- Autostart processes. Order matches the original autostart.conf exec-once chain.

hl.on("hyprland.start", function()
    hl.exec_cmd("uwsm-app -- hypridle")
    hl.exec_cmd("uwsm-app -- mako")
    hl.exec_cmd("uwsm-app -- waybar")
    hl.exec_cmd("uwsm-app -- fcitx5 --disable notificationitem")
    hl.exec_cmd("uwsm-app -- swaybg -i ~/.config/omarchy/current/background -m fill")
    hl.exec_cmd("uwsm-app -- swayosd-server")
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")

    -- Slow app launch fix -- set systemd vars
    hl.exec_cmd("systemctl --user import-environment $(env | cut -d'=' -f 1)")
    hl.exec_cmd("dbus-update-activation-environment --systemd --all")

    -- Extra autostart processes
    hl.exec_cmd("hyprpm reload -n")
    hl.exec_cmd("signal")
    hl.exec_cmd("teams-for-linux")
    hl.exec_cmd("vicinae server")

    -- Ensure all persistent workspaces are on correct monitors
    hl.exec_cmd([[sleep 1 && hyprctl --batch "dispatch moveworkspacetomonitor 1 DVI-D-1 ; dispatch moveworkspacetomonitor 4 DVI-D-1 ; dispatch moveworkspacetomonitor 7 DVI-D-1 ; dispatch moveworkspacetomonitor 2 HDMI-A-1 ; dispatch moveworkspacetomonitor 5 HDMI-A-1 ; dispatch moveworkspacetomonitor 8 HDMI-A-1 ; dispatch moveworkspacetomonitor 3 DP-2 ; dispatch moveworkspacetomonitor 6 DP-2 ; dispatch moveworkspacetomonitor 9 DP-2 ; dispatch moveworkspacetomonitor 10 DP-2 ; dispatch workspace 2"]])

    -- Hyprland 0.55 regression: cursor can't enter DP-2's region until the monitor is re-applied. Drop once upstream fixes it.
    hl.exec_cmd([[sleep 2 && hyprctl keyword monitor "DP-2, 1920x1080@60, 3601x0, 1" && hyprctl keyword monitor "DP-2, 1920x1080@60, 3600x0, 1"]])
end)
```

- [ ] **Step 2: Syntax check**

Run: `luac -p Linux/hypr/autostart.lua`
Expected: no output.

- [ ] **Step 3: Audit against original**

Run: `grep -c "^exec-once" Linux/hypr/autostart.conf` — expected: 16. Then count `hl.exec_cmd` calls in the new file: `grep -c "hl.exec_cmd" Linux/hypr/autostart.lua` — must also be 16.

- [ ] **Step 4: Commit**

```bash
git add Linux/hypr/autostart.lua
git commit -m "feat(hypr): migrate autostart to lua"
```

---

## Task 6: Create `monitors.lua`

Source: `Linux/hypr/monitors.conf.tmpl`. The tidydots host branching becomes Lua runtime branching. The desktop branch produces 4 monitors, 10 workspace rules, and 7 windowrule defaults.

**Files:**
- Create: `Linux/hypr/monitors.lua`

- [ ] **Step 1: Write `Linux/hypr/monitors.lua`**

```lua
-- Monitor + persistent-workspace + default-workspace-rule definitions.
-- Replaces monitors.conf.tmpl (was rendered by tidydots based on hostname).
-- See https://wiki.hypr.land/Configuring/Basics/Monitors/

hl.env("GDK_SCALE", "1")

local hostname_pipe = io.popen("hostname")
local hostname      = hostname_pipe and hostname_pipe:read("*l") or ""
if hostname_pipe then hostname_pipe:close() end

if hostname == "omarchbook" then
    -- Laptop: built-in display, mirror any external monitor (TV/HDMI).
    -- External pinned to 1920x1080@60 to match the laptop panel.
    -- SUPER+E toggles "takeover" mode via scripts/toggle-external-takeover.sh.
    hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 1 })
    hl.monitor({ output = "", mode = "1920x1080@60", position = "auto", scale = 1, mirror = "eDP-1" })
else
    -- Desktop: multi-monitor setup (1x scale for 1080p/1440p displays)
    hl.monitor({ output = "DVI-D-1",  mode = "1680x1050@59.88", position = "0x0",    scale = 1 })
    hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60",    position = "1680x0", scale = 1 })
    hl.monitor({ output = "DP-2",     mode = "1920x1080@60",    position = "3600x0", scale = 1 })
    hl.monitor({ output = "",         mode = "preferred",       position = "auto",   scale = 1 })

    hl.workspace_rule({ workspace = "1",  monitor = "DVI-D-1",  persistent = true, default = true })
    hl.workspace_rule({ workspace = "2",  monitor = "HDMI-A-1", persistent = true, default = true })
    hl.workspace_rule({ workspace = "3",  monitor = "DP-2",     persistent = true, default = true })
    hl.workspace_rule({ workspace = "4",  monitor = "DVI-D-1",  persistent = true })
    hl.workspace_rule({ workspace = "5",  monitor = "HDMI-A-1", persistent = true })
    hl.workspace_rule({ workspace = "6",  monitor = "DP-2",     persistent = true })
    hl.workspace_rule({ workspace = "7",  monitor = "DVI-D-1",  persistent = true })
    hl.workspace_rule({ workspace = "8",  monitor = "HDMI-A-1", persistent = true })
    hl.workspace_rule({ workspace = "9",  monitor = "DP-2",     persistent = true })
    hl.workspace_rule({ workspace = "10", monitor = "DP-2",     persistent = true })

    -- Default workspace for applications
    hl.window_rule({ name = "windowrule-1", match = { class = "teams-for-linux" },         workspace = "1" })
    hl.window_rule({ name = "windowrule-2", match = { class = "signal" },                  workspace = "1" })
    hl.window_rule({ name = "windowrule-3", match = { class = "obsidian" },                workspace = "4" })
    hl.window_rule({ name = "windowrule-4", match = { class = "org.wezfurlong.wezterm" },  workspace = "5" })
    hl.window_rule({ name = "windowrule-5", match = { class = "com.mitchellh.ghostty" },   workspace = "5" })
    hl.window_rule({ name = "windowrule-6", match = { class = "GitKraken" },               workspace = "6" })
    hl.window_rule({ name = "windowrule-7", match = { class = "brave-browser" },           workspace = "7" })
end
```

- [ ] **Step 2: Syntax check**

Run: `luac -p Linux/hypr/monitors.lua`
Expected: no output.

- [ ] **Step 3: Audit against original**

Run: `cat Linux/hypr/monitors.conf.tmpl`. Verify:
- The `env = GDK_SCALE,1` is preserved (always, both branches).
- Laptop branch: 2 monitors, no workspace rules.
- Desktop branch: 4 monitors, 10 workspace rules, 7 windowrules with matching names.

- [ ] **Step 4: Commit**

```bash
git add Linux/hypr/monitors.lua
git commit -m "feat(hypr): migrate monitors to lua with runtime host branching"
```

---

## Task 7: Create `looknfeel.lua`

Source: `Linux/hypr/looknfeel.conf`. The biggest file. Strategy: group related settings into multiple `hl.config()` calls (Hyprland merges them); define curves with `hl.curve()`; define each animation override with `hl.animation()`. Preserve the original "animation = border" double-definition by emitting only the last value (same end-state hyprlang reaches).

**Files:**
- Create: `Linux/hypr/looknfeel.lua`

- [ ] **Step 1: Write `Linux/hypr/looknfeel.lua`**

```lua
-- Change the default Omarchy look'n'feel

local activeBorderColor   = "rgb(cba6f7)"
local inactiveBorderColor = "rgba(595959aa)"

-- https://wiki.hypr.land/Configuring/Variables/#general
hl.config({
    general = {
        gaps_in     = 4,
        gaps_out    = 4,
        border_size = 2,

        col = {
            active_border   = activeBorderColor,
            inactive_border = inactiveBorderColor,
        },

        resize_on_border = false,
        allow_tearing    = false,
        layout           = "master",
    },
})

-- https://wiki.hypr.land/Configuring/Variables/#decoration
hl.config({
    decoration = {
        rounding = 8,

        shadow = {
            enabled      = true,
            range        = 2,
            render_power = 3,
            color        = "rgba(1a1a1aee)",
        },

        blur = {
            enabled    = true,
            size       = 5,
            passes     = 3,
            special    = true,
            brightness = 0.70,
            contrast   = 0.80,
        },
    },
})

-- Vicinae overlay blur
hl.layer_rule({
    name = "layerrule-1",
    match = { namespace = "vicinae" },
    blur = true,
    ignore_alpha = 0,
})

-- https://wiki.hypr.land/Configuring/Variables/#group
hl.config({
    group = {
        col = {
            border_active          = activeBorderColor,
            border_inactive        = inactiveBorderColor,
            border_locked_active   = activeBorderColor,
            border_locked_inactive = inactiveBorderColor,
        },

        groupbar = {
            font_size           = 12,
            font_family         = "monospace",
            font_weight_active  = "ultraheavy",
            font_weight_inactive = "normal",

            indicator_height = 0,
            indicator_gap    = 5,
            height           = 22,
            gaps_in          = 5,
            gaps_out         = 0,

            text_color          = "rgb(ffffff)",
            text_color_inactive = "rgba(ffffff90)",
            col = {
                active   = "rgba(00000040)",
                inactive = "rgba(00000020)",
            },

            gradients                 = true,
            gradient_rounding         = 0,
            gradient_round_only_edges = false,
        },
    },
})

-- https://wiki.hypr.land/Configuring/Variables/#animations
hl.config({ animations = { enabled = true } })

hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })

-- Smooth bezier curves
hl.curve("smoothOut",   { type = "bezier", points = { {0.36, 0},    {0.66, -0.56} } })
hl.curve("smoothIn",    { type = "bezier", points = { {0.25, 1},    {0.5, 1}      } })
hl.curve("overshot",    { type = "bezier", points = { {0.05, 0.9},  {0.1, 1.05}   } })
hl.curve("softSnap",    { type = "bezier", points = { {0.2, 0.8},   {0.2, 1}      } })
hl.curve("gentleFade",  { type = "bezier", points = { {0.4, 0},     {0.2, 1}      } })

hl.animation({ leaf = "global",  enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "windows", enabled = true, speed = 4.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "fade",    enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layersIn",     enabled = true, speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",    enabled = true, speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut",enabled = true, speed = 1.39, bezier = "almostLinear" })

-- Window open/close
hl.animation({ leaf = "windowsIn",   enabled = true, speed = 5, bezier = "overshot",  style = "popin 80%" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 4, bezier = "smoothOut", style = "popin 80%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4, bezier = "softSnap" })

-- Fading
hl.animation({ leaf = "fadeIn",     enabled = true, speed = 3, bezier = "smoothIn" })
hl.animation({ leaf = "fadeOut",    enabled = true, speed = 3, bezier = "smoothOut" })
hl.animation({ leaf = "fadeSwitch", enabled = true, speed = 5, bezier = "gentleFade" })
hl.animation({ leaf = "fadeDim",    enabled = true, speed = 5, bezier = "gentleFade" })

-- Border color transition (the .conf defined "border" twice; the second value wins, so we emit only that one)
hl.animation({ leaf = "border",      enabled = true, speed = 8,  bezier = "softSnap" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 30, bezier = "smoothIn" })

-- Workspace switching (slide effect)
hl.animation({ leaf = "workspaces",       enabled = true, speed = 5, bezier = "overshot", style = "slidevert" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 5, bezier = "overshot", style = "slidevert" })

-- Layers (waybar, notifications, etc.)
hl.animation({ leaf = "layers",     enabled = true, speed = 4, bezier = "softSnap",   style = "fade" })
hl.animation({ leaf = "fadeLayers", enabled = true, speed = 4, bezier = "gentleFade" })

-- See https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/ for more
hl.config({
    dwindle = {
        preserve_split = true,
        force_split    = 2, -- Always split on the right
    },
})

-- See https://wiki.hypr.land/Configuring/Layouts/Master-Layout/ for more
hl.config({
    master = {
        new_status = "master",
    },
})

-- https://wiki.hypr.land/Configuring/Variables/#misc
hl.config({
    misc = {
        disable_hyprland_logo     = true,
        disable_splash_rendering  = true,
        focus_on_activate         = true,
        anr_missed_pings          = 3,
        on_focus_under_fullscreen = 1,
    },
})

-- https://wiki.hypr.land/Configuring/Variables/#cursor
hl.config({
    cursor = {
        hide_on_key_press        = true,
        warp_on_change_workspace = 1,
    },
})

-- Auto toggle scratchpad on switching workspace from scratchpad
hl.config({
    binds = {
        hide_special_on_workspace_change = true,
    },
})

-- Style Gum confirm to match terminal theme
hl.env("GUM_CONFIRM_PROMPT_FOREGROUND",      "6") -- Cyan
hl.env("GUM_CONFIRM_SELECTED_FOREGROUND",    "0") -- Black
hl.env("GUM_CONFIRM_SELECTED_BACKGROUND",    "2") -- Green
hl.env("GUM_CONFIRM_UNSELECTED_FOREGROUND",  "7") -- White
hl.env("GUM_CONFIRM_UNSELECTED_BACKGROUND",  "8") -- Dark grey

-- Terminal transparency (controlled by Hyprland so SUPER+Backspace toggle works)
hl.window_rule({
    match = { tag = "terminal" },
    opacity = "0.90 1",
})
```

- [ ] **Step 2: Syntax check**

Run: `luac -p Linux/hypr/looknfeel.lua`
Expected: no output.

- [ ] **Step 3: Audit against original**

Run: `cat Linux/hypr/looknfeel.conf`. Verify each top-level block (general, decoration, layerrule, group, animations, dwindle, master, misc, cursor, binds, env, windowrule) is represented. The original has 5 env lines, 1 windowrule, 1 layerrule, 1 group block, ~22 animation lines, 10 bezier curves — all should appear above.

- [ ] **Step 4: Commit**

```bash
git add Linux/hypr/looknfeel.lua
git commit -m "feat(hypr): migrate looknfeel to lua"
```

---

## Task 8: Create `apps/*.lua` (all 15 app-specific window-rule files)

Source: `Linux/hypr/apps/*.conf`. Pure window-rule files — one task with all 15 sub-files because each is small and follows the same translation pattern (`windowrule = X, match:Y Z` → `hl.window_rule({ match = { Y = "Z" }, X = ... })`; `windowrule { name=…; match:…=…; rule=…; }` → `hl.window_rule({ name=…, match={…=…}, rule=… })`).

**Files:**
- Create 15 files under `Linux/hypr/apps/`

- [ ] **Step 1: Write `Linux/hypr/apps/1password.lua`**

```lua
hl.window_rule({ match = { class = "^(1[p|P]assword)$" }, no_screen_share = true })
hl.window_rule({ match = { class = "^(1[p|P]assword)$" }, tag = "+floating-window" })
```

- [ ] **Step 2: Write `Linux/hypr/apps/bitwarden.lua`**

```lua
hl.window_rule({ match = { class = "^(Bitwarden)$" }, no_screen_share = true })
hl.window_rule({ match = { class = "^(Bitwarden)$" }, tag = "+floating-window" })

-- Bitwarden Chrome Extension
hl.window_rule({ match = { class = "chrome-nngceckbapebfimnlniiiahkandclblb-Default" }, no_screen_share = true })
hl.window_rule({ match = { class = "chrome-nngceckbapebfimnlniiiahkandclblb-Default" }, tag = "+floating-window" })
```

- [ ] **Step 3: Write `Linux/hypr/apps/browser.lua`**

```lua
-- Browser types
hl.window_rule({ match = { class = "((google-)?[cC]hrom(e|ium)|[bB]rave-browser|[mM]icrosoft-edge|Vivaldi-stable|helium)" }, tag = "+chromium-based-browser" })
hl.window_rule({ match = { class = "([fF]irefox|zen|librewolf)" }, tag = "+firefox-based-browser" })
hl.window_rule({ match = { tag = "chromium-based-browser" }, tag = "-default-opacity" })
hl.window_rule({ match = { tag = "firefox-based-browser" },  tag = "-default-opacity" })

-- Video apps: remove chromium browser tag so they don't get opacity applied
hl.window_rule({ match = { class = "(chrome-youtube.com__-Default|chrome-app.zoom.us__wc_home-Default)" }, tag = "-chromium-based-browser" })
hl.window_rule({ match = { class = "(chrome-youtube.com__-Default|chrome-app.zoom.us__wc_home-Default)" }, tag = "-default-opacity" })

-- Force chromium-based browsers into a tile to deal with --app bug
hl.window_rule({ match = { tag = "chromium-based-browser" }, tile = true })

-- Only a subtle opacity change, but not for video sites
hl.window_rule({ match = { tag = "chromium-based-browser" }, opacity = "1.0 0.97" })
hl.window_rule({ match = { tag = "firefox-based-browser" },  opacity = "1.0 0.97" })
```

- [ ] **Step 4: Write `Linux/hypr/apps/geforce.lua`**

```lua
hl.window_rule({
    name = "geforce",
    match = { class = "GeForceNOW" },
    idle_inhibit = "fullscreen",
})
```

- [ ] **Step 5: Write `Linux/hypr/apps/hyprshot.lua`**

```lua
-- Remove 1px border around hyprshot screenshots
hl.layer_rule({ match = { namespace = "selection" }, no_anim = true })
```

- [ ] **Step 6: Write `Linux/hypr/apps/jetbrains.lua`**

```lua
-- Fix splash screen showing in weird places and prevent annoying focus takeovers
hl.window_rule({
    name = "jetbrains-splash",
    match = { class = "^(jetbrains-.*)$", title = "^(splash)$", float = true },
    tag = "+jetbrains-splash",
    center = true,
    no_focus = true,
    border_size = 0,
})

-- Center popups/find windows
hl.window_rule({
    name = "jetbrains-popup",
    match = { class = "^(jetbrains-.*)", title = "^(| )$", float = true },
    tag = "+jetbrains",
    center = true,
    -- Enabling this makes it possible to provide input in popup dialogs (search window, new file, etc.)
    stay_focused = true,
    border_size = 0,
    min_size = "(monitor_w*0.5) (monitor_h*0.5)",
})

-- Disable window flicker when autocomplete or tooltips appear
hl.window_rule({
    name = "jetbrains-tooltip",
    match = { class = "^(jetbrains-.*)$", title = "^(win.*)$", float = true },
    no_initial_focus = true,
})

-- Disable mouse focus
hl.window_rule({
    name = "jetbrains-focus",
    match = { class = "^(jetbrains-.*)$" },
    no_follow_mouse = true,
})
```

- [ ] **Step 7: Write `Linux/hypr/apps/localsend.lua`**

```lua
-- Float LocalSend and fzf file picker
hl.window_rule({ match = { class = "(Share|localsend)" }, float = true })
hl.window_rule({ match = { class = "(Share|localsend)" }, center = true })
hl.window_rule({ match = { class = "localsend" },         size = "1100 700" })
```

- [ ] **Step 8: Write `Linux/hypr/apps/moonlight.lua`**

```lua
hl.window_rule({
    name = "moonlight",
    match = { class = "com.moonlight_stream.Moonlight" },
    fullscreen = true,
    idle_inhibit = "fullscreen",
})
```

- [ ] **Step 9: Write `Linux/hypr/apps/pip.lua`**

```lua
-- Picture-in-picture overlays
hl.window_rule({ match = { title = "(Picture.?in.?[Pp]icture)" }, tag = "+pip" })
hl.window_rule({ match = { tag = "pip" }, tag = "-default-opacity" })
hl.window_rule({ match = { tag = "pip" }, float = true })
hl.window_rule({ match = { tag = "pip" }, pin = true })
hl.window_rule({ match = { tag = "pip" }, size = "600 338" })
hl.window_rule({ match = { tag = "pip" }, keep_aspect_ratio = true })
hl.window_rule({ match = { tag = "pip" }, border_size = 0 })
hl.window_rule({ match = { tag = "pip" }, opacity = "1 1" })
hl.window_rule({ match = { tag = "pip" }, move = "(monitor_w-window_w-40) (monitor_h*0.04)" })
```

- [ ] **Step 10: Write `Linux/hypr/apps/qemu.lua`**

```lua
hl.window_rule({ match = { class = "qemu" }, tag = "-default-opacity" })
hl.window_rule({ match = { class = "qemu" }, opacity = "1 1" })
```

- [ ] **Step 11: Write `Linux/hypr/apps/retroarch.lua`**

```lua
hl.window_rule({ match = { class = "com.libretro.RetroArch" }, fullscreen = true })
hl.window_rule({ match = { class = "com.libretro.RetroArch" }, tag = "-default-opacity" })
hl.window_rule({ match = { class = "com.libretro.RetroArch" }, opacity = "1 1" })
hl.window_rule({ match = { class = "com.libretro.RetroArch" }, idle_inhibit = "fullscreen" })
```

- [ ] **Step 12: Write `Linux/hypr/apps/steam.lua`**

```lua
-- Float Steam
hl.window_rule({ match = { class = "steam" },                          float = true })
hl.window_rule({ match = { class = "steam", title = "Steam" },         center = true })
hl.window_rule({ match = { class = "steam.*" },                        tag = "-default-opacity" })
hl.window_rule({ match = { class = "steam.*" },                        opacity = "1 1" })
hl.window_rule({ match = { class = "steam", title = "Steam" },         size = "1100 700" })
hl.window_rule({ match = { class = "steam", title = "Friends List" }, size = "460 800" })
hl.window_rule({ match = { class = "steam" },                          idle_inhibit = "fullscreen" })
```

- [ ] **Step 13: Write `Linux/hypr/apps/system.lua`**

```lua
-- Floating windows
hl.window_rule({ match = { tag = "floating-window" }, float = true })
hl.window_rule({ match = { tag = "floating-window" }, center = true })
hl.window_rule({ match = { tag = "floating-window" }, size = "875 600" })
hl.window_rule({
    match = { class = "(org.float\\..*|org.gnome.NautilusPreviewer|org.gnome.Evince|com.gabm.satty|About|TUI.float|imv|mpv)" },
    tag = "+floating-window",
})

-- Large floating windows (90% monitor size)
hl.window_rule({ match = { tag = "floating-window-large" }, float = true })
hl.window_rule({ match = { tag = "floating-window-large" }, center = true })
hl.window_rule({ match = { tag = "floating-window-large" }, size = "(monitor_w*0.9) (monitor_h*0.9)" })
hl.window_rule({ match = { class = "(org.float-large\\..*)" }, tag = "+floating-window-large" })
hl.window_rule({
    match = {
        class = "(xdg-desktop-portal-gtk|sublime_text|DesktopEditors|org.gnome.Nautilus)",
        title = "^(Open.*Files?|Open [F|f]older.*|Save.*Files?|Save.*As|Save|All Files|.*wants to [open|save].*|[C|c]hoose.*)",
    },
    tag = "+floating-window",
})
hl.window_rule({ match = { class = "org.gnome.Calculator" }, float = true })

-- Fullscreen screensaver
hl.window_rule({ match = { class = "org.omarchy.screensaver" }, fullscreen = true })
hl.window_rule({ match = { class = "org.omarchy.screensaver" }, float = true })
hl.window_rule({ match = { class = "org.omarchy.screensaver" }, animation = "slide" })

-- No transparency on media windows
hl.window_rule({
    match = { class = "^(zoom|vlc|mpv|org.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv|org.gnome.NautilusPreviewer)$" },
    tag = "-default-opacity",
})
hl.window_rule({
    match = { class = "^(zoom|vlc|mpv|org.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv|org.gnome.NautilusPreviewer)$" },
    opacity = "1 1",
})

-- Popped window rounding
hl.window_rule({ match = { tag = "pop" }, rounding = 8 })

-- Prevent idle while open
hl.window_rule({ match = { tag = "noidle" }, idle_inhibit = "always" })
```

- [ ] **Step 14: Write `Linux/hypr/apps/telegram.lua`**

```lua
-- Prevent Telegram from stealing focus on new messages
hl.window_rule({ match = { class = "org.telegram.desktop" }, focus_on_activate = false })
```

- [ ] **Step 15: Write `Linux/hypr/apps/terminals.lua`**

```lua
-- Define terminal tag to style them uniformly
hl.window_rule({ match = { class = "(Alacritty|kitty|com.mitchellh.ghostty)" }, tag = "+terminal" })
hl.window_rule({ match = { tag = "terminal" }, tag = "-default-opacity" })
hl.window_rule({ match = { tag = "terminal" }, opacity = "0.97 0.9" })
```

- [ ] **Step 16: Write `Linux/hypr/apps/webcam-overlay.lua`**

```lua
-- Webcam overlay for screen recording
hl.window_rule({ match = { title = "WebcamOverlay" }, float = true })
hl.window_rule({ match = { title = "WebcamOverlay" }, pin = true })
hl.window_rule({ match = { title = "WebcamOverlay" }, no_initial_focus = true })
hl.window_rule({ match = { title = "WebcamOverlay" }, no_dim = true })
hl.window_rule({ match = { title = "WebcamOverlay" }, move = "(monitor_w-window_w-40) (monitor_h-window_h-40)" })
```

- [ ] **Step 17: Syntax check all 15 files**

Run: `for f in Linux/hypr/apps/*.lua; do luac -p "$f" || echo "FAIL: $f"; done`
Expected: no output (all pass).

- [ ] **Step 18: Audit against originals**

Run: `for f in Linux/hypr/apps/*.conf; do echo "=== $f ==="; grep -cE '^(windowrule|layerrule)' "$f"; done` to get rule counts. Then `for f in Linux/hypr/apps/*.lua; do echo "=== $f ==="; grep -cE 'hl\.(window_rule|layer_rule)' "$f"; done` and verify counts match per file (allowing for v2-form `windowrule {…}` blocks where one rule has multiple match: lines but one rule overall).

- [ ] **Step 19: Commit**

```bash
git add Linux/hypr/apps/*.lua
git commit -m "feat(hypr): migrate apps/* window rules to lua"
```

---

## Task 9: Create `apps.lua` (require chain to apps/*)

Source: `Linux/hypr/apps.conf`. Pure `source =` chain.

**Files:**
- Create: `Linux/hypr/apps.lua`

- [ ] **Step 1: Write `Linux/hypr/apps.lua`**

```lua
-- App-specific tweaks
require("apps.1password")
require("apps.bitwarden")
require("apps.browser")
require("apps.hyprshot")
require("apps.jetbrains")
require("apps.localsend")
require("apps.pip")
require("apps.qemu")
require("apps.retroarch")
require("apps.steam")
require("apps.geforce")
require("apps.moonlight")
require("apps.system")
require("apps.telegram")
require("apps.terminals")
require("apps.webcam-overlay")
```

- [ ] **Step 2: Syntax check**

Run: `luac -p Linux/hypr/apps.lua`
Expected: no output.

- [ ] **Step 3: Audit**

Run: `grep -c "^source" Linux/hypr/apps.conf` — expected: 16. Then `grep -c "^require" Linux/hypr/apps.lua` — must also be 16.

- [ ] **Step 4: Commit**

```bash
git add Linux/hypr/apps.lua
git commit -m "feat(hypr): migrate apps source chain to lua"
```

---

## Task 10: Create `windows.lua`

Source: `Linux/hypr/windows.conf`. Three window rules + `require("apps")` + a final opacity rule.

**Files:**
- Create: `Linux/hypr/windows.lua`

- [ ] **Step 1: Write `Linux/hypr/windows.lua`**

```lua
-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/ for more

-- Ignore maximize requests from all apps. You'll probably like this.
hl.window_rule({
    name = "suppress-maximize",
    match = { class = ".*" },
    suppress_event = "maximize",
})

-- Tag all windows for default opacity (apps can override with -default-opacity tag)
hl.window_rule({
    name = "default-opacity-tag",
    match = { class = ".*" },
    tag = "+default-opacity",
})

-- Fix some dragging issues with XWayland
hl.window_rule({
    name = "fix-xwayland-drags",
    match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})

-- App-specific tweaks (may remove default-opacity tag)
require("apps")

-- Apply default opacity after apps have had a chance to opt out
hl.window_rule({
    name = "apply-default-opacity",
    match = { tag = "default-opacity" },
    opacity = "0.97 0.9",
})
```

- [ ] **Step 2: Syntax check**

Run: `luac -p Linux/hypr/windows.lua`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add Linux/hypr/windows.lua
git commit -m "feat(hypr): migrate windows to lua"
```

---

## Task 11: Create `bindings/media.lua`

Source: `Linux/hypr/bindings/media.conf`. All multimedia keys. Note: the original uses `bindeld` (e+l+d) and `bindld` (l+d) flags.

**Files:**
- Create: `Linux/hypr/bindings/media.lua`

- [ ] **Step 1: Write `Linux/hypr/bindings/media.lua`**

```lua
-- Only display the OSD on the currently focused monitor
local osdclient = [[swayosd-client --monitor "$(hyprctl monitors -j | jq -r '.[] | select(.focused == true).name')"]]

-- Laptop multimedia keys for volume and LCD brightness (with OSD)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(osdclient .. " --output-volume raise"),  { locked = true, repeating = true, description = "Volume up" })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(osdclient .. " --output-volume lower"),  { locked = true, repeating = true, description = "Volume down" })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd(osdclient .. " --output-volume mute-toggle"), { locked = true, repeating = true, description = "Mute" })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd(osdclient .. " --input-volume mute-toggle"),  { locked = true, repeating = true, description = "Mute microphone" })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightness-display +5%"),                { locked = true, repeating = true, description = "Brightness up" })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightness-display 5%-"),                { locked = true, repeating = true, description = "Brightness down" })
hl.bind("XF86KbdBrightnessUp",  hl.dsp.exec_cmd("brightness-keyboard up"),                { locked = true, repeating = true, description = "Keyboard brightness up" })
hl.bind("XF86KbdBrightnessDown",hl.dsp.exec_cmd("brightness-keyboard down"),              { locked = true, repeating = true, description = "Keyboard brightness down" })
hl.bind("XF86KbdLightOnOff",    hl.dsp.exec_cmd("brightness-keyboard cycle"),             { locked = true, description = "Keyboard backlight cycle" })

-- Precise 1% multimedia adjustments with Alt modifier
hl.bind("ALT + XF86AudioRaiseVolume", hl.dsp.exec_cmd(osdclient .. " --output-volume +1"), { locked = true, repeating = true, description = "Volume up precise" })
hl.bind("ALT + XF86AudioLowerVolume", hl.dsp.exec_cmd(osdclient .. " --output-volume -1"), { locked = true, repeating = true, description = "Volume down precise" })
hl.bind("ALT + XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightness-display +1%"),           { locked = true, repeating = true, description = "Brightness up precise" })
hl.bind("ALT + XF86MonBrightnessDown",hl.dsp.exec_cmd("brightness-display 1%-"),           { locked = true, repeating = true, description = "Brightness down precise" })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd(osdclient .. " --playerctl next"),       { locked = true, description = "Next track" })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd(osdclient .. " --playerctl play-pause"), { locked = true, description = "Pause" })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd(osdclient .. " --playerctl play-pause"), { locked = true, description = "Play" })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd(osdclient .. " --playerctl previous"),   { locked = true, description = "Previous track" })

-- Switch audio output with Super + Mute
hl.bind("SUPER + XF86AudioMute", hl.dsp.exec_cmd("cmd-audio-switch"), { locked = true, description = "Switch audio output" })
```

- [ ] **Step 2: Syntax check**

Run: `luac -p Linux/hypr/bindings/media.lua`
Expected: no output.

- [ ] **Step 3: Audit**

Run: `grep -cE '^bind(e|l|m|d|r)*ld?\s*=' Linux/hypr/bindings/media.conf` to count source binds. Then `grep -c 'hl.bind' Linux/hypr/bindings/media.lua` — counts must match (expected: 19 each).

- [ ] **Step 4: Commit**

```bash
git add Linux/hypr/bindings/media.lua
git commit -m "feat(hypr): migrate bindings/media to lua"
```

---

## Task 12: Create `bindings/utilities.lua`

Source: `Linux/hypr/bindings/utilities.conf`. All exec binds, no submaps. The `$terminal` variable goes away (only one binding referenced it and it was overridden in-line in bindings/apps.conf anyway).

**Files:**
- Create: `Linux/hypr/bindings/utilities.lua`

- [ ] **Step 1: Write `Linux/hypr/bindings/utilities.lua`**

```lua
-- Menus
hl.bind("SUPER + SPACE",           hl.dsp.exec_cmd("vicinae toggle"),                                  { description = "Dashboard" })
hl.bind("SUPER + CTRL + C",        hl.dsp.exec_cmd("menu capture"),                                    { description = "Capture menu" })
hl.bind("SUPER + CTRL + O",        hl.dsp.exec_cmd("menu toggle"),                                     { description = "Toggle menu" })
hl.bind("SUPER + ALT + SPACE",     hl.dsp.exec_cmd("menu"),                                            { description = "Omarchy menu" })
hl.bind("SUPER + ESCAPE",          hl.dsp.exec_cmd("menu system"),                                     { description = "System menu" })
hl.bind("XF86PowerOff",            hl.dsp.exec_cmd("vicinae vicinae://launch/power"),                  { description = "Power menu" })
hl.bind("SUPER + CTRL + K",        hl.dsp.exec_cmd("menu-keybindings"),                                { description = "Show key bindings" })
hl.bind("XF86Calculator",          hl.dsp.exec_cmd("vicinae vicinae://extensions/vicinae/calculator/history"), { description = "Calculator" })
hl.bind("SUPER + CTRL + W",        hl.dsp.exec_cmd("pkill waybar && waybar &"),                        { description = "Reload Waybar" })
hl.bind("SUPER + CTRL + H",        hl.dsp.exec_cmd("restart-hyprctl"),                                 { description = "Reload Hyprland" })

-- Aesthetics
hl.bind("SUPER + SHIFT + SPACE",         hl.dsp.exec_cmd("toggle-waybar"),                                 { description = "Toggle top bar" })
hl.bind("SUPER + CTRL + SPACE",          hl.dsp.exec_cmd("menu background"),                               { description = "Theme background menu" })
hl.bind("SUPER + SHIFT + CTRL + SPACE",  hl.dsp.exec_cmd("menu theme"),                                    { description = "Theme menu" })
hl.bind("SUPER + BACKSPACE",             hl.dsp.exec_cmd([[hyprctl dispatch setprop "address:$(hyprctl activewindow -j | jq -r '.address')" opaque toggle]]), { description = "Toggle window transparency" })
hl.bind("SUPER + SHIFT + BACKSPACE",     hl.dsp.exec_cmd("hyprland-window-gaps-toggle"),                   { description = "Toggle window gaps" })
hl.bind("SUPER + CTRL + BACKSPACE",      hl.dsp.exec_cmd("hyprland-window-single-square-aspect-toggle"),   { description = "Toggle single-window square aspect" })

-- Notifications
hl.bind("SUPER + COMMA",                 hl.dsp.exec_cmd("makoctl dismiss"),                               { description = "Dismiss last notification" })
hl.bind("SUPER + SHIFT + COMMA",         hl.dsp.exec_cmd("makoctl dismiss --all"),                         { description = "Dismiss all notifications" })
hl.bind("SUPER + CTRL + COMMA",          hl.dsp.exec_cmd("toggle-notification-silencing"),                 { description = "Toggle silencing notifications" })
hl.bind("SUPER + ALT + COMMA",           hl.dsp.exec_cmd("makoctl invoke"),                                { description = "Invoke last notification" })
hl.bind("SUPER + SHIFT + ALT + COMMA",   hl.dsp.exec_cmd("makoctl restore"),                               { description = "Restore last notification" })

-- Pacman
hl.bind("SUPER + CTRL + I",              hl.dsp.exec_cmd("launch-tui-large pkg-install"),                  { description = "Install packages" })
hl.bind("SUPER + CTRL + U",              hl.dsp.exec_cmd("launch-tui-large update"),                       { description = "Update system" })
hl.bind("SUPER + CTRL + R",              hl.dsp.exec_cmd("launch-tui-large pkg-remove"),                   { description = "Remove packages" })
hl.bind("SUPER + CTRL + A",              hl.dsp.exec_cmd("launch-tui-large pkg-aur-install"),              { description = "Install AUR packages" })

-- Captures
hl.bind("PRINT",                         hl.dsp.exec_cmd("cmd-screenshot"),                                { description = "Screenshot" })
hl.bind("ALT + PRINT",                   hl.dsp.exec_cmd("menu screenrecord"),                             { description = "Screenrecording" })
hl.bind("SUPER + PRINT",                 hl.dsp.exec_cmd("pkill hyprpicker || hyprpicker -a"),             { description = "Color picker" })

-- Control panels
hl.bind("SUPER + CTRL + T",              hl.dsp.exec_cmd("launch-tui-large btop"),                         { description = "Top" })

-- Dictation
hl.bind("SUPER + CTRL + X",              hl.dsp.exec_cmd("voxtype record toggle"),                         { description = "Toggle dictation" })

-- Zoom
hl.bind("SUPER + CTRL + Z",              hl.dsp.exec_cmd([[hyprctl keyword cursor:zoom_factor $(hyprctl getoption cursor:zoom_factor -j | jq '.float + 1')]]), { description = "Zoom in" })
hl.bind("SUPER + CTRL + ALT + Z",        hl.dsp.exec_cmd("hyprctl keyword cursor:zoom_factor 1"),          { description = "Reset zoom" })

-- Lock system
hl.bind("SUPER + CTRL + L",              hl.dsp.exec_cmd("lock-screen"),                                   { description = "Lock system" })

-- Display
hl.bind("SUPER + E",                     hl.dsp.exec_cmd("~/.config/hypr/scripts/toggle-external-takeover.sh"), { description = "Toggle external display takeover" })

hl.bind("SUPER + V",                     hl.dsp.exec_cmd("vicinae vicinae://launch/clipboard/history"),    { description = "Clipboard history" })
hl.bind("SUPER + PERIOD",                hl.dsp.exec_cmd("vicinae vicinae://launch/core/search-emojis"),   { description = "Emoji picker" })
```

- [ ] **Step 2: Syntax check**

Run: `luac -p Linux/hypr/bindings/utilities.lua`
Expected: no output.

- [ ] **Step 3: Audit**

Run: `grep -cE '^bindd?\s*=' Linux/hypr/bindings/utilities.conf` to count source binds (commented-out lines starting with `#` excluded). Compare to `grep -c 'hl.bind' Linux/hypr/bindings/utilities.lua`. Expected: 35 active binds.

- [ ] **Step 4: Commit**

```bash
git add Linux/hypr/bindings/utilities.lua
git commit -m "feat(hypr): migrate bindings/utilities to lua"
```

---

## Task 13: Create `bindings/tiling.lua`

Source: `Linux/hypr/bindings/tiling.conf`. Largest binding file. Includes two submaps (`resize` and `clean`).

**Files:**
- Create: `Linux/hypr/bindings/tiling.lua`

- [ ] **Step 1: Write `Linux/hypr/bindings/tiling.lua`**

```lua
-- This file replaces tiling.conf (now deprecated in favor of tiling-v2 per Omarchy).
-- All bindings below preserve the behavior of the previous .conf.

-- Fullscreen management
hl.bind("SUPER + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }), { description = "Force full screen" })
hl.bind("SUPER + F",         hl.dsp.window.fullscreen({ mode = "maximized",  action = "toggle" }), { description = "Full width" })

-- Close windows
hl.bind("SUPER + W",          hl.dsp.window.close(),                                       { description = "Close window" })
hl.bind("CTRL + ALT + DELETE", hl.dsp.exec_cmd("hyprland-window-close-all"),               { description = "Close all windows" })

-- Control tiling
hl.bind("SUPER + P",         hl.dsp.window.pseudo(),                                      { description = "Pseudo window" })
hl.bind("SUPER + SHIFT + V", hl.dsp.window.float({ action = "toggle" }),                  { description = "Toggle window floating/tiling" })

-- Switch workspaces with SUPER + [0-9] (via scancode)
hl.bind("SUPER + code:10", hl.dsp.focus({ workspace = 1  }), { description = "Switch to workspace 1" })
hl.bind("SUPER + code:11", hl.dsp.focus({ workspace = 2  }), { description = "Switch to workspace 2" })
hl.bind("SUPER + code:12", hl.dsp.focus({ workspace = 3  }), { description = "Switch to workspace 3" })
hl.bind("SUPER + code:13", hl.dsp.focus({ workspace = 4  }), { description = "Switch to workspace 4" })
hl.bind("SUPER + code:14", hl.dsp.focus({ workspace = 5  }), { description = "Switch to workspace 5" })
hl.bind("SUPER + code:15", hl.dsp.focus({ workspace = 6  }), { description = "Switch to workspace 6" })
hl.bind("SUPER + code:16", hl.dsp.focus({ workspace = 7  }), { description = "Switch to workspace 7" })
hl.bind("SUPER + code:17", hl.dsp.focus({ workspace = 8  }), { description = "Switch to workspace 8" })
hl.bind("SUPER + code:18", hl.dsp.focus({ workspace = 9  }), { description = "Switch to workspace 9" })
hl.bind("SUPER + code:19", hl.dsp.focus({ workspace = 10 }), { description = "Switch to workspace 10" })

-- Move active window to a workspace with SUPER + SHIFT + [0-9]
hl.bind("SUPER + SHIFT + code:10", hl.dsp.window.move({ workspace = 1  }), { description = "Move window to workspace 1" })
hl.bind("SUPER + SHIFT + code:11", hl.dsp.window.move({ workspace = 2  }), { description = "Move window to workspace 2" })
hl.bind("SUPER + SHIFT + code:12", hl.dsp.window.move({ workspace = 3  }), { description = "Move window to workspace 3" })
hl.bind("SUPER + SHIFT + code:13", hl.dsp.window.move({ workspace = 4  }), { description = "Move window to workspace 4" })
hl.bind("SUPER + SHIFT + code:14", hl.dsp.window.move({ workspace = 5  }), { description = "Move window to workspace 5" })
hl.bind("SUPER + SHIFT + code:15", hl.dsp.window.move({ workspace = 6  }), { description = "Move window to workspace 6" })
hl.bind("SUPER + SHIFT + code:16", hl.dsp.window.move({ workspace = 7  }), { description = "Move window to workspace 7" })
hl.bind("SUPER + SHIFT + code:17", hl.dsp.window.move({ workspace = 8  }), { description = "Move window to workspace 8" })
hl.bind("SUPER + SHIFT + code:18", hl.dsp.window.move({ workspace = 9  }), { description = "Move window to workspace 9" })
hl.bind("SUPER + SHIFT + code:19", hl.dsp.window.move({ workspace = 10 }), { description = "Move window to workspace 10" })

hl.bind("SUPER + U", hl.dsp.focus({ workspace = "previous" }), { description = "Former workspace" })

-- Swap active window with the one next to it with SUPER + SHIFT + arrow keys
hl.bind("SUPER + SHIFT + LEFT",  hl.dsp.window.swap({ direction = "left"  }), { description = "Swap window to the left" })
hl.bind("SUPER + SHIFT + RIGHT", hl.dsp.window.swap({ direction = "right" }), { description = "Swap window to the right" })
hl.bind("SUPER + SHIFT + UP",    hl.dsp.window.swap({ direction = "up"    }), { description = "Swap window up" })
hl.bind("SUPER + SHIFT + DOWN",  hl.dsp.window.swap({ direction = "down"  }), { description = "Swap window down" })

-- Cycle through applications on active workspace
hl.bind("ALT + TAB",         hl.dsp.window.cycle_next(),                  { description = "Cycle to next window" })
hl.bind("ALT + SHIFT + TAB", hl.dsp.window.cycle_next({ next = false }),  { description = "Cycle to prev window" })
hl.bind("ALT + TAB",         hl.dsp.window.bring_to_top(),                { description = "Reveal active window on top" })
hl.bind("ALT + SHIFT + TAB", hl.dsp.window.bring_to_top(),                { description = "Reveal active window on top" })

-- Resize active window
hl.bind("SUPER + code:20",         hl.dsp.window.resize({ x = -100, y = 0,   relative = true }), { description = "Expand window left" })  -- - key
hl.bind("SUPER + code:21",         hl.dsp.window.resize({ x = 100,  y = 0,   relative = true }), { description = "Shrink window left" })  -- = key
hl.bind("SUPER + SHIFT + code:20", hl.dsp.window.resize({ x = 0,    y = -100, relative = true }), { description = "Shrink window up" })
hl.bind("SUPER + SHIFT + code:21", hl.dsp.window.resize({ x = 0,    y = 100,  relative = true }), { description = "Expand window down" })

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(),   { mouse = true, description = "Move window" })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Resize window" })

-- Resize submap (arrow-key resizing)
hl.bind("SUPER + R", hl.dsp.submap("resize"))
hl.define_submap("resize", function()
    hl.bind("l",      hl.dsp.window.resize({ x =  10, y =   0, relative = true }), { repeating = true })
    hl.bind("h",      hl.dsp.window.resize({ x = -10, y =   0, relative = true }), { repeating = true })
    hl.bind("k",      hl.dsp.window.resize({ x =   0, y = -10, relative = true }), { repeating = true })
    hl.bind("j",      hl.dsp.window.resize({ x =   0, y =  10, relative = true }), { repeating = true })
    hl.bind("escape", hl.dsp.submap("reset"))
end)

-- Tiling
hl.bind("SUPER + SHIFT + H", hl.dsp.window.move({ direction = "left"  }), { description = "Move window to left workspace" })
hl.bind("SUPER + SHIFT + L", hl.dsp.window.move({ direction = "right" }), { description = "Move window to right workspace" })
hl.bind("SUPER + SHIFT + K", hl.dsp.window.move({ direction = "up"    }), { description = "Move window to upper workspace" })
hl.bind("SUPER + SHIFT + J", hl.dsp.window.move({ direction = "down"  }), { description = "Move window to lower workspace" })
hl.bind("SUPER + M",         hl.dsp.layout("swapwithmaster"),             { description = "Swap with master" })

hl.bind("SUPER + H", hl.dsp.focus({ direction = "left"  }), { description = "Move focus left" })
hl.bind("SUPER + L", hl.dsp.focus({ direction = "right" }), { description = "Move focus right" })
hl.bind("SUPER + K", hl.dsp.focus({ direction = "up"    }), { description = "Move focus right" })
hl.bind("SUPER + J", hl.dsp.focus({ direction = "down"  }), { description = "Move focus right" })
hl.bind("SUPER + N", hl.dsp.focus({ workspace  = "m+1"  }), { description = "Next workspace on monitor" })
hl.bind("SUPER + P", hl.dsp.focus({ workspace  = "m-1"  }), { description = "Previous workspace on monitor" })
hl.bind("SUPER + SHIFT + ALT + H", hl.dsp.workspace.move({ monitor = "l" }), { description = "Move current workspace left" })
hl.bind("SUPER + SHIFT + ALT + L", hl.dsp.workspace.move({ monitor = "r" }), { description = "Move current workspace right" })

hl.bind("SUPER + S", hl.dsp.layout("swapsplit"))
hl.bind("SUPER + T", hl.dsp.layout("orientationcycle left top left"))

-- Clean submap (disables most keybinds, used by RustDesk integration)
hl.bind("SUPER + SHIFT + Q", hl.dsp.submap("clean"))
hl.define_submap("clean", function()
    hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
    hl.bind("SUPER + SHIFT + Q", hl.dsp.submap("reset"))
end)
```

- [ ] **Step 2: Syntax check**

Run: `luac -p Linux/hypr/bindings/tiling.lua`
Expected: no output.

- [ ] **Step 3: Audit**

Run: `grep -cE '^(bind[demlr]*\s*=|submap\s*=)' Linux/hypr/bindings/tiling.conf`. Then count `hl.bind` + `hl.define_submap` in the new file. The structural counts won't be exactly equal (submap declarations don't have a direct equivalent — they're encapsulated in `hl.define_submap`), but every individual binding should be accounted for.

Manually verify both submaps exist: `grep "hl.define_submap" Linux/hypr/bindings/tiling.lua` should show `resize` and `clean`.

- [ ] **Step 4: Commit**

```bash
git add Linux/hypr/bindings/tiling.lua
git commit -m "feat(hypr): migrate bindings/tiling to lua (incl. resize+clean submaps)"
```

---

## Task 14: Create `bindings/apps.lua`

Source: `Linux/hypr/bindings/apps.conf`. App-launcher binds.

**Files:**
- Create: `Linux/hypr/bindings/apps.lua`

- [ ] **Step 1: Write `Linux/hypr/bindings/apps.lua`**

```lua
-- App launchers. The `##` escape for `#` in URLs is unnecessary in Lua strings
-- (no comment parsing on strings), but we don't have any such URLs here anyway.

hl.bind("SUPER + RETURN",         hl.dsp.exec_cmd("uwsm-app -- xdg-terminal-exec ~/.config/hypr/scripts/tmux-smart-attach.sh"), { description = "Terminal" })
hl.bind("SUPER + SHIFT + RETURN", hl.dsp.exec_cmd("uwsm-app -- xdg-terminal-exec"),                                              { description = "Terminal (no tmux)" })
hl.bind("SUPER + ALT + F",        hl.dsp.exec_cmd("vicinae vicinae://extensions/vicinae/file/search"),                          { description = "Search" })
hl.bind("SUPER + ALT + Y",        hl.dsp.exec_cmd("launch-tui-large yazi"),                                                     { description = "File manager" })
hl.bind("SUPER + ALT + M",        hl.dsp.exec_cmd("launch-or-focus teams-for-linux"),                                           { description = "MS Teams" })
hl.bind("SUPER + ALT + B",        hl.dsp.exec_cmd([[launch-or-focus brave-browser "uwsm app -- brave --enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime"]]), { description = "Browser" })
hl.bind("SUPER + ALT + N",        hl.dsp.exec_cmd("launch-editor"),                                                             { description = "Editor" })
hl.bind("SUPER + ALT + D",        hl.dsp.exec_cmd("launch-tui-large lazydocker"),                                               { description = "Docker" })
hl.bind("SUPER + ALT + O",        hl.dsp.exec_cmd([[launch-or-focus obsidian "uwsm app -- obsidian -disable-gpu --enable-wayland-ime"]]), { description = "Obsidian" })
hl.bind("SUPER + ALT + SLASH",    hl.dsp.exec_cmd("uwsm app -- 1password"),                                                     { description = "Passwords" })
hl.bind("SUPER + ALT + G",        hl.dsp.exec_cmd([[launch-or-focus gitkraken "uwsm app -- gitkraken"]]),                       { description = "GitKraken" })
hl.bind("SUPER + ALT + S",        hl.dsp.exec_cmd([[launch-or-focus signal "uwsm app -- signal-desktop"]]),                     { description = "Signal" })
hl.bind("SUPER + ALT + P",        hl.dsp.exec_cmd([[launch-or-focus 1password "uwsm app -- 1password"]]),                       { description = "1Password" })
```

- [ ] **Step 2: Syntax check**

Run: `luac -p Linux/hypr/bindings/apps.lua`
Expected: no output.

- [ ] **Step 3: Audit**

Run: `grep -cE '^bindd?\s*=' Linux/hypr/bindings/apps.conf` (count active binds). Compare to `grep -c 'hl.bind' Linux/hypr/bindings/apps.lua`. Expected: 13 each.

- [ ] **Step 4: Commit**

```bash
git add Linux/hypr/bindings/apps.lua
git commit -m "feat(hypr): migrate bindings/apps to lua"
```

---

## Task 15: Final whole-tree syntax verification

Before deleting the old `.conf` files, verify the entire migrated tree parses cleanly.

**Files:** none modified

- [ ] **Step 1: Run `luac -p` on every Lua file**

Run:

```bash
find Linux/hypr -name '*.lua' -print0 | xargs -0 -n1 luac -p
```

Expected: no output. Any failures = stop, fix that file in its own commit before proceeding.

- [ ] **Step 2: Spot check `hyprland.lua` requires resolve to existing files**

Run:

```bash
for m in autostart monitors input envs theme/hyprland looknfeel windows bindings/media bindings/tiling bindings/utilities bindings/apps; do
    test -f "Linux/hypr/${m}.lua" || echo "MISSING: $m"
done
test -f Linux/hypr/apps.lua || echo "MISSING: apps"
for a in 1password bitwarden browser geforce hyprshot jetbrains localsend moonlight pip qemu retroarch steam system telegram terminals webcam-overlay; do
    test -f "Linux/hypr/apps/${a}.lua" || echo "MISSING: apps/$a"
done
echo done
```

Expected: prints `done` only, no `MISSING` lines.

---

## Task 16: Delete obsolete `.conf` files

This is the point of no return for clean rollback. Keep it as the final commit before user verification so the previous commit (`Task 15` verification + everything before it) leaves all old files in place for easy bisect.

**Files:**
- Delete: `Linux/hypr/hyprland.conf`, `autostart.conf`, `monitors.conf` (symlink), `monitors.conf.tmpl`, `monitors.conf.tmpl.rendered`, `input.conf`, `envs.conf`, `windows.conf`, `apps.conf`, `looknfeel.conf`
- Delete: `Linux/hypr/theme/hyprland.conf`
- Delete: `Linux/hypr/bindings/{media,tiling,utilities,apps}.conf`
- Delete: `Linux/hypr/apps/*.conf` (16 files)

- [ ] **Step 1: Stage deletions**

Run:

```bash
git rm \
    Linux/hypr/hyprland.conf \
    Linux/hypr/autostart.conf \
    Linux/hypr/monitors.conf \
    Linux/hypr/monitors.conf.tmpl \
    Linux/hypr/monitors.conf.tmpl.rendered \
    Linux/hypr/input.conf \
    Linux/hypr/envs.conf \
    Linux/hypr/windows.conf \
    Linux/hypr/apps.conf \
    Linux/hypr/looknfeel.conf \
    Linux/hypr/theme/hyprland.conf \
    Linux/hypr/bindings/media.conf \
    Linux/hypr/bindings/tiling.conf \
    Linux/hypr/bindings/utilities.conf \
    Linux/hypr/bindings/apps.conf \
    Linux/hypr/apps/1password.conf \
    Linux/hypr/apps/bitwarden.conf \
    Linux/hypr/apps/browser.conf \
    Linux/hypr/apps/geforce.conf \
    Linux/hypr/apps/hyprshot.conf \
    Linux/hypr/apps/jetbrains.conf \
    Linux/hypr/apps/localsend.conf \
    Linux/hypr/apps/moonlight.conf \
    Linux/hypr/apps/pip.conf \
    Linux/hypr/apps/qemu.conf \
    Linux/hypr/apps/retroarch.conf \
    Linux/hypr/apps/steam.conf \
    Linux/hypr/apps/system.conf \
    Linux/hypr/apps/telegram.conf \
    Linux/hypr/apps/terminals.conf \
    Linux/hypr/apps/webcam-overlay.conf
```

- [ ] **Step 2: Verify staging**

Run: `git status --short Linux/hypr | grep '^D '`
Expected: 31 deletion entries (one per removed file).

- [ ] **Step 3: Commit**

```bash
git commit -m "chore(hypr): remove obsolete hyprlang .conf files (replaced by .lua)"
```

---

## Task 17: User runtime verification (HUMAN STEP)

The migration is complete on disk. The remaining verification must happen on the user's actual Hyprland session — this environment can't reload Hyprland.

- [ ] **Step 1: Run tidydots to deploy the new symlinks**

Run: `tidydots apply` (or whatever invocation the user prefers).
This refreshes the `~/.config/hypr` symlink. Since the tidydots mapping just links `Linux/hypr/` as a directory, all new `.lua` files appear automatically.

- [ ] **Step 2: Restart Hyprland (cold start)**

Hyprland 0.55 only picks up `.lua` vs `.conf` choice **at startup**, not on `hyprctl reload`. Log out and back in, or reboot.

- [ ] **Step 3: Check the Hyprland log for errors**

Run: `tail -100 ~/.cache/hyprland/hyprland.log` (or the appropriate log path).
Expected: no `[ERROR]`/`Lua error`/`hl.*: ...` lines. If there are errors, note the file and line, then revert the specific task's commit while debugging.

- [ ] **Step 4: Behavioral checklist**

Walk through and confirm each behavior. Tick off as you go:

- [ ] All monitors come up at correct resolutions/positions (run `hyprctl monitors`).
- [ ] Persistent workspaces 1-10 land on the right monitors (desktop only; for laptop just confirm the mirror layout works).
- [ ] Autostart processes spawned: `pgrep -a hypridle mako waybar fcitx5 swaybg swayosd-server signal teams-for-linux vicinae`.
- [ ] **Workspace switching:** SUPER+1..0 switches to each workspace; SUPER+SHIFT+1..0 moves the active window.
- [ ] **Focus:** SUPER+H/J/K/L moves focus; SUPER+SHIFT+H/J/K/L moves window in tile.
- [ ] **Window ops:** SUPER+W closes; SUPER+F maximize-toggle; SUPER+SHIFT+F real-fullscreen toggle; SUPER+SHIFT+V toggle floating.
- [ ] **Submap — resize:** SUPER+R enters; hjkl resizes; ESC exits.
- [ ] **Submap — clean:** SUPER+SHIFT+Q enters; SUPER+SHIFT+Q exits. (Trigger RustDesk auto-switch via opening a Remote Desktop window if you want to test the service path.)
- [ ] **Mouse:** SUPER+LMB drag moves window; SUPER+RMB drag resizes.
- [ ] **App launchers:** SUPER+RETURN terminal, SUPER+ALT+B browser, SUPER+ALT+S signal, etc.
- [ ] **Utilities:** SUPER+SPACE Vicinae dashboard; SUPER+ESC system menu; PRINT screenshot.
- [ ] **Window rules:** open Brave/Chrome — has subtle opacity; open JetBrains IDE — popups center correctly; open 1Password — floats and excluded from screen share; open a terminal (kitty/ghostty) — has terminal opacity; pop a YouTube into PiP — pinned and sized.
- [ ] **Multimedia keys:** XF86 volume/brightness/play keys work with OSD.
- [ ] **Special workspace** (if used): scratchpad-style toggles.
- [ ] **Visual polish:** active border is `rgb(cba6f7)`, blur on Vicinae overlay, gaps look right.

- [ ] **Step 5: Report back**

Confirm to me what works and what doesn't. For anything broken, share:
- The Hyprland log error (if any).
- The exact behavior expected vs. observed.
- Which file/binding you suspect.

We then fix forward (new commit, no revert) unless a whole task is broken.

---

## Self-Review Notes

- **Spec coverage**: every section of the design spec has a corresponding task. Risks/unknowns surfaced in the spec are explicit in the code (e.g., `cycle_next({ next = false })` for prev — confirmed against source).
- **Placeholder scan**: no TBDs. Every code block is complete inline.
- **Type consistency**: `hl.dsp.window.fullscreen({mode, action})` used identically in Task 13; `hl.dsp.focus({workspace=N})` for integer workspaces, `{workspace="previous"}` and `{workspace="m+1"}` for string selectors — consistent.
- **Rule field naming**: `no_screen_share`, `no_focus`, `no_initial_focus`, `no_dim`, `no_follow_mouse`, `idle_inhibit`, `stay_focused`, `border_size`, `min_size`, `keep_aspect_ratio`, `focus_on_activate`, `suppress_event` — all snake_case identical to hyprlang. If any rejects at runtime, document in Task 17 and patch forward.
