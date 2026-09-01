#!/usr/bin/env bash
set -Eeuo pipefail

TEST_DIR=$(mktemp -d)
readonly TEST_DIR
REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
readonly REPO_ROOT
readonly HELPER="$REPO_ROOT/Linux/os/helpers/desktop-shell-configuration-updates"
readonly REMOTE="$TEST_DIR/remote.git"
readonly SEED="$TEST_DIR/seed"
readonly CHECKOUT="$TEST_DIR/configurations"
readonly BIN_DIR="$TEST_DIR/bin"
readonly CACHE_DIR="$TEST_DIR/cache"

trap 'rm -rf -- "$TEST_DIR"' EXIT

fail() {
  printf 'configuration-updates-test: %s\n' "$*" >&2
  exit 1
}

assert_json() {
  local json=$1
  local expression=$2
  local description=$3

  jq -e "$expression" <<<"$json" >/dev/null || fail "$description: $json"
}

git init --bare --initial-branch=main "$REMOTE" >/dev/null
git clone "$REMOTE" "$SEED" >/dev/null 2>&1
git -C "$SEED" config user.email test@example.com
git -C "$SEED" config user.name Test
printf 'initial\n' >"$SEED/shared.txt"
printf 'local\n' >"$SEED/local.txt"
git -C "$SEED" add shared.txt local.txt
git -C "$SEED" commit -m initial >/dev/null
git -C "$SEED" push -u origin main >/dev/null 2>&1
git clone "$REMOTE" "$CHECKOUT" >/dev/null 2>&1
git -C "$CHECKOUT" config user.email test@example.com
git -C "$CHECKOUT" config user.name Test

mkdir -p -- "$BIN_DIR"
cat >"$BIN_DIR/tidydots-stub" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${1:-} == --help ]]; then
  if [[ ${TIDYDOTS_LEGACY:-0} == 1 ]]; then
    printf '%s\n' 'Usage: tidydots'
  else
    printf '%s\n' '      --actions   Start with actions visible'
  fi
  exit 0
fi
if [[ -n ${TIDYDOTS_ACTION_LOG:-} ]]; then
  printf '%s\n' "$*" >"$TIDYDOTS_ACTION_LOG"
  exit 0
fi
if [[ ${TIDYDOTS_FAIL:-0} == 1 ]]; then
  printf 'simulated tidydots failure\n' >&2
  exit 1
fi
printf '%s\n' "$TIDYDOTS_PAYLOAD"
EOF
chmod +x "$BIN_DIR/tidydots-stub"

clean_payload='{
  "actionable": false,
  "counts": {
    "applications": 1,
    "entries": 1,
    "packages": 0,
    "actionable_applications": 0,
    "actionable_entries": 0,
    "actionable_packages": 0
  },
  "applications": []
}'
actionable_payload='{
  "actionable": true,
  "counts": {
    "applications": 2,
    "entries": 2,
    "packages": 1,
    "actionable_applications": 2,
    "actionable_entries": 1,
    "actionable_packages": 1
  },
  "applications": [{"name": "nvim"}, {"name": "tidydots"}]
}'

run_status() {
  CONFIGURATIONS_REPO="$CHECKOUT" \
    CONFIGURATION_UPDATES_CACHE_DIR="$CACHE_DIR" \
    CONFIGURATION_UPDATES_ALLOW_NON_ARCH=1 \
    TIDYDOTS_BIN="$BIN_DIR/tidydots-stub" \
    TIDYDOTS_PAYLOAD="$1" \
    TIDYDOTS_FAIL="${2:-0}" \
    "$HELPER" status
}

# A dirty file outside the incoming change must not prevent a safe fast-forward.
printf 'locally modified\n' >"$CHECKOUT/local.txt"
printf 'remote addition\n' >"$SEED/remote.txt"
git -C "$SEED" add remote.txt
git -C "$SEED" commit -m remote-addition >/dev/null
git -C "$SEED" push >/dev/null 2>&1

