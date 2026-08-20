#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
HELPER_ROOT="$ROOT/Linux/os/helpers"
SHELL_ROOT="$ROOT/Linux/quickshell/desktop-shell"
AGENT_ROOT="$SHELL_ROOT/plugins/agents"
UPDATE="$HELPER_ROOT/desktop-agent-usage-update"
STATUS="$HELPER_ROOT/desktop-shell-status"

command -v jq >/dev/null 2>&1 || {
  printf 'agents-test: jq is required\n' >&2
  exit 1
}
command -v python3 >/dev/null 2>&1 || {
  printf 'agents-test: python3 is required\n' >&2
  exit 1
}

fail() {
  printf 'agents-test: %s\n' "$1" >&2
  exit 1
}

for helper in desktop-agent-usage-codex desktop-agent-usage-claude desktop-agent-usage-update; do
  test -x "$HELPER_ROOT/$helper" || fail "missing executable $helper"
done

for path in Agent.qml Main.qml Panel.qml manifest.json assets/codex.svg assets/codex-light.svg assets/claude.svg; do
  test -s "$AGENT_ROOT/$path" || fail "missing agent panel file $path"
done

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

fake_bin="$fixture/bin"
home_root="$fixture/home"
state_home="$fixture/state"
cache_home="$fixture/cache"
codex_home="$fixture/codex"
claude_home="$fixture/claude"
broken_collectors="$fixture/broken-collectors"
mkdir -p "$fake_bin" "$home_root" "$state_home" "$cache_home" \
  "$codex_home/sessions" "$claude_home/projects/project" "$broken_collectors"

cat >"$fake_bin/codex" <<'FAKE_CODEX'
#!/usr/bin/env bash
set -Eeuo pipefail

while IFS= read -r request; do
  request_id=$(jq -r '.id // empty' <<<"$request")
  case "$request_id" in
    1) printf '%s\n' '{"id":1,"result":{"ok":true}}' ;;
    2) printf '%s\n' '{"id":2,"result":{"account":{"planType":"plus"}}}' ;;
    3) printf '%s\n' '{"id":3,"result":{"rateLimits":{"planType":"plus","primary":{"usedPercent":1,"windowDurationMins":300,"resetsAt":4102444800},"secondary":{"usedPercent":4,"windowDurationMins":10080,"resetsAt":4102444800}}}}' ;;
  esac
done
FAKE_CODEX
chmod +x "$fake_bin/codex"

