#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
CONFIG="$SCRIPT_DIR/../config"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

section_line() {
  local wanted=$1
  local line
  local line_number=0

  while IFS= read -r line || [[ -n $line ]]; do
    ((line_number += 1))
    if [[ $line == "$wanted" ]]; then
      printf '%s\n' "$line_number"
      return 0
    fi
  done <"$CONFIG"

  return 1
}

section_count() {
  local wanted=$1
  local line
  local count=0

  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line == "$wanted" ]] && ((count += 1))
  done <"$CONFIG"

  printf '%s\n' "$count"
}

require_section() {
  local section=$1
  local count

  count=$(section_count "$section")
  [[ $count == 1 ]] || fail "expected exactly one section '$section', found $count"
}

section_has_setting() {
  local section=$1
  local wanted=$2
  local line
  local in_section=false

  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line == "$section" ]]; then
      in_section=true
      continue
    fi
    if [[ $in_section == true && $line == \[*\] ]]; then
      return 1
    fi
    if [[ $in_section == true && $line == "$wanted" ]]; then
      return 0
    fi
  done <"$CONFIG"

  return 1
}

require_setting() {
  local section=$1
  local setting=$2

  section_has_setting "$section" "$setting" ||
    fail "missing '$setting' in section $section"
}

assert_after() {
  local earlier=$1
  local later=$2
  local earlier_line
  local later_line

  earlier_line=$(section_line "$earlier") || fail "missing section: $earlier"
  later_line=$(section_line "$later") || fail "missing section: $later"
  ((earlier_line < later_line)) ||
    fail "section $later must appear after $earlier"
}

assert_before() {
  assert_after "$1" "$2"
}

cue_criterion_matches() {
  local section=$1
  local output=$2
  local app_name=$3
  local summary=$4
  local body=$5
  local expected_section

  printf -v expected_section '[app-name=notify-send category=rustdesk-notification-cue-%s summary~="^(←|→|↑|↓|•)$" body=""]' "$output"
  [[ $section == "$expected_section" && $app_name == notify-send && \
    $summary =~ ^(←|→|↑|↓|•)$ && -z $body ]]
}

assert_cue_content_rejected() {
  local section=$1
  local output=$2
  local summary=$3
  local body=$4

  if cue_criterion_matches "$section" "$output" notify-send "$summary" "$body"; then
    fail "visible cue criterion matched untrusted summary/body: '$summary'/'$body'"
  fi
}

require_section '[]'
require_setting '[]' 'invisible=true'

route_sections=(
  '[mode=rustdesk-route-DVI-D-1]'
  '[mode=rustdesk-route-HDMI-A-1]'
  '[mode=rustdesk-route-DP-2]'
  '[mode=rustdesk-route-DP-1]'
  '[mode=rustdesk-route-eDP-1]'
  '[mode=rustdesk-route-hidden]'
)
exception_sections=(
  '[mode=rustdesk-route-DVI-D-1 app-name=notify-send]'
  '[mode=rustdesk-route-HDMI-A-1 app-name=notify-send]'
  '[mode=rustdesk-route-DP-2 app-name=notify-send]'
  '[mode=rustdesk-route-DP-1 app-name=notify-send]'
  '[mode=rustdesk-route-eDP-1 app-name=notify-send]'
  '[mode=rustdesk-route-hidden app-name=notify-send]'
)
cue_sections=()
summary_sections=(
  '[summary~="Setup Wi-Fi"]'
  '[summary~="Update System"]'
  '[summary~="Learn Keybindings"]'
  '[summary~="Screenshot copied & saved"]'
)

for output in DVI-D-1 HDMI-A-1 DP-2 DP-1 eDP-1; do
  section="[mode=rustdesk-route-$output]"
  require_section "$section"
  require_setting "$section" "output=$output"
  require_setting "$section" 'invisible=false'
  assert_after '[]' "$section"
  assert_before "$section" '[mode=rustdesk-cue]'
done

require_section '[mode=rustdesk-route-hidden]'
require_setting '[mode=rustdesk-route-hidden]' 'invisible=true'
for value in false 0; do
  ! section_has_setting '[mode=rustdesk-route-hidden]' "invisible=$value" ||
    fail "hidden RustDesk route must not set invisible=$value"
