#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  printf 'Usage: %s --check|--apply|--help\n' "${0##*/}"
}

temp_dir="${OPENCODE_TEMP_DIR:-/tmp/opencode}"
tmpfiles_config="${OPENCODE_TMPFILES_CONFIG:-$HOME/.config/user-tmpfiles.d/opencode.conf}"

check_temp_dir() {
  [[ -d "$temp_dir" ]] &&
    [[ ! -L "$temp_dir" ]] &&
    [[ "$(stat -c %u "$temp_dir")" == "$(id -u)" ]] &&
    [[ "$(stat -c %a "$temp_dir")" == 700 ]]
}

check_timer() {
  systemctl --user is-enabled --quiet systemd-tmpfiles-clean.timer &&
    systemctl --user is-active --quiet systemd-tmpfiles-clean.timer
}

case "${1:-}" in
  --check)
    check_temp_dir && check_timer
    ;;
  --apply)
    systemd-tmpfiles --user --create "$tmpfiles_config" &&
      systemctl --user enable --now systemd-tmpfiles-clean.timer
    ;;
  --help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
