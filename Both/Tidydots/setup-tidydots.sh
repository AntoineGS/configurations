#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  printf 'Usage: %s --check|--apply|--help\n' "${0##*/}"
}

latest_commit="50586611417de9f264df52e7f2e227ae19975a94"
repository="${TIDYDOTS_REPOSITORY:-https://github.com/AntoineGS/tidydots.git}"
source_dir="${TIDYDOTS_SOURCE_DIR:-$HOME/gits/tidydots}"
go_bin="$(go env GOBIN)"
[[ -n "$go_bin" ]] || go_bin="$(go env GOPATH)/bin"
bin_dir="${TIDYDOTS_BIN_DIR:-$go_bin}"
binary="${TIDYDOTS_BINARY:-$bin_dir/tidydots}"

binary_revision() {
  go version -m "$binary" 2>/dev/null |
    sed -n 's/^[[:space:]]*build[[:space:]]\+vcs\.revision=//p'
}

check_binary() {
  [[ -x "$binary" ]] &&
    [[ "$(binary_revision)" == "$latest_commit" ]]
}

prepare_source() {
  local revision

  if [[ ! -e "$source_dir" ]]; then
    mkdir -p -- "$(dirname -- "$source_dir")"
    git clone -- "$repository" "$source_dir"
  fi

  if [[ -n "$(git -C "$source_dir" status --porcelain)" ]]; then
    printf 'tidydots: refusing to install from a dirty checkout at %s\n' "$source_dir" >&2
    return 1
  fi

  revision="$(git -C "$source_dir" rev-parse HEAD)"
  if [[ "$revision" != "$latest_commit" ]]; then
    git -C "$source_dir" pull --ff-only
    revision="$(git -C "$source_dir" rev-parse HEAD)"
  fi

  if [[ "$revision" != "$latest_commit" ]]; then
    printf 'tidydots: expected commit %s, found %s after git pull\n' "$latest_commit" "$revision" >&2
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
