#!/usr/bin/env bash
set -Eeuo pipefail

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
readonly test_dir
supervisor=$test_dir/../interbase-mcp-supervisor
readonly supervisor
tmp_dir=$(mktemp -d)
readonly tmp_dir
bin_dir=$tmp_dir/bin
readonly bin_dir
manager=$tmp_dir/manage.sh
readonly manager
calls=$tmp_dir/calls
readonly calls
sleep_pid_file=$tmp_dir/sleep.pid
readonly sleep_pid_file

cleanup() {
  if [[ -n ${supervisor_pid:-} ]] && kill -0 "$supervisor_pid" 2>/dev/null; then
    kill -TERM "$supervisor_pid" 2>/dev/null || true
    wait "$supervisor_pid" 2>/dev/null || true
  fi
  rm -rf -- "$tmp_dir"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

mkdir -p -- "$bin_dir"

cat >"$manager" <<'MANAGER'
#!/usr/bin/env bash
set -Eeuo pipefail

printf '%s\n' "$1" >>"$INTERBASE_MCP_TEST_CALLS"
case "$1" in
  start)
    printf 'nrf01: already running on port 5101\n'
    printf 'ERROR: todos_testing exited during startup\n' >&2
    exit 1
    ;;
  status)
    printf 'nrf01: running on port 5101\n'
    printf 'todos_testing: stopped\n'
    exit 1
    ;;
  stop)
    printf 'nrf01: stopped\n'
    printf 'todos_testing: stopped\n'
    exit "${INTERBASE_MCP_TEST_STOP_STATUS:-0}"
    ;;
  *)
    exit 2
    ;;
esac
MANAGER
cat >"$bin_dir/sleep" <<'SLEEP'
#!/usr/bin/env bash
set -Eeuo pipefail

printf '%s\n' "$$" >"$INTERBASE_MCP_TEST_SLEEP_PID"
exec /usr/bin/sleep "$@"
SLEEP
chmod +x -- "$manager" "$bin_dir/sleep"

wait_for_cycle_count() {
  local wanted=$1
  local attempt
  local start_count
  local status_count

  for ((attempt = 0; attempt < 100; attempt++)); do
    start_count=0
    status_count=0
    if [[ -f $calls ]]; then
      while IFS= read -r action; do
        [[ $action == start ]] && ((start_count += 1))
        [[ $action == status ]] && ((status_count += 1))
      done <"$calls"
    fi
    ((start_count >= wanted && status_count >= wanted)) && return 0
    sleep 0.02
  done
  return 1
}

wait_for_retry_sleep() {
  local attempt
  local candidate
  local parent

  for ((attempt = 0; attempt < 100; attempt++)); do
    if [[ -s $sleep_pid_file ]]; then
      candidate=$(<"$sleep_pid_file")
      if [[ $candidate =~ ^[0-9]+$ ]] && kill -0 "$candidate" 2>/dev/null; then
        parent=$(ps -o ppid= -p "$candidate" 2>/dev/null) || parent=''
        parent=${parent//[[:space:]]/}
        if [[ $parent == "$supervisor_pid" ]]; then
          sleep_pid=$candidate
          return 0
        fi
      fi
    fi
    sleep 0.02
  done
  return 1
}

INTERBASE_MCP_MANAGER=$manager \
INTERBASE_MCP_RETRY_SECONDS=0.05 \
INTERBASE_MCP_TEST_CALLS=$calls \
INTERBASE_MCP_TEST_SLEEP_PID=$sleep_pid_file \
PATH=$bin_dir:$PATH \
  "$supervisor" >"$tmp_dir/stdout" 2>"$tmp_dir/stderr" &
supervisor_pid=$!

wait_for_cycle_count 2 || fail 'degraded manager was not retried'
kill -0 "$supervisor_pid" 2>/dev/null || fail 'degraded startup terminated supervisor'
wait_for_retry_sleep || fail 'retry sleep did not start after degraded cycle'

kill -TERM "$supervisor_pid"
wait "$supervisor_pid" || fail 'supervisor did not shut down cleanly'
supervisor_pid=
if kill -0 "$sleep_pid" 2>/dev/null; then
  fail 'retry sleep remained alive after supervisor shutdown'
fi

[[ $(<"$calls") == $'start\nstatus\nstart\nstatus\nstop' ]] || \
  fail 'manager lifecycle calls differ'
grep -Fq 'continuing in degraded state' "$tmp_dir/stderr" || \
  fail 'degraded state was not reported'

if INTERBASE_MCP_MANAGER=$tmp_dir/missing \
  INTERBASE_MCP_RETRY_SECONDS=1 \
  "$supervisor" >"$tmp_dir/missing.out" 2>"$tmp_dir/missing.err"; then
  fail 'missing manager was accepted'
fi
grep -Fq 'manager is missing or not executable' "$tmp_dir/missing.err" || \
  fail 'missing manager error was not reported'

: >"$calls"
rm -f -- "$sleep_pid_file"
INTERBASE_MCP_MANAGER=$manager \
INTERBASE_MCP_RETRY_SECONDS=10 \
INTERBASE_MCP_TEST_CALLS=$calls \
INTERBASE_MCP_TEST_SLEEP_PID=$sleep_pid_file \
INTERBASE_MCP_TEST_STOP_STATUS=7 \
PATH=$bin_dir:$PATH \
  "$supervisor" >"$tmp_dir/stop-failure.out" 2>"$tmp_dir/stop-failure.err" &
supervisor_pid=$!

wait_for_cycle_count 1 || fail 'stop-failure fixture did not start'
wait_for_retry_sleep || fail 'retry sleep did not start before stop-failure shutdown'
kill -TERM "$supervisor_pid"
set +e
wait "$supervisor_pid"
stop_status=$?
set -e
supervisor_pid=

[[ $stop_status -eq 7 ]] || fail 'manager stop failure was not propagated'
if kill -0 "$sleep_pid" 2>/dev/null; then
  fail 'retry sleep remained alive after failed manager stop'
fi

printf 'PASS: InterBase MCP supervisor\n'
