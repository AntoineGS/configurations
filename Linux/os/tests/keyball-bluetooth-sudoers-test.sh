#!/bin/bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
rule="$repo_root/Linux/sudoers/90-keyball-bluetooth-restart"
expected='antoinegs ALL=(root) NOPASSWD: /usr/bin/systemctl restart bluetooth.service'

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -f "$rule" ]] || fail "$rule must exist"
[[ "$(<"$rule")" == "$expected" ]] || fail "sudoers rule grants an unexpected command"
visudo -cf "$rule" >/dev/null || fail "sudoers syntax is invalid"

printf 'PASS: Keyball Bluetooth sudoers rule\n'
