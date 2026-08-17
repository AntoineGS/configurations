#!/usr/bin/env bash

POLKIT_UNIT_ABSENT_STATUS=${POLKIT_UNIT_ABSENT_STATUS:-10}
POLKIT_UNIT_INSPECTION_FAILED_STATUS=${POLKIT_UNIT_INSPECTION_FAILED_STATUS:-11}

polkit_unit_property() {
  local name=$1
  local path=$2
  awk -F= -v property="$name" '$1 == property { print substr($0, index($0, "=") + 1); exit }' "$path"
}

polkit_validate_unit_snapshot() {
  local path=$1
  local properties=${unit_properties:-LoadState,ActiveState,SubState,UnitFileState,MainPID,ExecMainStartTimestamp,ExecMainStartTimestampMonotonic,ActiveEnterTimestamp,ActiveEnterTimestampMonotonic,FragmentPath,Result,NeedDaemonReload}
  local property line key
  local -a requested_properties
  local -A requested=() seen=()

  IFS=',' read -r -a requested_properties <<<"$properties"
  ((${#requested_properties[@]} > 0)) || return 1
  for property in "${requested_properties[@]}"; do
    [[ -n $property && -z ${requested[$property]+present} ]] || return 1
    requested["$property"]=1
  done

  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line == *=* ]] || return 1
    key=${line%%=*}
    [[ -n ${requested[$key]+present} && -z ${seen[$key]+present} ]] || return 1
    seen["$key"]=1
  done <"$path"

  for property in "${requested_properties[@]}"; do
    [[ -n ${seen[$property]+present} ]] || return 1
  done
}

polkit_systemctl_user_show() {
  [[ -n ${live_xdg_runtime_dir:-} ]] || return "$POLKIT_UNIT_INSPECTION_FAILED_STATUS"
  if [[ -n ${live_dbus_address:-} ]]; then
    env XDG_RUNTIME_DIR="$live_xdg_runtime_dir" \
      DBUS_SESSION_BUS_ADDRESS="$live_dbus_address" systemctl --user show "$@"
  else
    env XDG_RUNTIME_DIR="$live_xdg_runtime_dir" systemctl --user show "$@"
  fi
}

polkit_snapshot_unit() {
  local output=$1
  local load_state snapshot_load_state
  local properties=${unit_properties:-LoadState,ActiveState,SubState,UnitFileState,MainPID,ExecMainStartTimestamp,ExecMainStartTimestampMonotonic,ActiveEnterTimestamp,ActiveEnterTimestampMonotonic,FragmentPath,Result,NeedDaemonReload}

  command -v systemctl >/dev/null 2>&1 || return "$POLKIT_UNIT_INSPECTION_FAILED_STATUS"
  if ! load_state=$(polkit_systemctl_user_show desktop-shell.service --property=LoadState --value 2>/dev/null); then
    return "$POLKIT_UNIT_INSPECTION_FAILED_STATUS"
  fi
  [[ -n $load_state && $load_state != *$'\n'* && $load_state != *$'\r'* ]] || return "$POLKIT_UNIT_INSPECTION_FAILED_STATUS"
  if [[ $load_state == not-found ]]; then
    rm -f -- "$output"
    return "$POLKIT_UNIT_ABSENT_STATUS"
  fi

  if ! polkit_systemctl_user_show desktop-shell.service --all --property="$properties" >"$output" 2>/dev/null; then
    rm -f -- "$output"
    return "$POLKIT_UNIT_INSPECTION_FAILED_STATUS"
  fi
  if [[ ! -s $output ]]; then
    rm -f -- "$output"
    return "$POLKIT_UNIT_INSPECTION_FAILED_STATUS"
  fi
  if ! polkit_validate_unit_snapshot "$output"; then
    rm -f -- "$output"
    return "$POLKIT_UNIT_INSPECTION_FAILED_STATUS"
  fi
  snapshot_load_state=$(polkit_unit_property LoadState "$output")
  if [[ $snapshot_load_state != "$load_state" ]]; then
    rm -f -- "$output"
    return "$POLKIT_UNIT_INSPECTION_FAILED_STATUS"
  fi
  return 0
}
