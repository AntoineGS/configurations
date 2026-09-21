#!/usr/bin/env bash
set -Eeuo pipefail

# Workaround for opencode's config watcher failing on a symlinked config dir:
# inotify_add_watch uses IN_DONT_FOLLOW|IN_ONLYDIR, so watching ~/.config/opencode
# fails with ENOTDIR and the watch is retried on every config reload. Pointing
# OPENCODE_CONFIG_DIR at the resolved path gives the watcher a real directory.
# Drop this entry once upstream resolves the global config root before watching.

usage() {
  printf 'Usage: %s --check|--apply|--help\n' "${0##*/}"
}

config_link="${OPENCODE_CONFIG_LINK:-$HOME/.config/opencode}"
env_file="${OPENCODE_ENV_FILE:-$HOME/.config/environment.d/opencode.conf}"
resolved="$(readlink -f "$config_link" || true)"
content="OPENCODE_CONFIG_DIR=$resolved"

check_env_file() {
  [[ -n "$resolved" ]] &&
    [[ -d "$resolved" ]] &&
    [[ -f "$env_file" ]] &&
    [[ "$(cat "$env_file")" == "$content" ]]
}

apply_env_file() {
  [[ -n "$resolved" ]] && [[ -d "$resolved" ]] || {
    printf '%s: %s does not resolve to a directory\n' "${0##*/}" "$config_link" >&2
    exit 1
  }
  mkdir -p "$(dirname "$env_file")"
  printf '%s\n' "$content" >"$env_file"
  # Refreshes the user manager for services started later; existing shells keep
  # the environment they were launched with until the next login.
  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload || true
  fi
}

case "${1:-}" in
  --check)
    check_env_file
    ;;
  --apply)
    apply_env_file
    ;;
  --help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
