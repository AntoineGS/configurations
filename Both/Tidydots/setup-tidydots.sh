#!/usr/bin/env bash
# Update the locally installed tidydots binary from the remote default branch.
# Requires Bash 4.4+, Git, Go, GNU/coreutils timeout, env, and make for --apply.
set -Eeuo pipefail

if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4))); then
  printf 'tidydots: Bash 4.4 or newer is required\n' >&2
  exit 3
fi
shopt -s inherit_errexit

readonly DEFAULT_REPOSITORY='https://github.com/AntoineGS/tidydots.git'
readonly DEFAULT_SOURCE_SUFFIX='/gits/tidydots'
readonly REMOTE_LOOKUP_TIMEOUT='5s'
readonly NONINTERACTIVE_SSH='ssh -oBatchMode=yes -oConnectTimeout=5'

repository=''
source_dir=''
bin_dir=''
binary=''
installed_revision=''
remote_ref=''
remote_revision=''

usage() {
  printf 'Usage: %s --check|--apply|--help\n' "${0##*/}"
}

fail() {
  printf 'tidydots: %s\n' "$*" >&2
  exit 3
}

require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null 2>&1 || fail "required command not found: $command_name"
}

resolve_go_bin_dir() {
  local gobin gopath first_gopath

  require_command go
  if ! gobin="$(go env GOBIN 2>/dev/null)"; then
    fail 'cannot determine Go binary directory'
  fi
  if [[ -n "$gobin" ]]; then
    bin_dir="$gobin"
    return 0
  fi

  if ! gopath="$(go env GOPATH 2>/dev/null)"; then
    fail 'cannot determine Go workspace'
  fi
  first_gopath="${gopath%%:*}"
  [[ -n "$first_gopath" ]] || fail 'Go reported an empty workspace'
  bin_dir="$first_gopath/bin"
}

resolve_verification_path() {
  binary="${TIDYDOTS_BINARY:-}"
  bin_dir="${TIDYDOTS_BIN_DIR:-}"

  if [[ -z "$binary" ]]; then
    [[ -n "$bin_dir" ]] || resolve_go_bin_dir
    binary="${bin_dir%/}/tidydots"
  fi
}

resolve_apply_paths() {
  local install_binary

  resolve_verification_path
  [[ -n "$bin_dir" ]] || resolve_go_bin_dir
  if [[ "$bin_dir" == / ]]; then
    install_binary='/tidydots'
  else
    install_binary="${bin_dir%/}/tidydots"
  fi
  [[ "$binary" == "$install_binary" ]] || \
    fail 'TIDYDOTS_BINARY and TIDYDOTS_BIN_DIR do not designate the same tidydots binary'
}

read_installed_revision() {
  local metadata line revision=''

  if ! metadata="$(go version -m "$binary" 2>/dev/null)"; then
    fail 'cannot read installed binary metadata'
  fi

  while IFS= read -r line; do
    if [[ "$line" == *vcs.revision* ]]; then
      if [[ "$line" =~ ^[[:space:]]*build[[:space:]]+vcs\.revision=([0-9a-f]{40}|[0-9a-f]{64})[[:space:]]*$ ]]; then
        [[ -z "$revision" ]] || fail 'installed binary has multiple VCS revisions'
        revision="${BASH_REMATCH[1]}"
      else
        fail 'installed binary has invalid VCS revision metadata'
      fi
    fi
  done <<< "$metadata"

  [[ -n "$revision" ]] || fail 'installed binary has no VCS revision metadata'
  installed_revision="$revision"
}

run_noninteractive_git() {
  env \
    GIT_TERMINAL_PROMPT=0 \
    GIT_ASKPASS=false \
    SSH_ASKPASS=false \
    GIT_SSH_COMMAND="$NONINTERACTIVE_SSH" \
    git -c credential.helper= -c credential.interactive=false "$@"
}

