#!/usr/bin/env bash

readonly OSD_RUNTIME_IDENTITY_ATTEMPTS=100
readonly OSD_RUNTIME_IDENTITY_DELAY=0.01
readonly OSD_RUNTIME_CLEANUP_ATTEMPTS=50
readonly OSD_RUNTIME_CLEANUP_DELAY=0.1

osd_runtime_readlink_executable() {
  readlink -f -- "$1"
}

osd_runtime_process_start_time() {
  local pid=$1
  local stat_line
  local stat_tail
  local -a fields

  [[ $pid =~ ^[1-9][0-9]*$ && -r "/proc/$pid/stat" ]] || return 1
  stat_line=$(<"/proc/$pid/stat")
  stat_tail=${stat_line##*) }
  read -r -a fields <<<"$stat_tail"
  (( ${#fields[@]} >= 20 )) || return 1
  [[ ${fields[19]} =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "${fields[19]}"
}

osd_runtime_process_parent_pid() {
  local pid=$1
  local parent_pid

  [[ $pid =~ ^[1-9][0-9]*$ && -r "/proc/$pid/status" ]] || return 1
  parent_pid=$(awk '/^PPid:/ { print $2; exit }' "/proc/$pid/status")
  [[ $parent_pid =~ ^[1-9][0-9]*$ ]] || return 1
  printf '%s\n' "$parent_pid"
}

osd_runtime_process_state() {
  local pid=$1
  local stat_line
  local stat_tail
  local -a fields

  [[ $pid =~ ^[1-9][0-9]*$ && -r "/proc/$pid/stat" ]] || return 1
  stat_line=$(<"/proc/$pid/stat")
  stat_tail=${stat_line##*) }
  read -r -a fields <<<"$stat_tail"
  (( ${#fields[@]} >= 1 )) || return 1
  printf '%s\n' "${fields[0]}"
}

osd_runtime_process_executable() {
  local pid=$1
  local executable

  [[ $pid =~ ^[1-9][0-9]*$ && -L "/proc/$pid/exe" ]] || return 1
  executable=$(osd_runtime_readlink_executable "/proc/$pid/exe") || return 1
  [[ -n $executable && $executable != *$'\n'* ]] || return 1
  printf '%s\n' "$executable"
}

osd_runtime_resolve_executable() {
  local command_name=$1
  local command_path
  local executable

  [[ -n $command_name ]] || return 1
  command_path=$(command -v "$command_name" 2>/dev/null) || return 1
  [[ $command_path == /* && -x $command_path && $command_path != *$'\n'* ]] || return 1
  executable=$(osd_runtime_readlink_executable "$command_path") || return 1
  [[ -x $executable && $executable != *$'\n'* ]] || return 1
  printf '%s\n' "$executable"
}

osd_runtime_capture_pending_identity() {
  local pid=$1
  local expected_parent_pid=$2
  local parent_pid
  local start_time
  local executable

  for ((attempt = 0; attempt < OSD_RUNTIME_IDENTITY_ATTEMPTS; attempt++)); do
    parent_pid=$(osd_runtime_process_parent_pid "$pid" 2>/dev/null || true)
    if [[ $parent_pid == "$expected_parent_pid" ]]; then
      start_time=$(osd_runtime_process_start_time "$pid" 2>/dev/null || true)
      executable=$(osd_runtime_process_executable "$pid" 2>/dev/null || true)
      if [[ -n $start_time && -n $executable ]]; then
        printf '%s\t%s\t%s\n' "$start_time" "$executable" "$parent_pid"
        return 0
      fi
    fi
    sleep "$OSD_RUNTIME_IDENTITY_DELAY"
  done

  return 1
}

osd_runtime_promote_child_identity() {
  local pid=$1
  local expected_parent_pid=$2
  local expected_executable=$3
  local pending_start_time=$4
  local parent_pid
  local start_time
  local executable
  local stable_parent_pid
  local stable_start_time
  local stable_executable

  [[ -n $expected_executable && -n $pending_start_time ]] || return 1
  for ((attempt = 0; attempt < OSD_RUNTIME_IDENTITY_ATTEMPTS; attempt++)); do
    parent_pid=$(osd_runtime_process_parent_pid "$pid" 2>/dev/null || true)
    start_time=$(osd_runtime_process_start_time "$pid" 2>/dev/null || true)
    executable=$(osd_runtime_process_executable "$pid" 2>/dev/null || true)
    if [[ $parent_pid == "$expected_parent_pid" &&
      $start_time == "$pending_start_time" && $executable == "$expected_executable" ]]; then
      sleep "$OSD_RUNTIME_IDENTITY_DELAY"
      stable_parent_pid=$(osd_runtime_process_parent_pid "$pid" 2>/dev/null || true)
      stable_start_time=$(osd_runtime_process_start_time "$pid" 2>/dev/null || true)
      stable_executable=$(osd_runtime_process_executable "$pid" 2>/dev/null || true)
      if [[ $stable_parent_pid == "$expected_parent_pid" &&
        $stable_start_time == "$pending_start_time" && $stable_executable == "$expected_executable" ]]; then
        printf '%s\t%s\t%s\n' "$stable_start_time" "$stable_executable" "$stable_parent_pid"
        return 0
      fi
    fi
    sleep "$OSD_RUNTIME_IDENTITY_DELAY"
  done

  return 1
}

osd_runtime_identity_matches() {
  local pid=$1
  local expected_start_time=$2
  local expected_executable=$3
  local expected_parent_pid=$4

  [[ -n $expected_start_time && -n $expected_executable && -n $expected_parent_pid ]] || return 1
  [[ $(osd_runtime_process_start_time "$pid" 2>/dev/null || true) == "$expected_start_time" ]] || return 1
  [[ $(osd_runtime_process_executable "$pid" 2>/dev/null || true) == "$expected_executable" ]] || return 1
  [[ $(osd_runtime_process_parent_pid "$pid" 2>/dev/null || true) == "$expected_parent_pid" ]]
}

osd_runtime_reap_if_exited() {
  local pid=$1
  local state

  if [[ ! -e "/proc/$pid/stat" ]]; then
    wait "$pid" 2>/dev/null || true
    return 0
  fi
  state=$(osd_runtime_process_state "$pid" 2>/dev/null || true)
  case "$state" in
    Z|X)
      wait "$pid" 2>/dev/null || true
      return 0
      ;;
    *) return 1 ;;
  esac
}

osd_runtime_wait_for_reap() {
  local pid=$1

  for ((attempt = 0; attempt < OSD_RUNTIME_CLEANUP_ATTEMPTS; attempt++)); do
    osd_runtime_reap_if_exited "$pid" && return 0
    sleep "$OSD_RUNTIME_CLEANUP_DELAY"
  done
  return 1
}

osd_runtime_cleanup_child() {
  local pid=$1
  local expected_start_time=$2
  local expected_executable=$3
  local expected_parent_pid=$4

  osd_runtime_identity_matches "$pid" "$expected_start_time" "$expected_executable" "$expected_parent_pid" || return 0
  kill -TERM -- "$pid" 2>/dev/null || true
  for ((attempt = 0; attempt < OSD_RUNTIME_CLEANUP_ATTEMPTS; attempt++)); do
    if ! osd_runtime_identity_matches "$pid" "$expected_start_time" "$expected_executable" "$expected_parent_pid"; then
      osd_runtime_reap_if_exited "$pid"
      return $?
    fi
    sleep "$OSD_RUNTIME_CLEANUP_DELAY"
  done

  if osd_runtime_identity_matches "$pid" "$expected_start_time" "$expected_executable" "$expected_parent_pid"; then
    kill -KILL -- "$pid" 2>/dev/null || true
  fi
  osd_runtime_wait_for_reap "$pid"
}

osd_runtime_cleanup_pending_child() {
  local pid=$1
  local pending_start_time=$2
  local pending_executable=$3
  local expected_parent_pid=$4
  local expected_executable=${5-}

  if osd_runtime_identity_matches "$pid" "$pending_start_time" "$pending_executable" "$expected_parent_pid"; then
    osd_runtime_cleanup_child "$pid" "$pending_start_time" "$pending_executable" "$expected_parent_pid"
  elif [[ -n $expected_executable ]] &&
    osd_runtime_identity_matches "$pid" "$pending_start_time" "$expected_executable" "$expected_parent_pid"; then
    osd_runtime_cleanup_child "$pid" "$pending_start_time" "$expected_executable" "$expected_parent_pid"
  fi
}

osd_runtime_cleanup_pending_identity() {
  local pid=$1
  local expected_parent_pid=$2
  local expected_executable=$3
  local identity
  local start_time
  local executable
  local parent_pid

  identity=$(osd_runtime_capture_pending_identity "$pid" "$expected_parent_pid" 2>/dev/null) || {
    osd_runtime_reap_if_exited "$pid"
    return $?
  }
  IFS=$'\t' read -r start_time executable parent_pid <<<"$identity"
  osd_runtime_cleanup_pending_child "$pid" "$start_time" "$executable" "$parent_pid" "$expected_executable" || return 1
  osd_runtime_reap_if_exited "$pid"
}
