#!/bin/bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
template="$repo_root/Linux/hypr/hypridle.conf.tmpl"
expected_block="$(cat <<'EOF'
    {{- if eq .Hostname "omarchbook" }}
    on-resume = recover-keyball-bluetooth >/dev/null 2>&1 & hyprctl eval 'hl.dispatch(hl.dsp.dpms({action="on"}))' && brightnessctl -r # recover Keyball without delaying screen wake
    {{- else }}
    on-resume = hyprctl eval 'hl.dispatch(hl.dsp.dpms({action="on"}))' && brightnessctl -r # screen on when activity is detected
    {{- end }}
EOF
)"
contents="$(<"$template")"

[[ $contents == *"$expected_block"* ]] || {
  printf 'FAIL: Hypridle Keyball recovery is not restricted to omarchbook\n' >&2
  exit 1
}

printf 'PASS: Hypridle Keyball recovery trigger\n'
