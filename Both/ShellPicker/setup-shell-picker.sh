#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  printf 'Usage: %s --check|--apply|--help\n' "${0##*/}"
}

source_dir="${SHELL_PICKER_SOURCE_DIR:-$HOME/gits/shell-picker}"
binary="${SHELL_PICKER_BINARY:-$HOME/.local/bin/shell-picker}"
bin_dir="${SHELL_PICKER_BIN_DIR:-$HOME/.local/bin}"

check_binary() {
  local revision

  [[ -x "$binary" ]] &&
    revision="$(git -C "$source_dir" rev-parse HEAD 2>/dev/null)" &&
    [[ "$("$binary" version 2>/dev/null)" == 'shell-picker dev' ]] &&
    go version -m "$binary" 2>/dev/null | grep -Fq "vcs.revision=$revision"
}

case "${1:-}" in
  --check)
    check_binary
    ;;
  --apply)
    (
      cd -- "$source_dir"
      make build
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
