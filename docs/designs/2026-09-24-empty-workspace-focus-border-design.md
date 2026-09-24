# Focus border for an empty workspace

## Intent and scope

Show the same active-color outline as a lone tiled window when the focused monitor's active workspace has no app windows. The outline disappears when an app opens there, the monitor loses focus, or a different workspace becomes active. This makes monitor focus visible even when there is no window to decorate. Only the focused monitor may show the outline; inactive empty monitors never do.

The outline is visual only: it must not create a real window in the workspace, take focus or input, reserve space, affect tiling, or change the existing Win+H/L/J/K navigation. It depends on the existing Quickshell desktop shell being running; there is no separate service or Hyprland plugin.

## Approach

Add a dedicated, small QML component owned by `Linux/quickshell/desktop-shell/shell.qml`. It creates one transparent, non-interactive layer-shell surface per Quickshell screen using the existing `Variants`/`PanelWindow` pattern. Surfaces use `ExclusionMode.Ignore`, no keyboard focus, and an empty input region. Only the surface on the focused Hyprland monitor with a known, empty active workspace becomes visible; all others remain hidden. Disable the feature in desktop-shell preview and surface-suppressed test modes.

Use Quickshell's `Hyprland` monitor/workspace/toplevel models for focus and occupancy. A workspace is empty when its toplevel collection has no app windows, including floating ones; an active special workspace with a visible app also suppresses the outline. React to monitor focus, active-workspace and toplevel changes. A missing screen-to-monitor match, workspace, or trustworthy occupancy data means no outline rather than a misplaced one. Avoid polling or launching a helper process for state already exposed by the shell.

## Appearance and placement

Draw a transparent rectangle with an inward one-logical-pixel `#cba6f7` outline, matching Hyprland's current `general.border_size = 1` and `general.col.active_border` in `Linux/hypr/looknfeel.lua`. No fill, rounded corners, shadow, or additional animation. Place it at the outer boundary of the monitor's usable workspace rectangle, not at the screen edge above the top bar: a single tiled app currently begins one border width inside this boundary. Read the monitor's compositor-reported reserved insets so the border tracks the actual bar and other reserved areas instead of assuming a fixed 28-pixel top offset. Keep the overlay on the output it belongs to, honoring logical scaling and hotplug. If the usable rectangle cannot be determined safely, hide the surface.

The overlay remains invisible over normal occupied workspaces and must not intercept clicks, hover, keyboard shortcuts, or focus. When the top bar is hidden, the inset and outline should follow the compositor's updated usable area. The outline should not cover the bar or appear on a fullscreen application.

## Validation

Check shell startup, occupied and empty active workspaces, switching focus between empty and occupied monitors, opening/closing the first or last app (including a floating app), and workspace switching. Check the outline's alignment against a lone tiled app, including with the bar hidden and on scaled outputs; check that pointer input still reaches the desktop and no extra workspace window appears. Existing surface-suppression and preview runs must remain free of new visible surfaces. Add a narrow regression check only if state-selection logic warrants one; do not add tests for declarative QML layout or exact config text.
