#!/usr/bin/env bash
# Update the tmux window name with a Claude Code status icon.
# Usage: tmux-mark-window.sh waiting|completed|clear
# No-op outside tmux. Silent on failure — never blocks the CC hook.

set -u

WAITING='󰂚 '
COMPLETED='󰄬 '

mode=${1-}
[ -n "${TMUX-}" ] || exit 0
[ -n "${TMUX_PANE-}" ] || exit 0
case "$mode" in waiting|completed|clear) ;; *) exit 0 ;; esac

orig=$(tmux display-message -p -t "$TMUX_PANE" "#W" 2>/dev/null) || exit 0
base=$orig
case "$base" in
    "$WAITING"*)   base=${base#"$WAITING"} ;;
    "$COMPLETED"*) base=${base#"$COMPLETED"} ;;
esac

case "$mode" in
    waiting)   new_name="${WAITING}${base}" ;;
    completed) new_name="${COMPLETED}${base}" ;;
    clear)     new_name="$base" ;;
esac

[ "$new_name" = "$orig" ] && exit 0
tmux rename-window -t "$TMUX_PANE" "$new_name" >/dev/null 2>&1 || true
