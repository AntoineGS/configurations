#!/usr/bin/env bash
# Event-driven Hyprland workspace -> submap watcher using socat for automatic reconnects
# Also moves 2nd+ RustDesk Remote Desktop windows to the rightmost monitor
# Requirements: hyprctl, socat, jq
set -euo pipefail

readonly SUPPORTED_NOTIFICATION_OUTPUTS_JSON='["DVI-D-1","HDMI-A-1","DP-2"]'
readonly NOTIFICATION_CUE_MODE=rustdesk-cue
readonly -a NOTIFICATION_ROUTE_MODES=(
  rustdesk-route-DVI-D-1
  rustdesk-route-HDMI-A-1
  rustdesk-route-DP-2
  rustdesk-route-hidden
)
NOTIFICATION_RECONCILE_INTERVAL=${NOTIFICATION_RECONCILE_INTERVAL:-30}
HYPRLAND_EVENT_RECONNECT_DELAY=${HYPRLAND_EVENT_RECONNECT_DELAY:-2}

: "${XDG_RUNTIME_DIR:=/run/user/$UID}"
RUSTDESK_NOTIFICATION_CUE_STATE=${RUSTDESK_NOTIFICATION_CUE_STATE:-"$XDG_RUNTIME_DIR/rustdesk-notification-cue"}

is_rustdesk_remote() {
  printf '%s\n' "$1" | grep -qi "rustdesk" &&
    printf '%s\n' "$1" | grep -qi "Remote Desktop"
}

count_rustdesk_remote_windows() {
  hyprctl clients -j | jq '[.[] | select(.class | test("rustdesk"; "i")) | select(.title | test("Remote Desktop"; "i"))] | length'
}

