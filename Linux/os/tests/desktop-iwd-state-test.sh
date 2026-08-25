#!/usr/bin/env bash

set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR="$script_dir"
readonly HELPER="${SCRIPT_DIR%/tests}/helpers/desktop-iwd-state"

tmpdir=""
cleanup() {
  if [[ -n "$tmpdir" ]]; then
    rm -rf -- "$tmpdir"
  fi
}
trap cleanup EXIT

tmpdir="$(mktemp -d)"
mkdir -p -- "$tmpdir/bin" "$tmpdir/fixtures"

cat >"$tmpdir/fixtures/objects.json" <<'EOF'
{"type":"a{oa{sa{sv}}}","data":[{"/net/connman/iwd/device0":{"net.connman.iwd.Device":{"Mode":{"type":"s","data":"ap"}}},"/net/connman/iwd/station1":{"net.connman.iwd.Device":{"Name":{"type":"s","data":"wlan1"},"Mode":{"type":"s","data":"station"}},"net.connman.iwd.Station":{"State":{"type":"s","data":"disconnected"}}},"/net/connman/iwd/station0":{"net.connman.iwd.Device":{"Name":{"type":"s","data":"wlan0"},"Mode":{"type":"s","data":"station"}},"net.connman.iwd.Station":{"State":{"type":"s","data":"connected"},"ConnectedNetwork":{"type":"o","data":"/net/connman/iwd/network0"}}},"/net/connman/iwd/network0":{"net.connman.iwd.Network":{"Name":{"type":"s","data":"Cafe WiFi"},"Type":{"type":"s","data":"psk"},"KnownNetwork":{"type":"o","data":"/net/connman/iwd/known0"},"Connected":{"type":"b","data":true}}},"/net/connman/iwd/network1":{"net.connman.iwd.Network":{"Name":{"type":"s","data":"Open Network"},"Type":{"type":"s","data":"open"},"Connected":{"type":"b","data":false}}}}]}
EOF

cat >"$tmpdir/fixtures/networks.json" <<'EOF'
{"type":"a(on)","data":[[["/net/connman/iwd/network0",-4500],["/net/connman/iwd/network1",-9500]]]}
EOF

cat >"$tmpdir/fixtures/no-station.json" <<'EOF'
{"type":"a{oa{sa{sv}}}","data":[{"/net/connman/iwd/device0":{"net.connman.iwd.Device":{"Mode":{"type":"s","data":"ap"}}}}]}
EOF

cat >"$tmpdir/fixtures/malformed-station.json" <<'EOF'
{"type":"a{oa{sa{sv}}}","data":[{"/net/connman/iwd/station0":{"net.connman.iwd.Device":{"Name":{"type":"s","data":"wlan0"},"Mode":{"type":"s","data":"station"}}}}]}
EOF

cat >"$tmpdir/fixtures/missing-network.json" <<'EOF'
{"type":"a(on)","data":[[["/net/connman/iwd/network1",-9500]]]}
EOF

cat >"$tmpdir/fixtures/disconnected-network.json" <<'EOF'
{"type":"a{oa{sa{sv}}}","data":[{"/net/connman/iwd/device0":{"net.connman.iwd.Device":{"Mode":{"type":"s","data":"ap"}}},"/net/connman/iwd/station1":{"net.connman.iwd.Device":{"Name":{"type":"s","data":"wlan1"},"Mode":{"type":"s","data":"station"}},"net.connman.iwd.Station":{"State":{"type":"s","data":"disconnected"}}},"/net/connman/iwd/station0":{"net.connman.iwd.Device":{"Name":{"type":"s","data":"wlan0"},"Mode":{"type":"s","data":"station"}},"net.connman.iwd.Station":{"State":{"type":"s","data":"connected"},"ConnectedNetwork":{"type":"o","data":"/net/connman/iwd/network0"}}},"/net/connman/iwd/network0":{"net.connman.iwd.Network":{"Name":{"type":"s","data":"Cafe WiFi"},"Type":{"type":"s","data":"psk"},"KnownNetwork":{"type":"o","data":"/net/connman/iwd/known0"},"Connected":{"type":"b","data":false}}},"/net/connman/iwd/network1":{"net.connman.iwd.Network":{"Name":{"type":"s","data":"Open Network"},"Type":{"type":"s","data":"open"},"Connected":{"type":"b","data":false}}}}]}
EOF

jq '.data[0]["/net/connman/iwd/network0"]["net.connman.iwd.Network"].Name.data = 42' \
  "$tmpdir/fixtures/objects.json" >"$tmpdir/fixtures/malformed-network.json"

