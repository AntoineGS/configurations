#!/bin/sh

set -u

herdr_bin=${HERDR_BIN_PATH:-herdr}
opencode_cli_config=${XDG_CONFIG_HOME:-$HOME/.config}/opencode/cli.json

set_opencode_animations() {
  [ -f "$opencode_cli_config" ] || return 1
  tmp=$(mktemp "$opencode_cli_config.XXXXXX") || return 1
  if jq --argjson value "$1" 'if $value == null then del(.animations) else .animations = $value end' \
    "$opencode_cli_config" >"$tmp"; then
    mv "$tmp" "$opencode_cli_config"
  else
    rm -f "$tmp"
    return 1
  fi
}

attach_with_session_cleanup() {
  cleaned_up=0
  previous_animations=
  cleanup() {
    [ "$cleaned_up" -eq 0 ] || return
    cleaned_up=1
    if command -v herdr-waypipe-env >/dev/null 2>&1; then
      herdr-waypipe-env clear >/dev/null 2>&1 || true
    fi
    [ -z "$previous_animations" ] || set_opencode_animations "$previous_animations" >/dev/null 2>&1 || true
  }

  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap cleanup EXIT

  if command -v herdr-waypipe-env >/dev/null 2>&1; then
    herdr-waypipe-env publish >/dev/null 2>&1 || true
  fi

  # Only restore what this session changed, so overlapping sessions never leave animations off.
  if command -v jq >/dev/null 2>&1; then
    animations=$(jq -c '.animations' "$opencode_cli_config" 2>/dev/null) || animations=
    case "$animations" in
    true | null) set_opencode_animations false >/dev/null 2>&1 && previous_animations=$animations ;;
    esac
  fi

  "$herdr_bin"
  status=$?

  cleanup
  trap - EXIT HUP INT TERM
  return "$status"
}

case "${1:-attach}" in
attach) attach_with_session_cleanup ;;
*)
  printf '%s\n' 'usage: ssh-session.sh [attach]' >&2
  exit 2
  ;;
esac