notification_route_state() {
  local monitors_json=$1
  local clients_json=$2

  jq -rnc \
    --argjson monitors "$monitors_json" \
    --argjson clients "$clients_json" \
    --argjson supported "$SUPPORTED_NOTIFICATION_OUTPUTS_JSON" '
      def center: {
        x: (.x + (.width / 2)),
        y: (.y + (.height / 2))
      };

      [$monitors[]
        | select((.disabled // false) == false)
        | select((if has("dpmsStatus") then .dpmsStatus else true end) == true)
        | select(.name as $name | ($supported | index($name)) != null)
      ] as $active
      | [$clients[]
          | select((.mapped // false) == true)
          | select((.visible // false) == true)
          | select((.class // "") | test("rustdesk"; "i"))
          | select((.title // "") | test("Remote Desktop"; "i"))
          | .monitor
        ] | unique as $excluded
      | [$active[]
          | select(.id as $id | ($excluded | index($id)) == null)
        ] as $safe
      | ([$active[] | select(.focused == true)][0] // null) as $focused
      | (if $focused == null then null
         elif ($focused.id as $id | ($excluded | index($id)) == null) then $focused
         else (($safe | sort_by([.x, .y, .name]))[0] // null)
         end) as $destination
      | if $focused == null then
          ["rustdesk-route-hidden", "none", "none"]
        elif $destination == null then
          ["rustdesk-route-hidden", $focused.name, "none"]
        elif $focused.id == $destination.id then
          ["rustdesk-route-\($destination.name)", "none", "none"]
        else
          ($focused | center) as $from
          | ($destination | center) as $to
          | ($to.x - $from.x) as $dx
          | ($to.y - $from.y) as $dy
          | (if ($dx | fabs) >= ($dy | fabs) then
               if $dx >= 0 then "right" else "left" end
             else
               if $dy >= 0 then "down" else "up" end
             end) as $direction
          | ["rustdesk-route-\($destination.name)", $focused.name, $direction]
        end
      | join("|")
    '
}

mode_is_active() {
  local modes=$1
  local expected=$2
  local mode

  while IFS= read -r mode; do
    [[ $mode == "$expected" ]] && return 0
  done <<<"$modes"

  return 1
}

apply_notification_route_state() {
  local state=$1
  local route_mode cue_output direction
  local modes cue_state="" mode route_count=0
  local expected_cue=false modes_match=true cue_state_match=false
  local state_dir state_name temporary_state
  local -a mako_args=(mode)

  IFS='|' read -r route_mode cue_output direction <<<"$state"
  if [[ $state != "$route_mode|$cue_output|$direction" ]]; then
    printf 'invalid notification route state: %s\n' "$state" >&2
    return 1
  fi

  case $route_mode in
    rustdesk-route-DVI-D-1|rustdesk-route-HDMI-A-1|rustdesk-route-DP-2|rustdesk-route-hidden) ;;
    *)
      printf 'invalid notification route mode: %s\n' "$route_mode" >&2
      return 1
      ;;
  esac
  case $cue_output in
    DVI-D-1|HDMI-A-1|DP-2) expected_cue=true ;;
    none) ;;
    *)
      printf 'invalid notification cue output: %s\n' "$cue_output" >&2
      return 1
      ;;
  esac
  case $direction in
    left|right|up|down|none) ;;
    *)
      printf 'invalid notification cue direction: %s\n' "$direction" >&2
      return 1
      ;;
  esac
  if [[ $cue_output == none && $direction != none ]]; then
    printf 'notification route without cue has a direction: %s\n' "$state" >&2
    return 1
  fi

  if ! modes=$(makoctl mode); then
    printf 'failed to read Mako modes\n' >&2
    return 1
  fi

  if [[ -e $RUSTDESK_NOTIFICATION_CUE_STATE ]]; then
    if ! cue_state=$(<"$RUSTDESK_NOTIFICATION_CUE_STATE"); then
      printf 'failed to read notification cue state: %s\n' "$RUSTDESK_NOTIFICATION_CUE_STATE" >&2
      return 1
    fi
  fi

  while IFS= read -r mode; do
    case $mode in
      rustdesk-route-DVI-D-1|rustdesk-route-HDMI-A-1|rustdesk-route-DP-2|rustdesk-route-hidden)
        ((route_count += 1))
        [[ $mode == "$route_mode" ]] || modes_match=false
        ;;
      rustdesk-cue)
        [[ $expected_cue == true ]] || modes_match=false
        ;;
    esac
  done <<<"$modes"
  [[ $route_count == 1 ]] || modes_match=false
  mode_is_active "$modes" "$route_mode" || modes_match=false
  if [[ $expected_cue == true ]]; then
    mode_is_active "$modes" "$NOTIFICATION_CUE_MODE" || modes_match=false
    [[ $cue_state == "$cue_output|$direction" ]] && cue_state_match=true
  else
    mode_is_active "$modes" "$NOTIFICATION_CUE_MODE" && modes_match=false
    [[ ! -e $RUSTDESK_NOTIFICATION_CUE_STATE ]] && cue_state_match=true
  fi

  if [[ $expected_cue == true && $cue_state_match == false ]]; then
    state_dir=${RUSTDESK_NOTIFICATION_CUE_STATE%/*}
    state_name=${RUSTDESK_NOTIFICATION_CUE_STATE##*/}
    [[ $state_dir != "$RUSTDESK_NOTIFICATION_CUE_STATE" ]] || state_dir=.
    if ! temporary_state=$(umask 077 && mktemp "$state_dir/.${state_name}.XXXXXX"); then
      printf 'failed to create notification cue state file\n' >&2
      return 1
    fi
    if ! printf '%s\n' "$cue_output|$direction" >"$temporary_state" ||
      ! mv -f -- "$temporary_state" "$RUSTDESK_NOTIFICATION_CUE_STATE"; then
      rm -f -- "$temporary_state"
      printf 'failed to write notification cue state\n' >&2
      return 1
    fi
  fi

  if [[ $modes_match == false ]]; then
    for mode in "${NOTIFICATION_ROUTE_MODES[@]}" "$NOTIFICATION_CUE_MODE"; do
      mako_args+=(-r "$mode")
    done
    mako_args+=(-a "$route_mode")
    [[ $expected_cue == true ]] && mako_args+=(-a "$NOTIFICATION_CUE_MODE")
    if ! makoctl "${mako_args[@]}"; then
      printf 'failed to apply notification route state: %s\n' "$state" >&2
      return 1
    fi
  fi

  if [[ $expected_cue == false && -e $RUSTDESK_NOTIFICATION_CUE_STATE ]]; then
    if ! rm -f -- "$RUSTDESK_NOTIFICATION_CUE_STATE"; then
      printf 'failed to remove notification cue state\n' >&2
      return 1
    fi
  fi
}

reconcile_notification_routing() {
  local monitors_json clients_json state

  if ! monitors_json=$(hyprctl monitors -j) || ! clients_json=$(hyprctl clients -j); then
    apply_notification_route_state 'rustdesk-route-hidden|none|none' || true
    return 1
  fi
  if ! state=$(notification_route_state "$monitors_json" "$clients_json"); then
    apply_notification_route_state 'rustdesk-route-hidden|none|none' || true
    return 1
  fi
  apply_notification_route_state "$state"
}

is_notification_routing_event() {
  case $1 in
    "openwindow>>"*|"closewindow>>"*|"movewindow>>"*|"movewindowv2>>"*|\
      "windowtitle>>"*|"windowtitlev2>>"*|"activewindow>>"*|"activewindowv2>>"*|\
      "minimized>>"*|"workspace>>"*|"workspacev2>>"*|\
      "focusedmon>>"*|"focusedmonv2>>"*|\
      "monitoradded>>"*|"monitoraddedv2>>"*|\
      "monitorremoved>>"*|"monitorremovedv2>>"*|\
      "moveworkspace>>"*|"moveworkspacev2>>"*|\
      "activespecial>>"*|"activespecialv2>>"*|\
      "fullscreen>>"*|"pin>>"*|"togglegroup>>"*|\
      "moveintogroup>>"*|"moveoutofgroup>>"*|"configreloaded>>"*) return 0 ;;
    *) return 1 ;;
  esac
}

handle_hyprland_event() {
  local evline=$1
  local clean_state_name=$2
  local rightmost_monitor=$3
  local -n clean_state=$clean_state_name
  local window_addr
  local count
  local target_ws

  # Move 2nd+ RustDesk Remote Desktop windows to the rightmost monitor.
  if printf '%s\n' "$evline" | grep -qi "^openwindow>>" && is_rustdesk_remote "$evline"; then
    window_addr=$(printf '%s\n' "$evline" | sed 's/^openwindow>>//I' | cut -d',' -f1)
    count=$(count_rustdesk_remote_windows)
    if [ "$count" -gt 1 ]; then
      target_ws=$(hyprctl monitors -j | jq -r '.[] | select(.name == "'"${rightmost_monitor}"'") | .activeWorkspace.id')
      hyprctl eval "hl.dispatch(hl.dsp.window.move({workspace=${target_ws}, follow=false, window=\"address:0x${window_addr}\"}))"
    fi
  fi

  # Switch to clean submap when a RustDesk Remote Desktop window is focused.
  if printf '%s\n' "$evline" | grep -qi "^activewindow>>"; then
    if is_rustdesk_remote "$evline"; then
      hyprctl eval 'hl.dispatch(hl.dsp.submap("clean"))'
      clean_state=true
    elif [ "$clean_state" = true ]; then
      hyprctl eval 'hl.dispatch(hl.dsp.submap("reset"))'
      clean_state=false
    fi
  fi

  if is_notification_routing_event "$evline"; then
    reconcile_notification_routing || true
  fi
}

consume_hyprland_event_stream() {
  local clean_state_name=$1
  local rightmost_monitor=$2
  local reconcile_interval=$NOTIFICATION_RECONCILE_INTERVAL
  local evline read_status
  local next_reconciliation remaining

  if [[ ! $reconcile_interval =~ ^[1-9][0-9]*$ ]]; then
    reconcile_interval=30
  fi

  reconcile_notification_routing || true
  next_reconciliation=$((SECONDS + reconcile_interval))
  while :; do
    remaining=$((next_reconciliation - SECONDS))
    if ((remaining <= 0)); then
      reconcile_notification_routing || true
      next_reconciliation=$((SECONDS + reconcile_interval))
      continue
    fi

    if IFS= read -r -t "$remaining" evline; then
      handle_hyprland_event "$evline" "$clean_state_name" "$rightmost_monitor"
      continue
    else
      read_status=$?
    fi

    if ((read_status > 128)); then
      reconcile_notification_routing || true
      next_reconciliation=$((SECONDS + reconcile_interval))
      continue
    fi

    return 0
  done
}

watch_hyprland_events() {
  local socat_command=$1
  local hypr_socket_path=$2
  local clean_state_name=$3
  local rightmost_monitor=$4

  while :; do
    consume_hyprland_event_stream "$clean_state_name" "$rightmost_monitor" \
      < <("$socat_command" -u "UNIX-CONNECT:${hypr_socket_path}" - 2>/dev/null)
    sleep "$HYPRLAND_EVENT_RECONNECT_DELAY"
  done
}

main() {
  local socat_command=${SOCAT:-socat}
  local hypr_dir
  local sig=""
  local candidate
  local hypr_socket_path
  local activated_clean_workspace=false
  local rightmost_monitor="DP-2"

  : "${XDG_RUNTIME_DIR:=/run/user/$UID}"
  hypr_dir="$XDG_RUNTIME_DIR/hypr"

  # Resolve the running Hyprland instance before doing anything else. Under UWSM
  # this systemd user unit can start before the compositor environment
  # (HYPRLAND_INSTANCE_SIGNATURE) is imported into the session, and a process only
  # ever sees the environment it was spawned with -- so waiting on the env var
  # alone would hang forever. Prefer the env var when it points at a live instance
  # socket; otherwise discover the newest instance from the runtime socket dir.
  # Block until a live event socket exists, then adopt it (exported so the hyprctl
  # calls below inherit it too).
  while :; do
    if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} \
      && -S "$hypr_dir/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock" ]]; then
      sig=$HYPRLAND_INSTANCE_SIGNATURE
      break
    fi
    candidate=$(ls -t "$hypr_dir" 2>/dev/null | head -1 || true)
    if [[ -n $candidate && -S "$hypr_dir/$candidate/.socket2.sock" ]]; then
      sig=$candidate
      break
    fi
    sleep 2
  done
  export HYPRLAND_INSTANCE_SIGNATURE="$sig"

  hypr_socket_path="$hypr_dir/$sig/.socket2.sock"

  # Consume each connection in this shell so handler state persists. A read
  # timeout drives periodic recovery; EOF returns for a bounded reconnect.
  watch_hyprland_events \
    "$socat_command" "$hypr_socket_path" activated_clean_workspace "$rightmost_monitor"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
