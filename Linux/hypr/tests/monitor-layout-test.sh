#!/bin/bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config="$script_dir/../monitors.lua"
autostart="$script_dir/../autostart.lua"

lua - "$config" "$autostart" <<'LUA'
local config = assert(arg[1], "monitor config path is required")
local autostart = assert(arg[2], "autostart config path is required")
local monitors = {}

hl = {
  env = function() end,
  monitor = function(value)
    monitors[value.output] = value
  end,
  workspace_rule = function() end,
  window_rule = function() end,
}

io.popen = function(command)
  assert(command == "hostname", "unexpected command: " .. command)
  return {
    read = function(_, format)
      assert(format == "*l", "unexpected read format: " .. format)
      return "antoinews-linux"
    end,
    close = function() end,
  }
end

dofile(config)

local left = assert(monitors["DP-2"], "DP-2 is not configured")
local right = assert(monitors["DP-1"], "DP-1 is not configured")

assert(right.disabled ~= true, "DP-1 is disabled")
assert(left.mode == "1920x1080@60", "DP-2 mode is " .. tostring(left.mode))
assert(left.position == "0x0", "DP-2 position is " .. tostring(left.position))
assert(left.scale == 1, "DP-2 scale is " .. tostring(left.scale))
assert(right.mode == "1920x1080@60", "DP-1 mode is " .. tostring(right.mode))
assert(right.position == "1920x0", "DP-1 position is " .. tostring(right.position))
assert(right.scale == 1, "DP-1 scale is " .. tostring(right.scale))

local monitor_nudge
hl.on = function(event, callback)
  assert(event == "hyprland.start", "unexpected event: " .. event)
  callback()
end
hl.exec_cmd = function(command)
  if command:find("hl.monitor", 1, true) then
    monitor_nudge = command
  end
end

dofile(autostart)

assert(monitor_nudge, "DP-2 startup monitor nudge is missing")
assert(monitor_nudge:find('position = "1x0"', 1, true), "DP-2 is not nudged one pixel from the left origin")
assert(monitor_nudge:find('position = "0x0"', 1, true), "DP-2 startup nudge does not restore the left origin")
LUA

printf 'PASS: desktop monitor layout\n'
