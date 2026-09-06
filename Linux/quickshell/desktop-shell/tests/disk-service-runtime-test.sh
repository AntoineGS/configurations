#!/usr/bin/env bash
set -Eeuo pipefail

if ! command -v quickshell >/dev/null 2>&1; then
  printf 'SKIP: quickshell unavailable\n'
  exit 0
fi
if ! command -v timeout >/dev/null 2>&1; then
  printf 'FAIL: timeout unavailable\n' >&2
  exit 1
fi

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)
shell_dir="$repo_root/Linux/quickshell/desktop-shell"
fixture="$shell_dir/tests/fixtures/disk/fake-status-lifecycle"
tmp_dir=$(mktemp -d)
shell_pid=""
log_file="$tmp_dir/quickshell.log"

print_log() {
  while IFS= read -r line || [[ -n $line ]]; do
    printf '%s\n' "$line"
  done <"$log_file"
}

cleanup() {
  if [[ -n $shell_pid ]]; then
    kill "$shell_pid" 2>/dev/null || true
    wait "$shell_pid" 2>/dev/null || true
  fi
  rm -rf -- "$tmp_dir"
}
trap cleanup EXIT

bin_dir="$tmp_dir/bin"
home_dir="$tmp_dir/home"
runtime_dir="$tmp_dir/runtime"
mkdir -p -- "$bin_dir" "$home_dir/.config" "$home_dir/.local/state" "$runtime_dir"
chmod 0700 -- "$runtime_dir"

fake_executable="$bin_dir/fake-status-lifecycle"
cp -- "$fixture" "$fake_executable"
chmod 0755 -- "$fake_executable"

lifecycle_log="$tmp_dir/lifecycle.log"
lifecycle_mode="$tmp_dir/mode"
lifecycle_held="$tmp_dir/held"
lifecycle_release="$tmp_dir/release"
lifecycle_old_output="$tmp_dir/old-output"
: >"$lifecycle_log"
printf '%s\n' initial >"$lifecycle_mode"

if timeout --foreground --kill-after=2s 12s env \
  HOME="$home_dir" \
  XDG_CONFIG_HOME="$home_dir/.config" \
  XDG_STATE_HOME="$home_dir/.local/state" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  QT_QPA_PLATFORM=offscreen \
  DESKTOP_SHELL_TEST_NO_SURFACES=1 \
  DISK_FIXTURE_LIFECYCLE_EXECUTABLE="$fake_executable" \
  DISK_FIXTURE_MISSING_EXECUTABLE="$bin_dir/missing" \
  DISK_FIXTURE_LIFECYCLE_LOG="$lifecycle_log" \
  DISK_FIXTURE_LIFECYCLE_MODE="$lifecycle_mode" \
  DISK_FIXTURE_LIFECYCLE_HELD="$lifecycle_held" \
  DISK_FIXTURE_LIFECYCLE_RELEASE="$lifecycle_release" \
  DISK_FIXTURE_LIFECYCLE_OLD_OUTPUT="$lifecycle_old_output" \
  quickshell -n -p "$shell_dir/disk-service-runtime-test.qml" >"$log_file" 2>&1; then
  exit_code=0
else
  exit_code=$?
fi

if ((exit_code != 0)); then
  printf 'FAIL: disk lifecycle fixture exited with %s\n' "$exit_code" >&2
  print_log >&2
  exit 1
fi

log_text=$(<"$log_file")
if [[ $log_text != *"Disk lifecycle fixture passed"* ]]; then
  printf 'FAIL: disk lifecycle fixture did not report success\n' >&2
  print_log >&2
  exit 1
fi

while IFS= read -r line || [[ -n $line ]]; do
  if [[ $line == *"Disk lifecycle fixture passed"* ]]; then
    printf '%s\n' "$line"
  fi
done <"$log_file"