result=$(run_status "$clean_payload")
[[ $(git -C "$CHECKOUT" rev-parse HEAD) == "$(git -C "$SEED" rev-parse HEAD)" ]] ||
  fail 'safe fast-forward was not applied'
[[ $(<"$CHECKOUT/local.txt") == 'locally modified' ]] || fail 'safe fast-forward discarded local changes'
assert_json "$result" '.git.state == "clean" and (.git.visible | not)' 'safe fast-forward should leave Git clean'
assert_json "$result" '.tidydots.state == "clean" and (.tidydots.visible | not)' 'clean Tidydots state should be hidden'

# An incoming edit that overlaps a local modification must remain blocked.
printf 'remote shared edit\n' >"$SEED/shared.txt"
git -C "$SEED" add shared.txt
git -C "$SEED" commit -m remote-overlap >/dev/null
git -C "$SEED" push >/dev/null 2>&1
printf 'local shared edit\n' >"$CHECKOUT/shared.txt"
blocked_head=$(git -C "$CHECKOUT" rev-parse HEAD)

result=$(run_status "$actionable_payload")
[[ $(git -C "$CHECKOUT" rev-parse HEAD) == "$blocked_head" ]] || fail 'blocked update changed local HEAD'
[[ $(<"$CHECKOUT/shared.txt") == 'local shared edit' ]] || fail 'blocked update changed the local file'
assert_json "$result" '.git.state == "blocked" and .git.visible and .git.actionable' 'overlapping update should be blocked'
assert_json "$result" '.tidydots.state == "actionable" and .tidydots.visible' 'Tidydots action should remain independently visible'
assert_json "$result" '.tidydots.counts.actionable_applications == 2' 'Tidydots counts should be retained'

# A failed Tidydots refresh must retain the last actionable result as stale.
result=$(run_status "$actionable_payload" 1)
assert_json "$result" '.tidydots.state == "error" and .tidydots.visible and .tidydots.stale' 'failed Tidydots check should warn'
assert_json "$result" '.tidydots.actionable and .tidydots.counts.actionable_applications == 2' 'failed check should preserve cached actions'
result=$(run_status "$actionable_payload" 1)
assert_json "$result" '(.tidydots.tooltip | split("Check failed:") | length) == 2' 'repeated failures should not grow the tooltip'

# Interactive actions must open in the requested repository and retain the filtered launch.
cat >"$BIN_DIR/lazygit" <<'EOF'
#!/usr/bin/env bash
pwd >"$LAZYGIT_LOG"
EOF
chmod +x "$BIN_DIR/lazygit"
LAZYGIT_LOG="$TEST_DIR/lazygit.log" PATH="$BIN_DIR:$PATH" CONFIGURATIONS_REPO="$CHECKOUT" "$HELPER" git
[[ $(<"$TEST_DIR/lazygit.log") == "$CHECKOUT" ]] || fail 'Lazygit did not open in the configurations checkout'

TIDYDOTS_ACTION_LOG="$TEST_DIR/tidydots-action.log" \
  TIDYDOTS_BIN="$BIN_DIR/tidydots-stub" \
  CONFIGURATIONS_REPO="$CHECKOUT" \
  "$HELPER" tidydots
[[ $(<"$TEST_DIR/tidydots-action.log") == "--dir $CHECKOUT --actions" ]] ||
  fail 'Tidydots action did not use the repository and action filter'

TIDYDOTS_ACTION_LOG="$TEST_DIR/tidydots-legacy-action.log" \
  TIDYDOTS_LEGACY=1 \
  TIDYDOTS_BIN="$BIN_DIR/tidydots-stub" \
  CONFIGURATIONS_REPO="$CHECKOUT" \
  "$HELPER" tidydots
[[ $(<"$TEST_DIR/tidydots-legacy-action.log") == "--dir $CHECKOUT" ]] ||
  fail 'Legacy Tidydots launch did not fall back to the ordinary TUI'

printf 'configuration-updates-test: PASS\n'
