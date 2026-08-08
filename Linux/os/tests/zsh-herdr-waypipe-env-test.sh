#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
config=$repo_root/Linux/zsh/.zshrc
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

mkdir -p "$tmp/home"

CONFIG="$config" HOME="$tmp/home" HERDR_ENV=1 WAYLAND_DISPLAY=wayland-original \
  XDG_RUNTIME_DIR=/run/original DISPLAY=:0 \
  zsh -df >"$tmp/zsh-output" <<'ZSH'
typeset -ga precmd_functions=()
typeset snapshot_output=
typeset snapshot_status=0

herdr-waypipe-env() {
    [[ "$1" == read ]] || return 1
    print -rn -- "$snapshot_output"
    return "$snapshot_status"
}

source "$CONFIG" >/dev/null 2>&1

if ! whence _herdr_refresh_waypipe_env >/dev/null; then
    print -u2 -- 'Herdr refresh hook was not defined'
    exit 1
fi

assert_environment() {
    local label=$1 expected_wayland=$2 expected_runtime=$3 expected_display=$4

    if [[ "$WAYLAND_DISPLAY" != "$expected_wayland" ||
          "$XDG_RUNTIME_DIR" != "$expected_runtime" ||
          "${DISPLAY-<unset>}" != "$expected_display" ]]; then
        print -u2 -- "$label mutated the environment"
        print -u2 -- "WAYLAND_DISPLAY=${WAYLAND_DISPLAY-<unset>}"
        print -u2 -- "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR-<unset>}"
        print -u2 -- "DISPLAY=${DISPLAY-<unset>}"
        exit 1
    fi
}

assert_rejected_without_mutation() {
    local label=$1 fixture=$2

    export WAYLAND_DISPLAY=wayland-original
    export XDG_RUNTIME_DIR=/run/original
    export DISPLAY=:0
    snapshot_output=$fixture
    snapshot_status=0

    if _herdr_refresh_waypipe_env; then
        print -u2 -- "$label was unexpectedly accepted"
        exit 1
    fi
    assert_environment "$label" wayland-original /run/original :0
}

snapshot_output=$'WAYLAND_DISPLAY=wayland-new\nXDG_RUNTIME_DIR=/run/new path\nDISPLAY=localhost:12.0=screen\n'
_herdr_refresh_waypipe_env
assert_environment valid wayland-new '/run/new path' 'localhost:12.0=screen'

snapshot_status=1
if _herdr_refresh_waypipe_env; then
    print -u2 -- 'cleared snapshot was unexpectedly accepted'
    exit 1
fi
assert_environment restored-after-clear wayland-original /run/original :0
snapshot_status=0

assert_rejected_without_mutation missing \
  $'WAYLAND_DISPLAY=wayland-new\nXDG_RUNTIME_DIR=/run/new\n'
assert_rejected_without_mutation duplicate \
  $'WAYLAND_DISPLAY=wayland-new\nXDG_RUNTIME_DIR=/run/new\nXDG_RUNTIME_DIR=/run/duplicate\nDISPLAY=:1\n'
assert_rejected_without_mutation reordered \
  $'XDG_RUNTIME_DIR=/run/new\nWAYLAND_DISPLAY=wayland-new\nDISPLAY=:1\n'
assert_rejected_without_mutation extra \
  $'WAYLAND_DISPLAY=wayland-new\nXDG_RUNTIME_DIR=/run/new\nDISPLAY=:1\nEXTRA=value\n'
assert_rejected_without_mutation extra-empty \
  $'WAYLAND_DISPLAY=wayland-new\nXDG_RUNTIME_DIR=/run/new\nDISPLAY=:1\n\n'
assert_rejected_without_mutation empty-wayland \
  $'WAYLAND_DISPLAY=\nXDG_RUNTIME_DIR=/run/new\nDISPLAY=:1\n'
assert_rejected_without_mutation empty-runtime \
  $'WAYLAND_DISPLAY=/run/new/wayland-1\nXDG_RUNTIME_DIR=\nDISPLAY=:1\n'
assert_rejected_without_mutation malformed \
  $'WAYLAND_DISPLAY=wayland-new\nnot-a-record\nDISPLAY=:1\n'

export WAYLAND_DISPLAY=wayland-original
export XDG_RUNTIME_DIR=/run/original
export DISPLAY=:0
snapshot_status=1
snapshot_output=$'WAYLAND_DISPLAY=wayland-new\nXDG_RUNTIME_DIR=/run/new\nDISPLAY=:1\n'
if _herdr_refresh_waypipe_env; then
    print -u2 -- 'failed helper read was unexpectedly accepted'
    exit 1
fi
assert_environment failed-read wayland-original /run/original :0

snapshot_status=0
snapshot_output=$'WAYLAND_DISPLAY=wayland-new\nXDG_RUNTIME_DIR=/run/new\nDISPLAY=\n'
_herdr_refresh_waypipe_env
assert_environment empty-display wayland-new /run/new '<unset>'
ZSH

printf '%s\n' 'zsh Herdr Waypipe environment tests passed'
