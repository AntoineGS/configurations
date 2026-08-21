#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
SHELL_ROOT="$ROOT/Linux/quickshell/desktop-shell"
ACTIVATE_SOURCE="$ROOT/Linux/os/helpers/desktop-shell-activate"
SELECTED_PLUGINS="$SHELL_ROOT/SELECTED_PLUGINS"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

grep -Fxq 'commit=7be59e1f4b7451d352d4673c560168290792590f' "$SHELL_ROOT/SOURCE"
grep -Fq 'Copyright (c) David Heinemeier Hansson' "$SHELL_ROOT/LICENSE.omarchy"
grep -Fxq 'selected_polkit_paths=shell/plugins/polkit/manifest.json shell/plugins/polkit/PolkitAgent.qml shell/plugins/polkit/PolkitModel.js' \
  "$SHELL_ROOT/SOURCE"
grep -Fxq 'desktop.polkit|omarchy.polkit|shell/plugins/polkit/manifest.json shell/plugins/polkit/PolkitAgent.qml shell/plugins/polkit/PolkitModel.js' \
  "$SELECTED_PLUGINS"

for path in \
  shell.qml \
  Commons/Color.qml Commons/Style.qml Commons/Util.qml Commons/Border.qml Commons/BorderGeometry.js Commons/qmldir \
  Ui/qmldir Ui/BarWidget.qml Ui/BarIconButton.qml Ui/BarIndicator.qml Ui/Panel.qml Ui/PanelController.qml \
  services/PluginRegistry.qml services/BarWidgetRegistry.qml; do
  test -f "$SHELL_ROOT/$path"
done

runtime_paths=("$SHELL_ROOT/shell.qml" "$SHELL_ROOT/Commons" "$SHELL_ROOT/Ui" "$SHELL_ROOT/services")
for optional in plugins config; do
  [[ ! -e "$SHELL_ROOT/$optional" ]] || runtime_paths+=("$SHELL_ROOT/$optional")
done

if grep -RInE 'OMARCHY_PATH|omarchy-shell|omarchy-[[:alnum:]_-]+|org\.omarchy|\.config/omarchy|\.local/state/omarchy' \
  "${runtime_paths[@]}" --exclude=SOURCE --exclude=LICENSE.omarchy --exclude='*.md'; then
  echo 'active Omarchy runtime reference found' >&2
  exit 1
fi

SERVICE="$SHELL_ROOT/systemd/desktop-shell.service"
grep -Fq 'ExecStart=%h/.local/share/helpers/desktop-shell-launch' "$SERVICE"
if grep -Fq 'desktop-shell-mako-route' "$SERVICE"; then
  printf '%s\n' 'desktop-shell.service still references the deleted Mako route' >&2
  exit 1
fi

for removed in \
  "$ROOT/Linux/os/helpers/desktop-shell-rollback" \
  "$ROOT/Linux/os/helpers/desktop-shell-mako-route" \
  "$SHELL_ROOT/systemd/desktop-shell-mako-route.service"; do
  [[ ! -e $removed && ! -L $removed ]] || {
    printf 'removed fallback path remains: %s\n' "$removed" >&2
    exit 1
  }
done

logical_source_lines() {
  awk '
    {
      line = $0
      if (line ~ /\\[[:space:]]*$/) {
        sub(/\\[[:space:]]*$/, "", line)
        pending = pending line " "
      } else {
        print pending line
        pending = ""
      }
    }
    END { if (pending != "") print pending }
  ' "$1"
}

