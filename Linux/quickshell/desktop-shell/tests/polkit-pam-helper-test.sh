#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
HELPER="$ROOT/Linux/os/helpers/desktop-shell-polkit-pam"
CONFIG="$ROOT/tidydots.yaml"
fixture="$(mktemp -d)"
pam_dir="$fixture/pam"
stdout_file="$fixture/stdout"
stderr_file="$fixture/stderr"
expected_file="$fixture/expected"
probe_status=0
max_unique_files=64
max_total_bytes=4194304
max_total_lines=16384

trap 'rm -rf -- "$fixture"' EXIT HUP INT TERM
mkdir -p -- "$pam_dir"

fail() {
  printf 'polkit-pam-helper-test: %s\n' "$1" >&2
  exit 1
}

write_pam() {
  local name=$1
  local content=$2
  printf '%s' "$content" >"$pam_dir/$name"
}

run_probe() {
  probe_status=0
  : >"$stdout_file"
  : >"$stderr_file"
  DESKTOP_SHELL_PAM_DIR="$pam_dir" "$HELPER" >"$stdout_file" 2>"$stderr_file" || probe_status=$?
}

assert_status() {
  local expected=$1
  [[ $probe_status == "$expected" ]] || fail "expected status $expected, got $probe_status"
}

assert_stdout() {
  local expected=$1
  printf '%s\n' "$expected" >"$expected_file"
  cmp -s "$expected_file" "$stdout_file" || {
    printf 'expected stdout:\n%sactual stdout:\n%s' \
      "$(<"$expected_file")" "$(<"$stdout_file")" >&2
    fail 'stdout was not the exact boolean result'
  }
}

assert_no_stdout() {
  [[ ! -s $stdout_file ]] || fail 'failure emitted a result on stdout'
}

write_pam polkit-1 $'auth [success=1 default=ignore] /usr/lib/security/pam_fprintd.so\naccount required pam_fprintd.so\n'
run_probe
assert_status 0
assert_stdout true

write_pam polkit-1 $'auth required pam_unix.so\naccount required pam_fprintd.so\n'
run_probe
assert_status 0
assert_stdout false

write_pam polkit-1 $'auth include common-auth\nauth substack local-auth\n'
write_pam common-auth $'@include shared-auth\n'
write_pam shared-auth $'auth optional pam_fprintd.so\n'
write_pam local-auth $'account required pam_fprintd.so\nauth required pam_unix.so\n'
run_probe
assert_status 0
assert_stdout true

write_pam polkit-1 $'# auth required pam_fprintd.so\nauth required pam_unix.so # pam_fprintd.so\nauth required pam_unix.so /usr/lib/security/pam_fprintd.so\nauth required pam_fprintd.so.extra\n'
run_probe
assert_status 0
assert_stdout false

write_pam polkit-1 $'auth required\n'
run_probe
assert_status 1
assert_no_stdout

write_pam polkit-1 $'auth include common-auth extra\n'
write_pam common-auth $'auth required pam_unix.so\n'
run_probe
assert_status 1
assert_no_stdout

write_pam polkit-1 $'auth include ../outside\n'
run_probe
assert_status 1
assert_no_stdout

write_pam polkit-1 $'@include ../outside\n'
run_probe
assert_status 1
assert_no_stdout

write_pam polkit-1 $'auth include missing-service\n'
run_probe
assert_status 1
assert_no_stdout

mkdir -p -- "$pam_dir/not-a-file"
write_pam polkit-1 $'auth include not-a-file\n'
run_probe
assert_status 1
assert_no_stdout

write_pam polkit-1 $'@include cycle-a\n'
write_pam cycle-a $'@include cycle-b\n'
write_pam cycle-b $'@include cycle-a\n'
run_probe
assert_status 1
assert_no_stdout

for index in {0..17}; do
  if ((index == 17)); then
    write_pam "depth-$index" $'auth required pam_unix.so\n'
  else
    write_pam "depth-$index" "@include depth-$((index + 1))\n"
  fi
done
write_pam polkit-1 $'@include depth-0\n'
run_probe
assert_status 1
assert_no_stdout

for index in {0..15}; do
  if ((index == 15)); then
    write_pam "depth-exact-$index" $'auth required pam_unix.so\n'
  else
    printf -v include_line '@include depth-exact-%s\n' "$((index + 1))"
    write_pam "depth-exact-$index" "$include_line"
  fi
done
write_pam polkit-1 $'@include depth-exact-0\n'
run_probe
assert_status 0
assert_stdout false

for index in {0..16}; do
  if ((index == 16)); then
    write_pam "depth-overflow-$index" $'auth required pam_unix.so\n'
  else
    printf -v include_line '@include depth-overflow-%s\n' "$((index + 1))"
    write_pam "depth-overflow-$index" "$include_line"
  fi
done
write_pam polkit-1 $'@include depth-overflow-0\n'
run_probe
assert_status 1
assert_no_stdout

write_pam shared-fanout $'auth sufficient pam_fprintd.so\n'
fanout=''
for _ in {1..128}; do
  fanout+=$'@include shared-fanout\n'
done
write_pam polkit-1 "$fanout"
run_probe
assert_status 0
assert_stdout true

unique_includes=''
for index in $(seq 0 "$max_unique_files"); do
  write_pam "unique-$index" $'auth required pam_unix.so\n'
  unique_includes+="$(printf '@include unique-%s\n' "$index")"$'\n'
done
write_pam polkit-1 "$unique_includes"
run_probe
assert_status 1
assert_no_stdout

byte_includes=''
for index in {0..4}; do
  truncate -s "$((max_total_bytes / 4))" "$pam_dir/bytes-$index"
  byte_includes+="$(printf '@include bytes-%s\n' "$index")"$'\n'
done
write_pam polkit-1 "$byte_includes"
run_probe
assert_status 1
assert_no_stdout

line_content=''
for _ in $(seq 1 "$((max_total_lines + 1))"); do
  line_content+=$'auth required pam_unix.so\n'
done
write_pam lines-overflow "$line_content"
write_pam polkit-1 $'@include lines-overflow\n'
run_probe
assert_status 1
assert_no_stdout

probe_status=0
DESKTOP_SHELL_PAM_DIR=relative "$HELPER" >"$stdout_file" 2>"$stderr_file" || probe_status=$?
[[ $probe_status != 0 ]] || fail 'relative PAM override was accepted'
assert_no_stdout

[[ -x $HELPER ]] || fail 'PAM helper is not executable'
if grep -Eq '(^|[^[:alnum:]_])eval([^[:alnum:]_]|$)|(^|[^[:alnum:]_])source([^[:alnum:]_]|$)' "$HELPER"; then
  fail 'PAM helper evaluates or sources configuration text'
fi
grep -Fqx '        name: desktop-shell-helpers' "$CONFIG" || fail 'tidydots helper mapping is missing'
grep -Fqx '        backup: ./Linux/os/helpers' "$CONFIG" || fail 'tidydots helper backup path changed'

printf '%s\n' 'PASS: recursive PAM resolution, failure boundaries, and helper mapping verified'
