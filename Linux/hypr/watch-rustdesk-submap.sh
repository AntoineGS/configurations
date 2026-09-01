#!/usr/bin/env bash
# Event-driven Hyprland workspace -> submap watcher using socat for automatic reconnects
# Also moves 2nd+ RustDesk Remote Desktop windows to the rightmost monitor
# Requirements: hyprctl, socat, jq
set -Eeuo pipefail

readonly SUPPORTED_NOTIFICATION_OUTPUTS_JSON='["HDMI-A-1","DP-3","DP-2","DP-1","eDP-1"]'
readonly NOTIFICATION_ROUTE_REWRITE_INTERVAL=30
readonly NOTIFICATION_LEASE_MAX_AGE_MS=15000
readonly NOTIFICATION_LEASE_RENEW_INTERVAL=5
NOTIFICATION_RECONCILE_INTERVAL=${NOTIFICATION_RECONCILE_INTERVAL:-30}
HYPRLAND_EVENT_RECONNECT_DELAY=${HYPRLAND_EVENT_RECONNECT_DELAY:-2}
NOTIFICATION_ROUTE_LAST_WRITE_SECONDS=-1
NOTIFICATION_ROUTE_CACHED_UPDATED_AT=""
NOTIFICATION_ROUTE_CACHE_INVALID=false
NOTIFICATION_ROUTE_RECONCILE_GENERATION=0
LOCAL_HOSTNAME=$(hostname)
readonly LOCAL_HOSTNAME

: "${XDG_RUNTIME_DIR:=/run/user/$UID}"

NOTIFICATION_ROUTE_DIR=${NOTIFICATION_ROUTE_DIR:-"$XDG_RUNTIME_DIR/desktop-shell"}
NOTIFICATION_ROUTE_FILE=${NOTIFICATION_ROUTE_FILE:-"$NOTIFICATION_ROUTE_DIR/notification-route.json"}
NOTIFICATION_LEASE_FILE=${NOTIFICATION_LEASE_FILE:-"$NOTIFICATION_ROUTE_DIR/notification-route-lease.json"}

monotonic_seconds() {
  printf '%s\n' "$SECONDS"
}

epoch_seconds() {
  printf '%(%s)T\n' -1
}

epoch_milliseconds() {
  date +%s%3N
}

is_rustdesk_remote() {
  printf '%s\n' "$1" | grep -qi "rustdesk" &&
    printf '%s\n' "$1" | grep -qi "Remote Desktop"
}

count_rustdesk_remote_windows() {
  local clients_json=$1

  jq '[.[] | select(.class | test("rustdesk"; "i")) | select(.title | test("Remote Desktop"; "i"))] | length' \
    <<<"$clients_json"
}