now="$(date +%s)"
cat >"$codex_home/auth.json" <<'CODEX_AUTH'
{"tokens":{"access_token":"codex-fixture-secret"}}
CODEX_AUTH
cat >"$codex_home/sessions/fixture.jsonl" <<CODEX_SESSION
{"type":"turn_context","payload":{"model":"gpt-5"}}
{"type":"response_item","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"output_tokens":20}}},"timestamp":$now}
CODEX_SESSION

cat >"$claude_home/.credentials.json" <<'CLAUDE_AUTH'
{"claudeAiOauth":{"accessToken":"claude-fixture-secret","expiresAt":1,"subscriptionType":"pro"}}
CLAUDE_AUTH
cat >"$claude_home/projects/project/session.jsonl" <<CLAUDE_SESSION
{"type":"assistant","message":{"role":"assistant","id":"fixture-message","model":"claude-sonnet-4","usage":{"input_tokens":30,"output_tokens":10}},"timestamp":"2026-08-16T12:00:00Z"}
CLAUDE_SESSION

original_path="$PATH"
usage_dir="$state_home/desktop-shell/agents/usage"

run_update() {
  PATH="$fake_bin:$original_path" \
    HOME="$home_root" \
    XDG_STATE_HOME="$state_home" \
    XDG_CACHE_HOME="$cache_home" \
    CODEX_HOME="$codex_home" \
    CLAUDE_CONFIG_DIR="$claude_home" \
    "$UPDATE" "$@"
}

assert_record() {
  local provider=$1
  local record="$usage_dir/$provider.json"
  test -s "$record" || fail "$provider record was not written"
  jq -e --arg id "$provider" '
    .id == $id and
    (.name | type == "string") and
    (.limits | type == "array") and
    (.dailyUsage | type == "array") and
    (.modelUsage | type == "object") and
    (.updatedAt | type == "string") and
    (.stale == false)
  ' "$record" >/dev/null || fail "$provider record contract failed"
  jq -e --arg secret fixture-secret 'tostring | contains($secret) | not' "$record" >/dev/null \
    || fail "$provider record contains a credential"
}

run_update codex
assert_record codex
test ! -e "$usage_dir/claude.json" || fail "Claude record exists during Codex-only auth"

rm -f "$codex_home/auth.json" "$usage_dir/codex.json"
run_update claude
assert_record claude
test ! -e "$usage_dir/codex.json" || fail "Codex record exists during Claude-only auth"

rm -f "$claude_home/.credentials.json" "$usage_dir/claude.json"
run_update
test ! -e "$usage_dir/codex.json" || fail "Codex record was not omitted without auth"
test ! -e "$usage_dir/claude.json" || fail "Claude record was not omitted without auth"

cat >"$codex_home/auth.json" <<'CODEX_AUTH'
{"tokens":{"access_token":"codex-fixture-secret"}}
CODEX_AUTH
run_update codex
assert_record codex

cat >"$broken_collectors/desktop-agent-usage-codex" <<'BROKEN_COLLECTOR'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' 'not-json'
BROKEN_COLLECTOR
chmod +x "$broken_collectors/desktop-agent-usage-codex"

if DESKTOP_SHELL_AGENT_COLLECTOR_DIR="$broken_collectors" run_update codex 2>"$fixture/malformed.stderr"; then
  fail "malformed provider output unexpectedly succeeded"
fi
jq -e '
  .id == "codex" and
  .stale == true and
  (.error | type == "string" and length > 0) and
  (.limits | type == "array") and
  (.dailyUsage | type == "array")
' "$usage_dir/codex.json" >/dev/null || fail "stale fallback did not preserve the valid Codex record"

cat >"$broken_collectors/desktop-agent-usage-codex" <<'SECRET_COLLECTOR'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' '{"id":"codex","name":"Codex","updatedAt":"2026-08-16T00:00:00Z","limits":[],"dailyUsage":[],"modelUsage":{},"accessToken":"should-not-be-written"}'
SECRET_COLLECTOR
chmod +x "$broken_collectors/desktop-agent-usage-codex"
DESKTOP_SHELL_AGENT_COLLECTOR_DIR="$broken_collectors" run_update codex
jq -e 'has("accessToken") | not' "$usage_dir/codex.json" >/dev/null \
  || fail "record writer persisted an unapproved credential field"

shopt -s nullglob
temporary_records=("$usage_dir"/.[!.]*.tmp)
(( ${#temporary_records[@]} == 0 )) || fail "temporary record was left behind after atomic update"

cat >"$fake_bin/codexbar" <<'FAKE_CODEXBAR'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' '{"text":"1%/4d 7h 03m","tooltip":"Codex quota","class":"source"}'
FAKE_CODEXBAR
chmod +x "$fake_bin/codexbar"
compact_output=$(PATH="$fake_bin:$original_path" HOME="$home_root" XDG_CACHE_HOME="$cache_home" "$STATUS" codex)
jq -e '.text == "1%/4d7h03m" and (.text | contains("Codex") | not)' <<<"$compact_output" >/dev/null \
  || fail "compact Codex status changed"

jq -e '
  .id == "desktop.agents" and
  (.kinds | index("bar-widget")) != null and
  .entryPoints.barWidget == "Panel.qml" and
  .barWidget.defaultSection == "right"
' "$AGENT_ROOT/manifest.json" >/dev/null \
  || fail "agent manifest has no native bar-widget entry point"
grep -Fq 'command: ["desktop-shell-status", "codex"]' "$AGENT_ROOT/Panel.qml" \
  || fail "agent widget does not own compact Codex status"
grep -Fq 'readonly property string displayText: compactText !== "" ? compactText : (providers.length > 0 ? "󱚣" : "")' "$AGENT_ROOT/Panel.qml" \
  || fail "agent widget has no provider display fallback"
grep -Fq 'visible: displayText !== ""' "$AGENT_ROOT/Panel.qml" \
  || fail "agent widget visibility is not derived from display text"
grep -Fq 'text: root.displayText' "$AGENT_ROOT/Panel.qml" \
  || fail "agent button does not use the derived display text"
grep -Fq 'interval: 300000' "$AGENT_ROOT/Panel.qml" \
  || fail "agent compact status refresh cadence changed"
grep -Fq 'anchorItem: button' "$AGENT_ROOT/Panel.qml" \
  || fail "agent panel is not anchored to its native button"
grep -Fq 'BarWidgetIpc { pluginId: "desktop.agents" }' "$SHELL_ROOT/shell.qml" \
  || fail "agent widget has no shell-managed IPC route"
if grep -Fq 'standaloneAnchor' "$AGENT_ROOT/Panel.qml" \
    || grep -Fq 'IpcHandler {' "$AGENT_ROOT/Panel.qml"; then
  fail "agent widget retains detached panel anchoring or direct IPC"
fi
grep -Fq 'desktop-agent-usage-update' "$AGENT_ROOT/Main.qml" \
  || fail "panel does not use the neutral updater"
grep -Fq 'dailyUsage' "$AGENT_ROOT/Panel.qml" \
  || fail "panel does not render daily usage"
grep -Fq 'stale' "$AGENT_ROOT/Panel.qml" \
  || fail "panel does not expose stale details"
grep -Fq 'onMoveRequested' "$AGENT_ROOT/Panel.qml" \
  || fail "panel has no keyboard navigation"
grep -Fq 'onTextKey' "$AGENT_ROOT/Panel.qml" \
  || fail "panel has no keyboard shortcuts"
grep -Fq 'function refresh' "$AGENT_ROOT/Main.qml" \
  || fail "panel has no refresh operation"

if grep -RInE 'omarchy|Fireworks|sync|cross-device|agent --pick|PersistentProperties' "$AGENT_ROOT"; then
  fail "forbidden Omarchy, Fireworks, sync, cross-device, or launch behavior found in agent panel"
fi

CONFIG="$SHELL_ROOT/config/shell.json.tmpl"
grep -Fq '{ "id": "desktop.agents" }' "$CONFIG" \
  || fail "bar does not mount the native Agents widget"
if grep -Fq '{ "id": "codex", "type": "command"' "$CONFIG"; then
  fail "legacy generic Codex command widget remains configured"
fi

printf 'agents-test: collector records, auth omission, stale fallback, panel contract, and compact status verified\n'
