#!/usr/bin/env bash
set -eu

mode=${1-}
source_dir=$HOME/gits/shell-picker
binary=$HOME/.local/bin/shell-picker

case "$mode" in
  check)
    test -x "$binary"
    revision=$(git -C "$source_dir" rev-parse HEAD 2>/dev/null)
    test "$("$binary" version 2>/dev/null)" = 'shell-picker dev'
    go version -m "$binary" 2>/dev/null | grep -Fq "vcs.revision=$revision"
    ;;
  install)
    (cd "$source_dir" && make build && GOBIN="$HOME/.local/bin" make install)
    test -x "$binary"
    ;;
  *)
    printf '%s\n' 'usage: manage-binary.sh {check|install}' >&2
    exit 2
    ;;
esac