cat >"$tmpdir/bin/busctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "$*" == *"GetManagedObjects"* ]]; then
  if [[ "${IWD_FIXTURE_MODE:-normal}" == malformed-station ]]; then
    cat "$IWD_FIXTURE_DIR/malformed-station.json"
  elif [[ "${IWD_FIXTURE_MODE:-normal}" == malformed-network ]]; then
    cat "$IWD_FIXTURE_DIR/malformed-network.json"
  elif [[ "${IWD_FIXTURE_MODE:-normal}" == disconnected-network ]]; then
    cat "$IWD_FIXTURE_DIR/disconnected-network.json"
  elif [[ "${IWD_NO_STATION:-false}" == true ]]; then
    cat "$IWD_FIXTURE_DIR/no-station.json"
  else
    cat "$IWD_FIXTURE_DIR/objects.json"
  fi
elif [[ "$*" == *"GetOrderedNetworks"* ]]; then
  if [[ "${IWD_NETWORK_MODE:-normal}" == missing-path ]]; then
    cat "$IWD_FIXTURE_DIR/missing-network.json"
  else
    cat "$IWD_FIXTURE_DIR/networks.json"
  fi
else
  printf 'unexpected busctl call\n' >&2
  exit 2
fi
EOF
chmod 0755 -- "$tmpdir/bin/busctl"

run_helper() {
  env PATH="$tmpdir/bin:$PATH" IWD_FIXTURE_DIR="$tmpdir/fixtures" \
    IWD_FIXTURE_MODE="${IWD_FIXTURE_MODE:-normal}" IWD_NETWORK_MODE="${IWD_NETWORK_MODE:-normal}" "$@"
}

output="$(run_helper "$HELPER")"
printf '%s\n' "$output" | jq -e '
  .available == true and
  .device == "wlan0" and
  .stationPath == "/net/connman/iwd/station0" and
  .state == "connected" and
  .connectedSsid == "Cafe WiFi" and
  .signal == 100 and
  (.networks | length == 2) and
  .networks[0] == {path: "/net/connman/iwd/network0", ssid: "Cafe WiFi", signal: 100, security: "psk", known: true, connected: true} and
  .networks[1] == {path: "/net/connman/iwd/network1", ssid: "Open Network", signal: 0, security: "open", known: false, connected: false}
' >/dev/null

if IWD_NETWORK_MODE=missing-path run_helper "$HELPER" >"$tmpdir/missing-network.out" 2>"$tmpdir/missing-network.err"; then
  printf 'expected missing ordered network failure\n' >&2
  exit 1
fi
[[ "$(<"$tmpdir/missing-network.err")" == *"incoherent connected snapshot"* ]]

if IWD_FIXTURE_MODE=disconnected-network run_helper "$HELPER" >"$tmpdir/disconnected-network.out" 2>"$tmpdir/disconnected-network.err"; then
  printf 'expected disconnected connected-network failure\n' >&2
  exit 1
fi
[[ "$(<"$tmpdir/disconnected-network.err")" == *"incoherent connected snapshot"* ]]

if IWD_FIXTURE_MODE=malformed-network run_helper "$HELPER" >"$tmpdir/malformed-network.out" 2>"$tmpdir/malformed-network.err"; then
  printf 'expected malformed network property failure\n' >&2
  exit 1
fi
[[ "$(<"$tmpdir/malformed-network.err")" == *"malformed network data"* ]]

if IWD_FIXTURE_MODE=malformed-station run_helper "$HELPER" >"$tmpdir/malformed-station.out" 2>"$tmpdir/malformed-station.err"; then
  printf 'expected malformed station failure\n' >&2
  exit 1
fi

no_station_output="$(IWD_FIXTURE_MODE=normal IWD_NO_STATION=true run_helper "$HELPER")"
printf '%s\n' "$no_station_output" | jq -e '
  .available == false and .device == null and .stationPath == null and
  .networks == []
' >/dev/null

cat >"$tmpdir/bin/busctl" <<'EOF'
#!/usr/bin/env bash
printf 'iwd unavailable\n' >&2
exit 1
EOF
chmod 0755 -- "$tmpdir/bin/busctl"
if run_helper "$HELPER" >"$tmpdir/unavailable.out" 2>"$tmpdir/unavailable.err"; then
  printf 'expected unavailable iwd failure\n' >&2
  exit 1
fi

cat >"$tmpdir/bin/busctl" <<'EOF'
#!/usr/bin/env bash
printf '{malformed\n'
EOF
chmod 0755 -- "$tmpdir/bin/busctl"
if run_helper "$HELPER" >"$tmpdir/malformed.out" 2>"$tmpdir/malformed.err"; then
  printf 'expected malformed JSON failure\n' >&2
  exit 1
fi

printf 'desktop-iwd-state tests passed\n'