done
assert_after '[mode=rustdesk-route-DP-2]' '[mode=rustdesk-route-hidden]'
assert_before '[mode=rustdesk-route-hidden]' '[mode=rustdesk-cue]'

require_section '[mode=rustdesk-cue]'
require_setting '[mode=rustdesk-cue]' 'on-notify=exec ~/.config/mako/rustdesk-notification-cue "$id"'
assert_after '[mode=rustdesk-route-hidden]' '[mode=rustdesk-cue]'

require_section '[app-name=Spotify]'
require_setting '[app-name=Spotify]' 'invisible=1'
require_setting '[app-name=Spotify]' 'on-notify=none'
assert_after '[mode=rustdesk-cue]' '[app-name=Spotify]'

require_section '[mode=do-not-disturb]'
require_setting '[mode=do-not-disturb]' 'invisible=true'
require_setting '[mode=do-not-disturb]' 'on-notify=none'
assert_after '[app-name=Spotify]' '[mode=do-not-disturb]'

if section_line '[mode=do-not-disturb app-name=notify-send]' >/dev/null; then
  fail 'broad do-not-disturb notify-send exception must not be present'
fi

for output in DVI-D-1 HDMI-A-1 DP-2 DP-1 eDP-1; do
  section="[mode=rustdesk-route-$output app-name=notify-send]"
  require_section "$section"
  require_setting "$section" 'invisible=false'
  require_setting "$section" 'on-notify=exec ~/.config/mako/rustdesk-notification-cue "$id"'
  assert_after '[mode=do-not-disturb]' "$section"
done

require_section '[mode=rustdesk-route-hidden app-name=notify-send]'
require_setting '[mode=rustdesk-route-hidden app-name=notify-send]' \
  'on-notify=exec ~/.config/mako/rustdesk-notification-cue "$id"'
for value in false 0; do
  ! section_has_setting '[mode=rustdesk-route-hidden app-name=notify-send]' "invisible=$value" ||
    fail "hidden notify-send exception must not set invisible=$value"
done
assert_after '[mode=rustdesk-route-DP-2 app-name=notify-send]' \
  '[mode=rustdesk-route-hidden app-name=notify-send]'

for output in DVI-D-1 HDMI-A-1 DP-2 DP-1 eDP-1; do
  printf -v section '[app-name=notify-send category=rustdesk-notification-cue-%s summary~="^(←|→|↑|↓|•)$" body=""]' "$output"
  cue_sections+=("$section")
  require_section "$section"
  require_setting "$section" "output=$output"
  require_setting "$section" 'invisible=false'
  require_setting "$section" 'on-notify=none'
  require_setting "$section" 'icons=0'
  require_setting "$section" 'actions=0'
  require_setting "$section" 'history=0'
  require_setting "$section" 'format=%s'
  require_setting "$section" 'text-alignment=center'
  require_setting "$section" 'font=sans-serif 28px'
  require_setting "$section" 'default-timeout=5000'
  require_setting "$section" 'layer=overlay'
  for exception in "${exception_sections[@]}"; do
    assert_before "$exception" "$section"
  done
  assert_before "$section" '[urgency=critical]'
  for summary_section in "${summary_sections[@]}"; do
    assert_before "$section" "$summary_section"
  done
  cue_criterion_matches "$section" "$output" notify-send '←' '' ||
    fail "helper-generated cue does not match $section"
  assert_cue_content_rejected "$section" "$output" 'untrusted summary' ''
  assert_cue_content_rejected "$section" "$output" '←' 'untrusted body'
done

require_section '[urgency=critical]'

for section in "${summary_sections[@]}"; do
  require_section "$section"
  assert_after '[urgency=critical]' "$section"
done

set +e
parser_output=$(timeout 1 mako -c "$CONFIG" 2>&1)
parser_status=$?
set -e
[[ $parser_output != *'Failed to parse config'* ]] || fail "$parser_output"
[[ $parser_output != *'Invalid configuration'* ]] || fail "$parser_output"
((parser_status != 0)) || fail 'second mako instance unexpectedly exited successfully'

printf 'PASS: Mako fail-closed RustDesk notification routing config\n'