scan_unauthorized_desktop_mutations() {
  local root relative tracked file command lifecycle_context activation_source

  activation_source=$ACTIVATE_SOURCE
  if [[ ${1:-} == --activation-source ]]; then
    activation_source=$2
    shift 2
  fi

  scan_file() {
    local file=$1 command content

    case $file in
      */tests/*|*/.superpowers/*|*/docs/*|*.generated.*|*/generated/*) return 0 ;;
    esac
    LC_ALL=C grep -Iq . "$file" 2>/dev/null || return 0
    content=$(tr '\n' ' ' <"$file")
    if [[ $file == "$activation_source" ]]; then
      audit_activation_source "$file" || printf '%s\n' "$file"
      return 0
    fi
    if grep -Fq -- 'systemctl' "$file" && grep -Fq -- '--user' "$file" &&
      grep -Fq -- 'desktop-shell' "$file"; then
      printf '%s\n' "$file"
      return 0
    fi
    lifecycle_context=false
    case $file in
      */Linux/mako/*|*/Linux/swayosd/*)
        lifecycle_context=false
        ;;
      */hypr/*|*/vicinae/*|*/quickshell/*|*/systemd/*|*desktop-shell*|*rustdesk*)
        lifecycle_context=true
        ;;
    esac
    [[ $content == *desktop-shell* ]] && lifecycle_context=true
    while IFS= read -r command; do
      if [[ ( $command == *systemctl* && $command == *desktop-shell* ) ||
        $command =~ systemctl.*--user.*(stop|start|restart|try-restart|enable|disable|reload|daemon-reload|mask|unmask|reset-failed).*desktop-shell(\.service)? ||
        $command =~ systemctl.*--user.*desktop-shell(\.service)?.*(stop|start|restart|try-restart|enable|disable|reload|daemon-reload|mask|unmask|reset-failed) ||
        ( $lifecycle_context == true &&
          ( $command == *makoctl* || $command == *swayosd* || $command == *polkit-gnome* ||
            $command == *'uwsm-app -- mako'* || $command == *'uwsm-app -- swayosd-server'* ) ) ]]; then
        printf '%s\n' "$file"
        return 0
      fi
    done < <(logical_source_lines "$file")
  }

  for root in "$@"; do
    if [[ $root == "$ROOT"/* || $root == "$ROOT" ]]; then
      relative=${root#"$ROOT"/}
      while IFS= read -r -d '' tracked; do
        scan_file "$ROOT/$tracked"
      done < <(git -C "$ROOT" ls-files -z -- "$relative")
    else
      while IFS= read -r -d '' file; do
        scan_file "$file"
      done < <(find "$root" -type f -print0 2>/dev/null)
    fi
  done
}

audit_activation_systemctl_line() {
  awk '
    {
      line = $0
      gsub(/"/, "", line)
      gsub(/\047/, "", line)
      gsub(/\\/, "", line)
      gsub(/[()]/, " ", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      count = split(line, token, /[[:space:];|&]+/)
      for (i = 1; i <= count; i++) {
        if (token[i] !~ /(^|\/)systemctl$/) continue
        token[i] = "systemctl"
        if (token[++i] != "--user") exit 1
        i++
        while (i <= count && token[i] == "--no-block") i++
        operation = token[i]
        i++
        if (operation == "restart" || operation == "start" || operation == "stop" ||
            operation == "try-restart" || operation == "reload" || operation == "enable" ||
            operation == "disable" || operation == "mask" || operation == "unmask" ||
            operation == "reset-failed" || operation == "daemon-reload") {
          target = token[i]
          i++
          if (operation == "restart" && target == "watch-rustdesk-submap.service" && i > count) {
            print "restart"
            continue
          }
          if (operation == "start" && target == "desktop-shell.service" && i > count) {
            print "start"
            continue
          }
          exit 1
        }
        if (operation == "is-active" && token[i] == "--quiet") {
          i++
          target = token[i]
          i++
          if ((target == "$unit" || target == "watch-rustdesk-submap.service" ||
               target == "desktop-shell.service") && i > count) continue
        }
        if (operation == "show" && token[i] == "desktop-shell.service") {
          i++
          if (token[i] == "--property=MainPID") i++
          if (token[i] == "--value") {
            i++
            if (i > count) continue
          }
        }
        exit 1
      }
    }
  ' <<<"$1"
}

audit_activation_source() {
  local file=$1
  local command parsed_operations parsed_operation restart_count=0 start_count=0

  LC_ALL=C grep -Iq . "$file" 2>/dev/null || return 1
  while IFS= read -r command; do
    for forbidden in makoctl swayosd polkit-gnome uwsm-app desktop-shell-mako-route; do
      [[ $command != *"$forbidden"* ]] || return 1
    done
    [[ $command != *systemctl* ]] || {
      parsed_operations=$(audit_activation_systemctl_line "$command") || return 1
      while IFS= read -r parsed_operation; do
        case $parsed_operation in
          restart) ((restart_count += 1)) ;;
          start) ((start_count += 1)) ;;
        esac
      done <<<"$parsed_operations"
    }
  done < <(logical_source_lines "$file")
  ((restart_count == 1 && start_count == 1))
}

audit_production_violations() {
  local root=$1
  local activation_source=${2:-$ACTIVATE_SOURCE}
  local violations

  violations=$(scan_unauthorized_desktop_mutations \
    --activation-source "$activation_source" "$root")
  if [[ -n $violations ]]; then
    printf '%s\n' "$violations"
    return 1
  fi
}

audit_violations=$(audit_production_violations "$ROOT/Linux") || {
  printf 'unauthorized desktop mutation owners:\n%s\n' "$audit_violations" >&2
  exit 1
}

AUDIT_FIXTURE=$(mktemp -d)
trap 'rm -rf -- "$AUDIT_FIXTURE"' EXIT HUP INT TERM
mkdir -p "$AUDIT_FIXTURE/Linux/vicinae"
printf '%s\n' 'systemctl --user --no-block restart "desktop-shell"' >"$AUDIT_FIXTURE/Linux/vicinae/quoted-service.sh"
printf '%s\n' "systemctl --user \\" '  enable desktop-shell.service' >"$AUDIT_FIXTURE/Linux/vicinae/continued-service.sh"
printf '%s\n' 'systemctl --user start desktop-shell' >"$AUDIT_FIXTURE/Linux/vicinae/implicit-service.sh"
printf '%s\n' 'wrapper uwsm-app -- mako' >"$AUDIT_FIXTURE/Linux/vicinae/mako-route.sh"
printf '%s\n' 'makoctl mode' >"$AUDIT_FIXTURE/Linux/vicinae/mako-control.sh"
printf '%s\n' 'swayosd-client --output-volume' >"$AUDIT_FIXTURE/Linux/vicinae/swayosd-route.sh"
printf '%s\n' '/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1' >"$AUDIT_FIXTURE/Linux/vicinae/polkit-route.sh"

audit_violations=$(scan_unauthorized_desktop_mutations "$AUDIT_FIXTURE/Linux")
[[ $audit_violations == *'quoted-service.sh'* &&
  $audit_violations == *'continued-service.sh'* &&
  $audit_violations == *'implicit-service.sh'* &&
  $audit_violations == *'mako-route.sh'* &&
  $audit_violations == *'mako-control.sh'* &&
  $audit_violations == *'swayosd-route.sh'* &&
  $audit_violations == *'polkit-route.sh'* ]] || {
  printf 'active mutation audit missed fixture violations:\n%s\n' "$audit_violations" >&2
  exit 1
}

mkdir -p "$AUDIT_FIXTURE/Linux/vicinae" "$AUDIT_FIXTURE/Linux/os/helpers" \
  "$AUDIT_FIXTURE/Linux/systemd" "$AUDIT_FIXTURE/Linux/desktop" \
  "$AUDIT_FIXTURE/Linux/hypr" "$AUDIT_FIXTURE/Linux/quickshell"
printf '%s\n' \
  'systemctl --user restart watch-rustdesk-submap.service' \
  'systemctl --user start desktop-shell.service' \
  'systemctl --user is-active --quiet desktop-shell.service' \
  'systemctl --user show desktop-shell.service --property=MainPID --value' \
  >"$AUDIT_FIXTURE/Linux/os/helpers/desktop-shell-activate"
printf '%s\n' \
  'systemctl --user restart watch-rustdesk-submap.service' \
  'systemctl --user start desktop-shell.service' \
  'systemctl --user start desktop-shell.service' \
  >"$AUDIT_FIXTURE/Linux/os/helpers/desktop-shell-activate-forbidden"
printf '%s\n' 'systemctl --user restart desktop-shell.service' \
  >"$AUDIT_FIXTURE/Linux/vicinae/extra-desktop-mutation.sh"
audit_activation_source "$AUDIT_FIXTURE/Linux/os/helpers/desktop-shell-activate" || \
  fail 'allowed activation operations were rejected'
if audit_activation_source "$AUDIT_FIXTURE/Linux/vicinae/extra-desktop-mutation.sh"; then
  fail 'extra activation desktop-shell mutation was accepted'
fi

production_fixture_result="$AUDIT_FIXTURE/production-violations"
if audit_production_violations "$AUDIT_FIXTURE/Linux" \
  "$AUDIT_FIXTURE/Linux/os/helpers/desktop-shell-activate-forbidden" >"$production_fixture_result"; then
  fail 'forbidden activation operation was accepted by the production audit'
fi
grep -Fxq "$AUDIT_FIXTURE/Linux/os/helpers/desktop-shell-activate-forbidden" "$production_fixture_result" || \
  fail 'production audit discarded the forbidden activation violation'

printf '%s\n' \
  'systemctl --user restart watch-rustdesk-submap.service' \
  'systemctl --user start desktop-shell.service' \
  'systemctl --user --no-block start desktop-shell.service' \
  >"$AUDIT_FIXTURE/Linux/os/helpers/option-duplicate-start"
printf '%s\n' \
  'systemctl --user restart watch-rustdesk-submap.service' \
  'systemctl --user start desktop-shell.service' \
  'systemctl --user --no-block restart watch-rustdesk-submap.service' \
  >"$AUDIT_FIXTURE/Linux/os/helpers/option-duplicate-restart"
printf '%s\n' \
  'systemctl --user restart watch-rustdesk-submap.service' \
  'systemctl --user start desktop-shell.service' \
  '/usr/bin/systemctl --user stop desktop-shell.service' \
  >"$AUDIT_FIXTURE/Linux/os/helpers/path-qualified-forbidden"
printf '%s\n' \
  'systemctl --user restart watch-rustdesk-submap.service' \
  'systemctl --user start desktop-shell.service' \
  'systemctl --user --no-block' \
  >"$AUDIT_FIXTURE/Linux/os/helpers/malformed-systemctl"

for forbidden_fixture in \
  option-duplicate-start option-duplicate-restart path-qualified-forbidden malformed-systemctl; do
  production_fixture_result="$AUDIT_FIXTURE/production-$forbidden_fixture"
  fixture_path="$AUDIT_FIXTURE/Linux/os/helpers/$forbidden_fixture"
  if audit_production_violations "$AUDIT_FIXTURE/Linux" "$fixture_path" >"$production_fixture_result"; then
    fail "production audit accepted forbidden activation fixture: $forbidden_fixture"
  fi
  grep -Fxq "$fixture_path" "$production_fixture_result" || \
    fail "production audit discarded activation fixture: $forbidden_fixture"
done

for root in vicinae os/helpers systemd desktop hypr quickshell; do
  name=${root//\//-}
  printf '%s\n' 'desktop-shell fallback route: uwsm-app -- mako' \
    >"$AUDIT_FIXTURE/Linux/$root/forbidden-route-$name.sh"
done
repo_fixture_violations=$(scan_unauthorized_desktop_mutations "$AUDIT_FIXTURE/Linux")
for root in vicinae os/helpers systemd desktop hypr quickshell; do
  name=${root//\//-}
  [[ $repo_fixture_violations == *"forbidden-route-$name.sh"* ]] || \
    fail "repository audit missed representative root: $root"
done