resolve_remote() {
  local remote_output value name extra

  require_command timeout
  require_command git
  require_command env
  if ! remote_output="$(timeout --signal=KILL "$REMOTE_LOOKUP_TIMEOUT" env \
    GIT_TERMINAL_PROMPT=0 \
    GIT_ASKPASS=false \
    SSH_ASKPASS=false \
    GIT_SSH_COMMAND="$NONINTERACTIVE_SSH" \
    git -c credential.helper= -c credential.interactive=false \
    ls-remote --symref -- "$repository" HEAD 2>/dev/null)"; then
    fail 'cannot determine remote HEAD (lookup failed or timed out)'
  fi

  remote_ref=''
  remote_revision=''
  while IFS=$'\t' read -r value name extra; do
    [[ "$name" == HEAD && -z "$extra" ]] || fail 'invalid remote HEAD response'
    if [[ "$value" == 'ref: refs/heads/'* ]]; then
      [[ -z "$remote_ref" ]] || fail 'duplicate remote HEAD reference'
      remote_ref="${value#ref: }"
    elif [[ "$value" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]; then
      [[ -z "$remote_revision" ]] || fail 'duplicate remote HEAD revision'
      remote_revision="$value"
    else
      fail 'invalid remote HEAD response'
    fi
  done <<< "$remote_output"

  [[ -n "$remote_ref" && -n "$remote_revision" ]] || fail 'remote HEAD has no branch or revision'
  [[ "$remote_ref" == refs/heads/* ]] || fail 'invalid remote default branch'
  if ! run_noninteractive_git check-ref-format "$remote_ref" >/dev/null 2>&1; then
    fail 'invalid remote default branch'
  fi
}

verify_checkout_root() {
  local actual_root expected_root

  if ! actual_root="$(run_noninteractive_git -C "$source_dir" rev-parse --show-toplevel 2>/dev/null)"; then
    fail 'source directory is not a Git repository'
  fi
  if ! expected_root="$(cd -- "$source_dir" && pwd -P)"; then
    fail 'cannot resolve source checkout path'
  fi
  [[ "$actual_root" == "$expected_root" ]] || fail 'source path is not the repository root'
}

verify_checkout_identity() {
  local origin_url

  if ! origin_url="$(run_noninteractive_git -C "$source_dir" remote get-url origin 2>/dev/null)"; then
    fail 'source checkout has no readable origin remote'
  fi
  [[ "$origin_url" == "$repository" ]] || fail 'source checkout origin does not match configured repository'
}

verify_checkout_branch() {
  local expected_ref="$1" current_ref

  if ! current_ref="$(run_noninteractive_git -C "$source_dir" symbolic-ref --quiet HEAD 2>/dev/null)"; then
    fail 'source checkout is detached; refusing to update it'
  fi
  [[ "$current_ref" == "$expected_ref" ]] || fail 'source checkout is not on the remote default branch'
}

verify_checkout_clean() {
  local status_output

  if ! status_output="$(run_noninteractive_git -C "$source_dir" status --porcelain --untracked-files=all 2>/dev/null)"; then
    fail 'cannot inspect source checkout status'
  fi
  [[ -z "$status_output" ]] || fail 'refusing to update a dirty source checkout'
}

checkout_revision() {
  local revision

  if ! revision="$(run_noninteractive_git -C "$source_dir" rev-parse HEAD 2>/dev/null)"; then
    fail 'cannot read source revision'
  fi
  printf '%s' "$revision"
}

verify_checkout_revision() {
  local expected_revision="$1" revision

  revision="$(checkout_revision)"
  [[ "$revision" == "$expected_revision" ]] || fail 'checkout does not match remote HEAD; refusing to build'
}

fetch_and_fast_forward() {
  local fetched_revision

  if ! run_noninteractive_git -C "$source_dir" fetch --no-tags -- origin "$remote_ref" >/dev/null 2>&1; then
    fail 'fetch failed'
  fi
  if ! fetched_revision="$(run_noninteractive_git -C "$source_dir" rev-parse FETCH_HEAD 2>/dev/null)"; then
    fail 'cannot read fetched revision'
  fi
  [[ "$fetched_revision" == "$remote_revision" ]] || fail 'remote moved during update; retry'
  if ! run_noninteractive_git -C "$source_dir" merge --ff-only "$remote_revision" >/dev/null 2>&1; then
    fail 'checkout cannot fast-forward to remote HEAD'
  fi
}

prepare_source() {
  local remote_branch

  remote_branch="${remote_ref#refs/heads/}"
  [[ -n "$remote_branch" ]] || fail 'invalid remote default branch'
  if ! run_noninteractive_git check-ref-format --branch "$remote_branch" >/dev/null 2>&1; then
    fail 'invalid remote default branch'
  fi

  if [[ -e "$source_dir" || -L "$source_dir" ]]; then
    [[ -d "$source_dir" && ! -L "$source_dir" ]] || fail 'source path is not a real checkout directory'
    verify_checkout_root
    verify_checkout_identity
    verify_checkout_branch "$remote_ref"
    verify_checkout_clean
    fetch_and_fast_forward
  else
    if ! mkdir -p -- "$(dirname -- "$source_dir")"; then
      fail 'cannot create source checkout parent'
    fi
    if ! run_noninteractive_git clone --branch "$remote_branch" -- "$repository" "$source_dir" >/dev/null 2>&1; then
      fail 'clone failed'
    fi
  fi

  verify_checkout_root
  verify_checkout_identity
  verify_checkout_branch "$remote_ref"
  verify_checkout_clean
  verify_checkout_revision "$remote_revision"
}

run_check() {
  resolve_verification_path
  [[ -x "$binary" ]] || exit 1
  require_command go
  read_installed_revision
  resolve_remote
  [[ "$installed_revision" == "$remote_revision" ]] && exit 0
  exit 2
}

run_apply() {
  local expected_ref expected_revision

  resolve_apply_paths
  if [[ -n "${TIDYDOTS_SOURCE_DIR:-}" ]]; then
    source_dir="$TIDYDOTS_SOURCE_DIR"
  else
    [[ -n "${HOME:-}" ]] || fail 'HOME is required when TIDYDOTS_SOURCE_DIR is unset'
    source_dir="$HOME$DEFAULT_SOURCE_SUFFIX"
  fi
  require_command go
  require_command make
  resolve_remote
  expected_ref="$remote_ref"
  expected_revision="$remote_revision"
  prepare_source

  if ! (cd -- "$source_dir" && GOBIN="$bin_dir" make install); then
    fail 'make install failed'
  fi
  [[ -x "$binary" ]] || fail 'make install did not produce an executable tidydots binary'
  read_installed_revision
  [[ "$installed_revision" == "$expected_revision" ]] || \
    fail 'installed binary revision does not match remote HEAD'

  resolve_remote
  [[ "$remote_ref" == "$expected_ref" && "$remote_revision" == "$expected_revision" ]] || \
    fail 'remote advanced during update; retry'
  printf 'tidydots: installed remote HEAD\n'
}

case "${1:-}" in
  --help)
    [[ "$#" == 1 ]] || { usage >&2; exit 3; }
    usage
    exit 0
    ;;
  --check|--apply)
    [[ "$#" == 1 ]] || { usage >&2; exit 3; }
    ;;
  *)
    usage >&2
    exit 3
    ;;
esac

repository="${TIDYDOTS_REPOSITORY:-$DEFAULT_REPOSITORY}"

case "$1" in
  --check) run_check ;;
  --apply) run_apply ;;
esac
