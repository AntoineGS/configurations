#!/usr/bin/env bash
# Disable the laptop's internal keyboard + touchpad while the Keyball44
# (Bluetooth) is connected, and re-enable them the moment it disconnects.
#
# Two event sources, multiplexed into one idempotent reconcile loop:
#   * udev input hotplug  - Keyball connect/disconnect (re)applies the policy.
#   * logind PrepareForSleep - on resume from sleep/hibernate, force the
#     internal devices back ON until the Keyball reconnects. Hyprland keeps
#     runtime `hl.device` config keyed by name, so a device re-enumerated by
#     the system-sleep rebind hooks could otherwise come back still-disabled
#     and lock you out.
#
# Self-heals: if the service restarts while the Keyball is gone, the startup
# reconcile re-enables the internal devices.
#
# Mirrors the watch-rustdesk-submap.service pattern.
# Requirements: hyprctl, udevadm, gdbus
set -euo pipefail

# Resolve the running Hyprland instance up front. This systemd user unit can
# start before UWSM imports the compositor environment
# (HYPRLAND_INSTANCE_SIGNATURE) into the session, and a process only ever sees
# the environment it was spawned with -- so the hyprctl calls below would
# otherwise silently fail for the entire session. Prefer the env var when it
# names a live instance socket; otherwise discover the newest instance from the
# runtime socket dir. Block until a live socket exists, then export it so
# hyprctl inherits it.
: "${XDG_RUNTIME_DIR:=/run/user/$UID}"
_hypr_dir="$XDG_RUNTIME_DIR/hypr"
_sig=""
while :; do
  if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} \
    && -S "$_hypr_dir/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock" ]]; then
    _sig=$HYPRLAND_INSTANCE_SIGNATURE
    break
  fi
  _candidate=$(ls -t "$_hypr_dir" 2>/dev/null | head -1 || true)
  if [[ -n $_candidate && -S "$_hypr_dir/$_candidate/.socket2.sock" ]]; then
    _sig=$_candidate
    break
  fi
  sleep 2
done
export HYPRLAND_INSTANCE_SIGNATURE="$_sig"

# Substring identifying the external keyboard in /proc/bus/input/devices.
EXTERNAL_KB_MATCH=${EXTERNAL_KB_MATCH:-Keyball44}

# Hyprland device names to toggle (see `hyprctl devices`).
INTERNAL_DEVICES=(
  "at-translated-set-2-keyboard"
  "elan-touchpad"
)

last_state=""

external_present() {
  grep -qi "$EXTERNAL_KB_MATCH" /proc/bus/input/devices
}

# $1 = true|false -> set `enabled` on every internal device.
# Returns non-zero if any hyprctl call fails (e.g. Hyprland not up yet).
set_internal_enabled() {
  local enabled="$1" rc=0
  for dev in "${INTERNAL_DEVICES[@]}"; do
    hyprctl eval "hl.device({ name = \"${dev}\", enabled = ${enabled} })" \
      >/dev/null 2>&1 || rc=1
  done
  return "$rc"
}

# Safety: whenever this watcher exits (service stop/restart, udevadm dying),
# restore the internal devices so you can never be left without a keyboard.
# The next startup reconcile re-disables them if the Keyball is still present.
cleanup() { set_internal_enabled true || true; }
trap cleanup EXIT
trap 'exit 0' INT TERM HUP

reconcile() {
  local desired bool
  if external_present; then
    desired="disabled"   # external keyboard connected -> internal off
    bool=false
  else
    desired="enabled"    # external keyboard gone -> internal back on
    bool=true
  fi

  [ "$desired" = "$last_state" ] && return 0

  # Only cache the new state once Hyprland actually accepted the change,
  # so a failed apply (e.g. during startup) is retried on the next event.
  if set_internal_enabled "$bool"; then
    last_state="$desired"
  fi
}

# Resume handler: re-enable the internal devices and clear the cached state so
# the next reconcile re-applies based on actual Keyball presence. Guarantees a
# working keyboard on wake even if the Keyball is out of range, until it
# reconnects.
force_enable_internal() {
  set_internal_enabled true || true
  last_state="enabled"
}

# Apply once on startup, retrying until Hyprland answers.
for _ in $(seq 1 30); do
  reconcile
  [ -n "$last_state" ] && break
  sleep 1
done

# Multiplex both event sources into one reader and react forever:
#   INPUT  - udev input hotplug; every per-device line ends in "(input)".
#   SLEEP  - logind PrepareForSleep; "(false)" means resuming from sleep.
# reconcile() and force_enable_internal() are idempotent. If either producer
# dies the reader ends, the script exits, and the service (Restart=on-failure)
# brings us back, re-reconciling.
{
  stdbuf -oL -eL udevadm monitor --udev --subsystem-match=input 2>/dev/null \
    | stdbuf -oL sed 's/^/INPUT /' &
  gdbus monitor --system --dest org.freedesktop.login1 2>/dev/null \
    | stdbuf -oL grep --line-buffered PrepareForSleep \
    | stdbuf -oL sed 's/^/SLEEP /' &
  wait
} |
while read -r tag rest; do  # default IFS: split first word (tag) from the rest
  case "$tag" in
    INPUT) case "$rest" in *"(input)"*)  reconcile ;; esac ;;
    SLEEP) case "$rest" in *"(false)"*)  force_enable_internal ;; esac ;;
  esac
done