rightmost_monitor_from_json() {
  local monitors_json=$1

  jq -r '
    [ .[]
      | select((.disabled // false) == false)
      | select((if has("dpmsStatus") then .dpmsStatus else true end) == true)
      | select((.x // null) != null and (.width // null) != null)
    ]
    | sort_by([(.x + .width), .x, .y, .name])
    | (.[-1].name // "")
  ' <<<"$monitors_json"
}

is_rustdesk_connection_manager_window() {
  local window_class=$1
  local window_title=$2
  local peer_title

  [[ ${window_class,,} == *rustdesk* && $window_title == *" - RustDesk" ]] || return 1
  peer_title=${window_title%" - RustDesk"}
  [[ -n $peer_title && $peer_title != *" - "* ]]
}

hide_rustdesk_connection_manager() {
  local window_addr=$1

  if ! hyprctl eval \
    "hl.dispatch(hl.dsp.window.move({workspace=\"special:rustdesk-cm\", follow=false, window=\"address:0x${window_addr}\"}))"; then
    printf 'failed to hide RustDesk connection manager window: %s\n' "$window_addr" >&2
    return 1
  fi
}

hide_rustdesk_connection_managers() {
  local clients_json=$1
  local window_addr window_class window_title workspace_name

  while IFS=$'\t' read -r window_addr window_class window_title workspace_name; do
    if is_rustdesk_connection_manager_window "$window_class" "$window_title" &&
      [[ $workspace_name != special:rustdesk-cm ]]; then
      hide_rustdesk_connection_manager "${window_addr#0x}" || return 1
    fi
  done < <(jq -r '
    .[]
    | select((.mapped // false) == true)
    | [(.address // ""), (.class // ""), (.title // ""), (.workspace.name // "")]
    | @tsv
  ' <<<"$clients_json")
}

notification_route_state() {
  local monitors_json=$1
  local clients_json=$2
  local routing_hostname=${3:-$LOCAL_HOSTNAME}

  jq -rnc \
    --argjson monitors "$monitors_json" \
    --argjson clients "$clients_json" \
    --argjson supported "$SUPPORTED_NOTIFICATION_OUTPUTS_JSON" \
    --arg routing_hostname "$routing_hostname" '
      def center: {
        x: (.x + (.width / 2)),
        y: (.y + (.height / 2))
      };

      [$monitors[]
        | select((.disabled // false) == false)
        | select((if has("dpmsStatus") then .dpmsStatus else true end) == true)
        | select(.name as $name | ($supported | index($name)) != null)
      ] as $active
      | (if ($routing_hostname | ascii_downcase) == "desktop-e07vtrn" then
           [$clients[]
             | select((.mapped // false) == true)
             | select(.monitor as $monitor
                 | .workspace.id == ($active[] | select(.id == $monitor) | .activeWorkspace.id))
             | select((.class // "") | test("rustdesk"; "i"))
             | select((.title // "") | test("Remote Desktop"; "i"))
             | .monitor
           ] | unique
         else []
         end) as $excluded
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

parse_notification_route_state() {
  local state=$1
  local route_mode_name=$2
  local cue_output_name=$3
  local direction_name=$4
  local -n route_mode_ref=$route_mode_name
  local -n cue_output_ref=$cue_output_name
  local -n direction_ref=$direction_name

  IFS='|' read -r route_mode_ref cue_output_ref direction_ref <<<"$state"
  if [[ $state != "$route_mode_ref|$cue_output_ref|$direction_ref" ]]; then
    printf 'invalid notification route state: %s\n' "$state" >&2
    return 1
  fi

  case $route_mode_ref in
    rustdesk-route-HDMI-A-1|rustdesk-route-DP-3|rustdesk-route-DP-2|rustdesk-route-DP-1|rustdesk-route-eDP-1|rustdesk-route-hidden) ;;
    *)
      printf 'invalid notification route mode: %s\n' "$route_mode_ref" >&2
      return 1
      ;;
  esac

  case $cue_output_ref in
    HDMI-A-1|DP-3|DP-2|DP-1|eDP-1|none) ;;
    *)
      printf 'invalid notification cue output: %s\n' "$cue_output_ref" >&2
      return 1
      ;;
  esac
  case $direction_ref in
    left|right|up|down|none) ;;
    *)
      printf 'invalid notification cue direction: %s\n' "$direction_ref" >&2
      return 1
      ;;
  esac
  if [[ $cue_output_ref == none && $direction_ref != none ]]; then
    printf 'notification route without cue has a direction: %s\n' "$state" >&2
    return 1
  fi

  return 0
}

build_notification_route_json() {
  local visible=$1
  local output=$2
  local cue_output=$3
  local direction=$4
  local updated_at=$5

  jq -cn \
    --argjson visible "$visible" \
    --arg output "$output" \
    --arg cue_output "$cue_output" \
    --arg direction "$direction" \
    --argjson updated_at "$updated_at" \
    '{version: 1, visible: $visible,
      output: (if $visible then $output else null end),
      cueOutput: (if $cue_output == "none" then null else $cue_output end),
      direction: (if $direction == "none" then null else $direction end),
      updatedAt: $updated_at}'
}

notification_route_dir_is_secure() {
  local route_dir=$1
  local owner mode

  [[ -d $route_dir && ! -L $route_dir ]] || return 1
  if ! read -r owner mode < <(stat -c '%u %a' -- "$route_dir"); then
    return 1
  fi
  [[ $owner == "$UID" && $mode == 700 ]]
}

notification_route_file_is_secure() {
  local route_file=$1
  local owner mode

  [[ -f $route_file && ! -L $route_file ]] || return 1
  if ! read -r owner mode < <(stat -c '%u %a' -- "$route_file"); then
    return 1
  fi
  [[ $owner == "$UID" && $mode == 600 ]]
}

ensure_notification_route_dir() {
  local route_dir=$1

  if [[ -e $route_dir && -L $route_dir ]]; then
    printf 'notification route directory is a symlink: %s\n' "$route_dir" >&2
    return 1
  fi
  if ! (umask 077 && mkdir -p -- "$route_dir"); then
    printf 'failed to create notification route directory: %s\n' "$route_dir" >&2
    return 1
  fi
  if ! chmod 0700 -- "$route_dir"; then
    printf 'failed to secure notification route directory: %s\n' "$route_dir" >&2
    return 1
  fi
  if ! notification_route_dir_is_secure "$route_dir"; then
    printf 'notification route directory is not secure: %s\n' "$route_dir" >&2
    return 1
  fi
}

publish_notification_json() (
  local route_dir=$1
  local route_file=$2
  local temp_prefix=$3
  local route_json=$4
  local temporary_file=""

  # shellcheck disable=SC2329 # The EXIT trap invokes this function indirectly.
  cleanup_temporary_route_file() {
    [[ -z $temporary_file ]] || rm -f -- "$temporary_file"
  }

  trap cleanup_temporary_route_file EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  if ! notification_route_dir_is_secure "$route_dir"; then
    return 1
  fi
  if ! temporary_file=$(umask 077 && mktemp "$route_dir/$temp_prefix.XXXXXX"); then
    return 1
  fi
  if ! printf '%s\n' "$route_json" >"$temporary_file"; then
    return 1
  fi
  if ! chmod 0600 -- "$temporary_file"; then
    return 1
  fi
  if ! mv -f -- "$temporary_file" "$route_file"; then
    return 1
  fi
  if ! notification_route_file_is_secure "$route_file"; then
    return 1
  fi
  temporary_file=""
)

write_notification_route_lease() {
  local route_dir=$1
  local lease_file=$2
  local route_updated_at=$3
  local refreshed_at_ms expires_at_ms lease_json

  refreshed_at_ms=$(epoch_milliseconds)
  expires_at_ms=$((refreshed_at_ms + NOTIFICATION_LEASE_MAX_AGE_MS))
  if ! lease_json=$(jq -cn \
    --argjson refreshed_at_ms "$refreshed_at_ms" \
    --argjson expires_at_ms "$expires_at_ms" \
    --argjson route_updated_at "$route_updated_at" \
    '{version: 2, refreshedAtMs: $refreshed_at_ms,
      expiresAtMs: $expires_at_ms, routeUpdatedAt: $route_updated_at}'); then
    return 1
  fi

  publish_notification_json "$route_dir" "$lease_file" '.notification-route-lease.json' "$lease_json"
}

invalidate_notification_route_lease() {
  local route_file=$1

  rm -f -- "$route_file" || return 1
  [[ ! -e $route_file && ! -L $route_file ]]
}

publish_hidden_notification_route_state() {
  local route_dir=$1
  local route_file=$2
  local lease_file=${3:-"$NOTIFICATION_LEASE_FILE"}
  local route_json

  if ! ensure_notification_route_dir "$route_dir"; then
    invalidate_notification_route_lease "$lease_file" || true
    return 1
  fi
  if ! route_json=$(build_notification_route_json false "" "none" "none" "$(epoch_seconds)"); then
    invalidate_notification_route_lease "$lease_file" || true
    return 1
  fi
  invalidate_notification_route_lease "$lease_file" || return 1

  if publish_notification_json "$route_dir" "$route_file" '.notification-route.json' "$route_json"; then
    return 0
  fi
  invalidate_notification_route_lease "$lease_file" || true
  return 1
}

cleanup_notification_route_state() {
  local route_dir=${1:-"$NOTIFICATION_ROUTE_DIR"}
  local route_file=${2:-"$NOTIFICATION_ROUTE_FILE"}
  local lease_file=${3:-"$NOTIFICATION_LEASE_FILE"}

  if invalidate_notification_route_lease "$lease_file"; then
    if notification_route_dir_is_secure "$route_dir"; then
      publish_hidden_notification_route_state "$route_dir" "$route_file" "$lease_file" || true
    fi
  fi
}

write_notification_route_state() {
  local state=$1
  local route_mode cue_output direction visible output
  local route_dir route_file current_core current_updated_at updated_at
  local route_json route_core route_updated_at
  local monotonic_now route_write_age
  local route_rewritten=false

  if ! parse_notification_route_state "$state" route_mode cue_output direction; then
    invalidate_notification_route_lease "$NOTIFICATION_LEASE_FILE" || true
    return 1
  fi

  case $route_mode in
    rustdesk-route-HDMI-A-1) visible=true; output=HDMI-A-1 ;;
    rustdesk-route-DP-3) visible=true; output=DP-3 ;;
    rustdesk-route-DP-2) visible=true; output=DP-2 ;;
    rustdesk-route-DP-1) visible=true; output=DP-1 ;;
    rustdesk-route-eDP-1) visible=true; output=eDP-1 ;;
    rustdesk-route-hidden) visible=false; output="" ;;
  esac

  route_dir=$NOTIFICATION_ROUTE_DIR
  route_file=$NOTIFICATION_ROUTE_FILE
  if ! ensure_notification_route_dir "$route_dir"; then
    invalidate_notification_route_lease "$NOTIFICATION_LEASE_FILE" || true
    return 1
  fi

  monotonic_now=$(monotonic_seconds)
  route_write_age=$NOTIFICATION_ROUTE_REWRITE_INTERVAL
  if [[ ${NOTIFICATION_ROUTE_LAST_WRITE_SECONDS:-} =~ ^[0-9]+$ ]] &&
    ((monotonic_now >= NOTIFICATION_ROUTE_LAST_WRITE_SECONDS)); then
    route_write_age=$((monotonic_now - NOTIFICATION_ROUTE_LAST_WRITE_SECONDS))
  fi

  updated_at=$(epoch_seconds)
  current_core=""
  current_updated_at=""
  if [[ -f $route_file ]] &&
    current_core=$(jq -c 'del(.updatedAt)' "$route_file" 2>/dev/null) &&
    current_updated_at=$(jq -er \
      '.updatedAt | select(type == "number" and (floor == .) and (. >= 0))' \
      "$route_file" 2>/dev/null) &&
    [[ $current_updated_at =~ ^[0-9]+$ ]]; then
    :
  else
    current_core=""
    current_updated_at=""
  fi

  if [[ $current_updated_at =~ ^[0-9]+$ ]] && ((updated_at < current_updated_at)); then
    updated_at=$current_updated_at
  fi

  if ! route_json=$(build_notification_route_json \
    "$visible" "$output" "$cue_output" "$direction" "$updated_at"); then
    invalidate_notification_route_lease "$NOTIFICATION_LEASE_FILE" || true
    printf 'failed to build notification route JSON\n' >&2
    return 1
  fi
  if ! route_core=$(jq -c 'del(.updatedAt)' <<<"$route_json"); then
    invalidate_notification_route_lease "$NOTIFICATION_LEASE_FILE" || true
    printf 'failed to normalize notification route JSON\n' >&2
    return 1
  fi

  route_updated_at=$updated_at
  if notification_route_file_is_secure "$route_file" &&
    [[ $route_core == "$current_core" && $current_updated_at =~ ^[0-9]+$ ]] &&
    ((route_write_age < NOTIFICATION_ROUTE_REWRITE_INTERVAL)); then
    route_updated_at=$current_updated_at
  else
    local publish_status
    # Revoke the lease before replacing route content so a crash cannot make an
    # old route-timestamp lease validate newly published route content.
    if ! invalidate_notification_route_lease "$NOTIFICATION_LEASE_FILE"; then
      printf 'failed to revoke notification route lease: %s\n' "$NOTIFICATION_LEASE_FILE" >&2
      return 1
    fi
    if publish_notification_json "$route_dir" "$route_file" '.notification-route.json' "$route_json"; then
      route_rewritten=true
      :
    else
      publish_status=$?
      invalidate_notification_route_lease "$NOTIFICATION_LEASE_FILE" || true
      printf 'failed to publish notification route: %s\n' "$route_file" >&2
      return "$publish_status"
    fi
  fi

  if ! write_notification_route_lease "$route_dir" "$NOTIFICATION_LEASE_FILE" "$route_updated_at"; then
    invalidate_notification_route_lease "$NOTIFICATION_LEASE_FILE" || true
    printf 'failed to publish notification lease: %s\n' "$NOTIFICATION_LEASE_FILE" >&2
    return 1
  fi

  if [[ $route_rewritten == true ]]; then
    NOTIFICATION_ROUTE_LAST_WRITE_SECONDS=$monotonic_now
  fi
  NOTIFICATION_ROUTE_CACHED_UPDATED_AT=$route_updated_at
  return 0
}

renew_notification_route_lease() {
  local route_updated_at=$NOTIFICATION_ROUTE_CACHED_UPDATED_AT

  [[ $route_updated_at =~ ^[0-9]+$ ]] || return 1
  if write_notification_route_lease \
    "$NOTIFICATION_ROUTE_DIR" "$NOTIFICATION_LEASE_FILE" "$route_updated_at"; then
    return 0
  fi

  NOTIFICATION_ROUTE_CACHED_UPDATED_AT=""
  NOTIFICATION_ROUTE_CACHE_INVALID=true
  invalidate_notification_route_lease "$NOTIFICATION_LEASE_FILE" || true
  return 1
}

notification_heartbeat_tick() {
  if [[ $NOTIFICATION_ROUTE_CACHE_INVALID == true ]]; then
    return 0
  fi
  if ! renew_notification_route_lease; then
    reconcile_notification_routing || true
  fi
}

notification_scheduler_step() {
  local now=$1
  local reconciliation_deadline=$2
  local heartbeat_deadline=$3
  local cache_valid=$4
  local chosen_deadline=$reconciliation_deadline

  if [[ $cache_valid == true ]] && ((heartbeat_deadline < chosen_deadline)); then
    chosen_deadline=$heartbeat_deadline
  fi
  NOTIFICATION_SCHEDULER_REMAINING=$((chosen_deadline - now))

  if ((now >= reconciliation_deadline)); then
    NOTIFICATION_SCHEDULER_ACTION=reconcile
  elif ((now >= heartbeat_deadline)) && [[ $cache_valid == true ]]; then
    NOTIFICATION_SCHEDULER_ACTION=heartbeat
  else
    NOTIFICATION_SCHEDULER_ACTION="wait"
  fi
}

reconcile_notification_routing() {
  local monitors_json clients_json state

  NOTIFICATION_ROUTE_RECONCILE_GENERATION=$((NOTIFICATION_ROUTE_RECONCILE_GENERATION + 1))
  NOTIFICATION_ROUTE_CACHED_UPDATED_AT=""

  if ! monitors_json=$(hyprctl monitors -j) || ! clients_json=$(hyprctl clients -j); then
    NOTIFICATION_ROUTE_CACHE_INVALID=true
    invalidate_notification_route_lease "$NOTIFICATION_LEASE_FILE" || true
    publish_hidden_notification_route_state "$NOTIFICATION_ROUTE_DIR" "$NOTIFICATION_ROUTE_FILE" || true
    return 1
  fi
  hide_rustdesk_connection_managers "$clients_json" || true
  if ! state=$(notification_route_state "$monitors_json" "$clients_json" "$LOCAL_HOSTNAME"); then
    NOTIFICATION_ROUTE_CACHE_INVALID=true
    invalidate_notification_route_lease "$NOTIFICATION_LEASE_FILE" || true
    publish_hidden_notification_route_state "$NOTIFICATION_ROUTE_DIR" "$NOTIFICATION_ROUTE_FILE" || true
    return 1
  fi
  if write_notification_route_state "$state"; then
    NOTIFICATION_ROUTE_CACHE_INVALID=false
    return 0
  fi
  NOTIFICATION_ROUTE_CACHE_INVALID=true
  return 1
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
  local -n clean_state=$clean_state_name
  local window_addr window_class window_event window_title
  local clients_json fullscreen_restore fullscreen_window_addr fullscreen_internal fullscreen_client
  local count
  local monitors_json
  local rightmost_monitor
  local target_ws

  if [[ $evline == "openwindow>>"* ]]; then
    window_event=${evline#openwindow>>}
    IFS=, read -r window_addr _ window_class window_title <<<"$window_event"
    if is_rustdesk_connection_manager_window "$window_class" "$window_title"; then
      hide_rustdesk_connection_manager "$window_addr" || true
    fi
  fi

  # Move 2nd+ RustDesk Remote Desktop windows to the rightmost monitor.
  if printf '%s\n' "$evline" | grep -qi "^openwindow>>" && is_rustdesk_remote "$evline"; then
    window_addr=$(printf '%s\n' "$evline" | sed 's/^openwindow>>//I' | cut -d',' -f1)
    if clients_json=$(hyprctl clients -j); then
      count=$(count_rustdesk_remote_windows "$clients_json")
      fullscreen_restore=$(jq -r --arg address "0x${window_addr}" '
        (.[] | select(.address == $address)) as $opened
        | [
            .[]
            | select(.address != $address)
            | select(.workspace.id == $opened.workspace.id)
            | select((.class // "") | test("rustdesk"; "i"))
            | select((.title // "") | test("Remote Desktop"; "i"))
          ]
        | sort_by(.focusHistoryID // 2147483647)
        | .[0] as $displaced
        | select($displaced != null)
        | ([($opened.fullscreen // 0), ($displaced.fullscreen // 0)] | max) as $internal
        | ([($opened.fullscreenClient // 0), ($displaced.fullscreenClient // 0)] | max) as $client
        | select(($internal > 0) or ($client > 0))
        | [$displaced.address, $internal, $client]
        | @tsv
      ' <<<"$clients_json")
      IFS=$'\t' read -r fullscreen_window_addr fullscreen_internal fullscreen_client <<<"$fullscreen_restore"
    fi
    if [[ ${count:-0} -gt 1 ]] &&
      monitors_json=$(hyprctl monitors -j) &&
      rightmost_monitor=$(rightmost_monitor_from_json "$monitors_json") &&
      [[ -n $rightmost_monitor ]]; then
      if target_ws=$(jq -r --arg name "$rightmost_monitor" \
        '.[] | select(.name == $name) | .activeWorkspace.id // empty' \
        <<<"$monitors_json") && [[ -n $target_ws ]]; then
        hyprctl eval "hl.dispatch(hl.dsp.window.move({workspace=${target_ws}, follow=false, window=\"address:0x${window_addr}\"}))"
        if [[ $fullscreen_window_addr =~ ^0x[0-9a-fA-F]+$ && $fullscreen_internal =~ ^[0-2]$ && $fullscreen_client =~ ^[0-2]$ ]]; then
          hyprctl eval \
            "hl.dispatch(hl.dsp.window.fullscreen_state({internal=${fullscreen_internal}, client=${fullscreen_client}, action=\"set\", window=\"address:0x${window_addr}\"}))"
          hyprctl eval \
            "hl.dispatch(hl.dsp.window.fullscreen_state({internal=${fullscreen_internal}, client=${fullscreen_client}, action=\"set\", window=\"address:${fullscreen_window_addr}\"}))"
        fi
      fi
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
  local reconcile_interval=$NOTIFICATION_RECONCILE_INTERVAL
  local evline read_status monotonic_now remaining
  local next_reconciliation next_heartbeat
  local reconcile_generation_before_event
  local cache_valid

  if [[ ! $reconcile_interval =~ ^[1-9][0-9]*$ ]]; then
    reconcile_interval=30
  fi

  reconcile_notification_routing || true
  monotonic_now=$(monotonic_seconds)
  next_reconciliation=$((monotonic_now + reconcile_interval))
  next_heartbeat=$((monotonic_now + NOTIFICATION_LEASE_RENEW_INTERVAL))

  while :; do
    monotonic_now=$(monotonic_seconds)
    cache_valid=false
    if [[ $NOTIFICATION_ROUTE_CACHE_INVALID == false ]]; then cache_valid=true; fi
    notification_scheduler_step "$monotonic_now" "$next_reconciliation" "$next_heartbeat" "$cache_valid"
    remaining=$NOTIFICATION_SCHEDULER_REMAINING

    if ((remaining <= 0)); then
      if [[ $NOTIFICATION_SCHEDULER_ACTION == reconcile ]]; then
        reconcile_notification_routing || true
        monotonic_now=$(monotonic_seconds)
        next_reconciliation=$((monotonic_now + reconcile_interval))
        next_heartbeat=$((monotonic_now + NOTIFICATION_LEASE_RENEW_INTERVAL))
      elif [[ $NOTIFICATION_SCHEDULER_ACTION == heartbeat ]]; then
        notification_heartbeat_tick
        monotonic_now=$(monotonic_seconds)
        next_heartbeat=$((monotonic_now + NOTIFICATION_LEASE_RENEW_INTERVAL))
      fi
      continue
    fi

    if IFS= read -r -t "$remaining" evline; then
      reconcile_generation_before_event=$NOTIFICATION_ROUTE_RECONCILE_GENERATION
      handle_hyprland_event "$evline" "$clean_state_name"
      if ((NOTIFICATION_ROUTE_RECONCILE_GENERATION != reconcile_generation_before_event)); then
        monotonic_now=$(monotonic_seconds)
        next_reconciliation=$((monotonic_now + reconcile_interval))
        next_heartbeat=$((monotonic_now + NOTIFICATION_LEASE_RENEW_INTERVAL))
      fi
      continue
    else
      read_status=$?
    fi

    if ((read_status > 128)); then
      monotonic_now=$(monotonic_seconds)
      cache_valid=false
      if [[ $NOTIFICATION_ROUTE_CACHE_INVALID == false ]]; then cache_valid=true; fi
      notification_scheduler_step "$monotonic_now" "$next_reconciliation" "$next_heartbeat" "$cache_valid"
      if [[ $NOTIFICATION_SCHEDULER_ACTION == reconcile ]]; then
        reconcile_notification_routing || true
        monotonic_now=$(monotonic_seconds)
        next_reconciliation=$((monotonic_now + reconcile_interval))
        next_heartbeat=$((monotonic_now + NOTIFICATION_LEASE_RENEW_INTERVAL))
      elif [[ $NOTIFICATION_SCHEDULER_ACTION == heartbeat ]]; then
        notification_heartbeat_tick
        monotonic_now=$(monotonic_seconds)
        next_heartbeat=$((monotonic_now + NOTIFICATION_LEASE_RENEW_INTERVAL))
      fi
      continue
    fi

    return 0
  done
}

watch_hyprland_events() {
  local socat_command=$1
  local hypr_socket_path=$2
  local clean_state_name=$3

  while :; do
    consume_hyprland_event_stream "$clean_state_name" \
      < <("$socat_command" -u "UNIX-CONNECT:${hypr_socket_path}" - 2>/dev/null)
    sleep "$HYPRLAND_EVENT_RECONNECT_DELAY"
  done
}

main() {
  local socat_command=${SOCAT:-socat}
  # shellcheck disable=SC2034 # Passed by name to a nameref in the event loop.
  local activated_clean_workspace=false
  local hypr_dir
  local sig=""
  local candidate
  local hypr_socket_path

  trap cleanup_notification_route_state EXIT
  trap 'cleanup_notification_route_state; exit 129' HUP
  trap 'cleanup_notification_route_state; exit 130' INT
  trap 'cleanup_notification_route_state; exit 143' TERM

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
    # shellcheck disable=SC2012 # Hyprland instance directories are controlled runtime entries.
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
    "$socat_command" "$hypr_socket_path" activated_clean_workspace
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
