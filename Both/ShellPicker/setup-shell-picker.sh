#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  printf 'Usage: %s --check|--apply|--help\n' "${0##*/}"
}

latest_commit="3c44d2ecf7c7b315aa29e4660aa0f82861950d84"
repository="${SHELL_PICKER_REPOSITORY:-https://github.com/AntoineGS/shell-picker.git}"
source_dir="${SHELL_PICKER_SOURCE_DIR:-$HOME/gits/shell-picker}"
binary="${SHELL_PICKER_BINARY:-$HOME/.local/bin/shell-picker}"
bin_dir="${SHELL_PICKER_BIN_DIR:-$HOME/.local/bin}"

check_binary() {
  [[ -x "$binary" ]] &&
    [[ "$("$binary" version 2>/dev/null)" == "shell-picker $latest_commit" ]]
}

prepare_source() {
  local revision

  if [[ ! -e "$source_dir" ]]; then
    mkdir -p -- "$(dirname -- "$source_dir")"
    git clone -- "$repository" "$source_dir"
  fi

  if [[ -n "$(git -C "$source_dir" status --porcelain)" ]]; then
    printf 'shell-picker: refusing to install from a dirty checkout at %s\n' "$source_dir" >&2
    return 1
  fi

  revision="$(git -C "$source_dir" rev-parse HEAD)"
  if [[ "$revision" != "$latest_commit" ]]; then
    git -C "$source_dir" pull --ff-only
    revision="$(git -C "$source_dir" rev-parse HEAD)"
  fi

  if [[ "$revision" != "$latest_commit" ]]; then
    printf 'shell-picker: expected commit %s, found %s after git pull\n' "$latest_commit" "$revision" >&2
    return 1
  fi
}

case "${1:-}" in
  --check)
    check_binary
    ;;
  --apply)
    (
      prepare_source
      cd -- "$source_dir"
      GOBIN="$bin_dir" make install
    )
    ;;
  --help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
