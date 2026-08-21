#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TILING_LUA="$SCRIPT_DIR/../bindings/tiling.lua"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT
mkdir -p -- "$TEST_ROOT/bin"
cat >"$TEST_ROOT/bin/hostname" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$TEST_HOSTNAME"
EOF
chmod 0700 "$TEST_ROOT/bin/hostname"
export PATH="$TEST_ROOT/bin:/usr/bin:/bin"

run_tiling_binding() {
  local hostname=$1

  TEST_HOSTNAME=$hostname lua - "$TILING_LUA" <<'LUA'
local config_path = arg[1]

local function command(name)
  return function(options)
    if type(options) == "table" and options.direction then
      return name .. ":" .. options.direction
    end
    return name
  end
end

hl = {
  bind = function(key, action)
    if key == "SUPER + H" then
      print(key .. "=" .. action)
    end
  end,
  define_submap = function() end,
  dsp = {
    exec_cmd = function(value) return "exec:" .. value end,
    focus = command("focus"),
    layout = command("layout"),
    submap = command("submap"),
    window = {
      bring_to_top = command("bring_to_top"),
      close = command("close"),
      cycle_next = command("cycle_next"),
      drag = command("drag"),
      float = command("float"),
      fullscreen = command("fullscreen"),
      move = command("move"),
      resize = command("resize"),
      swap = command("swap"),
    },
    workspace = {
      move = command("workspace_move"),
    },
  },
}

dofile(config_path)
LUA
}

host_binding=$(run_tiling_binding antoinews-linux)
[[ $host_binding == 'SUPER + H=exec:~/.config/hypr/rustdesk-focus-handoff.sh send' ]] ||
  fail "antoinews-linux SUPER+H binding mismatch: $host_binding"

client_binding=$(run_tiling_binding DESKTOP-E07VTRN)
[[ $client_binding == 'SUPER + H=focus:left' ]] ||
  fail "desktop SUPER+H binding mismatch: $client_binding"

printf 'PASS: tiling binding tests\n'
