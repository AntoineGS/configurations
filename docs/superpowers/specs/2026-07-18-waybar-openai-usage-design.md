# Waybar AI Usage Design

## Goal

Show Claude and OpenAI Codex subscription usage as adjacent, visually matched Waybar modules. Use `claudebar` and `codexbar` for CLI OAuth, current API handling, caching, and rich provider-specific tooltips.

## Current State

The persistent Waybar template uses `waybar-ai-usage` for Claude and has an uncommitted codexbar module for OpenAI. The combined tool relies on browser cookies and its declared tidydots package name is stale.

This design replaces both provider modules with the matched `claudebar` and `codexbar` tools. Both AUR packages are installed and return live usage JSON on this machine.

The relevant files are:

- `Linux/waybar/config.jsonc.tmpl`: persistent source template
- `Linux/waybar/config.jsonc.tmpl.rendered`: generated current-host rendering
- `Linux/waybar/config.jsonc`: active generated configuration
- `Linux/waybar/style.css`: shared Waybar styling
- `tidydots.yaml`: Waybar package dependencies

## Modules

Place `custom/claudebar` and `custom/codexbar` first in `modules-right`, followed by the tray expander.

### Claude

Use this visible format:

```text
{session_pct}%/{session_reset} - {weekly_pct}%/{weekly_reset}
```

Configure `custom/claudebar` with:

- Waybar JSON return type
- 300-second polling interval
- signal 13
- native rich tooltip enabled
- click action opening `https://claude.ai/settings/usage`

### Codex

Use this visible format, matching the weekly half of Claude:

```text
{weekly_pct}%/{weekly_reset}
```

Configure `custom/codexbar` with:

- Waybar JSON return type
- 300-second polling interval
- signal 12
- native rich tooltip enabled
- click action opening `https://chatgpt.com/codex/settings/usage`

## Appearance

Both tools normally embed severity colors in their bar text as Pango markup, which overrides CSS foreground colors. Pass all four bar-color options to both commands with Waybar's inherited foreground color:

```text
--color-low '#cdd6f4' --color-mid '#cdd6f4' --color-high '#cdd6f4' --color-critical '#cdd6f4'
```

Apply the existing `margin-right: 12px` and `opacity: 0.6` rule to `#custom-claudebar` and `#custom-codexbar`. This makes both readouts match the previous subdued Claude appearance. The color overrides affect only bar text; native tooltip progress bars remain severity-colored and adaptive.

## Compact Reset Times

Both tools format multi-day countdowns with a space, such as `6d 20h`. Pipe each tool's Waybar JSON through this filter:

```text
jq -c '.text |= gsub("d "; "d")'
```

The filter changes only the top-level Waybar `text` field, producing `6d20h` in both provider readouts. It does not alter tooltips or hour/minute countdowns such as `1h 30m`. Loading, stale, and authentication messages remain unchanged because they do not contain the `d ` sequence.

## Dependencies

Replace the obsolete `waybar-ai-usage-go` dependency with the AUR packages `claudebar` and `codexbar`. Do not vendor either script. Their Bash, curl, jq, and Waybar dependencies are handled by the AUR packages.

`waybar-ai-usage` is no longer needed by Waybar after both modules migrate. Existing installed copies and package inventory files are outside this change; tidydots simply stops declaring it as a Waybar dependency.

## Data Flow

1. Waybar invokes each provider module every 300 seconds.
2. `claudebar` reads and refreshes Claude CLI OAuth credentials from `~/.claude/.credentials.json`.
3. `codexbar` reads and refreshes Codex CLI OAuth credentials from `~/.codex/auth.json`.
4. Each tool fetches its provider's usage endpoint and caches successful responses for 60 seconds.
5. Each tool emits independent Waybar JSON containing fixed bar text, a native rich tooltip, and a severity class.
6. The final `jq` filter compacts day/hour spacing in the bar text before Waybar renders it.

The 300-second Claude interval follows claudebar's documented minimum and avoids unnecessary pressure on Anthropic's aggressively rate-limited usage endpoint.

## Error Handling

Use each tool's native behavior without wrappers:

- loading output when no cache is available during a transient failure
- stale cached output when a prior response remains usable
- OAuth refresh before token expiry
- provider-specific authentication guidance when CLI credentials are absent or invalid
- independent failure regions so one provider does not prevent the other from updating

## Validation

- Confirm `tidydots.yaml` parses and lists `claudebar` and `codexbar` for Waybar, with no `waybar-ai-usage-go` dependency.
- Run `tidydots restore -n` and confirm it renders the Waybar template.
- Parse the active and rendered JSON configurations and verify module ordering and exact settings.
- Run each configured command and verify valid Waybar JSON with non-empty text, tooltip, and class fields.
- Verify both bar outputs use foreground `#cdd6f4` while their native tooltips remain present.
- Verify neither bar text contains an `Nd Nh` pattern and both native tooltips preserve spaced day/hour values.
- Confirm the active and rendered usage-module definitions are equivalent.
- Run `git diff --check` on persistent source files.
- Restart Waybar and visually verify matching gray readouts, rich provider tooltips, and usage-page click actions when a graphical session is available.

## Out of Scope

- Vendoring or modifying claudebar or codexbar
- Automating `claude` or `codex login`
- Customizing either native rich tooltip
- Removing already installed `waybar-ai-usage` packages from machines
- Editing generated package inventory files
