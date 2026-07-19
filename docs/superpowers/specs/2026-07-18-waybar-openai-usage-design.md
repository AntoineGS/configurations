# Waybar OpenAI Usage Design

## Goal

Show OpenAI Codex subscription usage beside Claude Code usage in Waybar. Use `codexbar` for reliable Codex CLI OAuth, API-window handling, caching, and error recovery while keeping the visible readout compact.

## Current State

The source Waybar template exposes `custom/claude-usage`, backed by `waybar-ai-usage claude`. The Waybar package declaration already retains `waybar-ai-usage-go` for that module.

An earlier uncommitted implementation used `waybar-ai-usage codex` for OpenAI. This design replaces that OpenAI command and module with `codexbar`; it does not replace the Claude integration.

The relevant files are:

- `Linux/waybar/config.jsonc.tmpl`: persistent source template
- `Linux/waybar/config.jsonc.tmpl.rendered`: generated current-host rendering
- `Linux/waybar/config.jsonc`: active generated configuration
- `Linux/waybar/style.css`: shared Waybar styling
- `tidydots.yaml`: Waybar package dependencies

## Design

Add `custom/codexbar` immediately after `custom/claude-usage` in the right-side module list. Use this command:

```text
codexbar --format '{weekly_pct}% · {weekly_reset}'
```

The fixed bar text shows weekly usage and its reset countdown. The native codexbar tooltip remains enabled and unmodified so it can adapt to API changes and show the Codex plan, real window labels, model-specific limits, code review usage, credits, pacing, and stale-data status.

Configure the module with:

- Waybar JSON return type
- 300-second polling interval
- signal 12
- tooltip enabled
- click action opening `https://chatgpt.com/codex/settings/usage`

Keep the existing compact Claude bar format. Add an explicit Claude tooltip headed `Claude`, followed by its 5-hour and 7-day percentages and reset times, so both adjacent readouts identify their provider on hover.

Expand the existing Claude usage CSS selector to include `#custom-codexbar`, giving both modules the same right margin and subdued opacity.

Add `codexbar` to the Waybar application's existing Yay dependency list in `tidydots.yaml`. Keep `waybar-ai-usage-go` because Claude still depends on it. No wrapper script or vendored codexbar source is needed.

## Data Flow

1. Waybar invokes `codexbar` every 300 seconds.
2. `codexbar` reads Codex CLI OAuth credentials from `~/.codex/auth.json`, created by `codex login`.
3. It refreshes expiring OAuth tokens, fetches ChatGPT Codex usage, and caches successful responses for 60 seconds.
4. It maps the current API window shape to the weekly placeholders and emits Waybar JSON.
5. Waybar renders the fixed weekly text and codexbar's adaptive rich tooltip.

Claude continues to use its existing independent command, interval, signal, and error region.

## Error Handling

Use codexbar's native states without additional wrapping:

- loading output when no cache is available during a transient network failure
- stale cached output when a prior response remains usable
- authentication guidance when Codex CLI credentials are absent or invalid
- token refresh and cache locking for concurrent Waybar invocations

The OpenAI module can fail or display stale data without preventing Claude from updating.

## Installation

Manage `codexbar` through the AUR package named `codexbar`. Its required Bash, curl, jq, and Waybar dependencies are declared by that package. The user must already be authenticated with `codex login`; tidydots will not automate account login.

## Validation

- Confirm `tidydots.yaml` parses and lists both `waybar-ai-usage-go` and `codexbar` for Waybar.
- Run `tidydots restore -n` and confirm it renders the Waybar template without applying unrelated changes.
- Parse the active and rendered JSON configurations and verify module ordering and exact codexbar settings.
- Run `codexbar --format '{weekly_pct}% · {weekly_reset}'` and verify valid Waybar JSON with non-empty text and tooltip fields.
- Confirm the active and rendered usage-module definitions are equivalent.
- Run `git diff --check` on the persistent source files.
- Restart Waybar and visually verify adjacent readouts and provider-specific hover regions when a graphical session is available.

## Out of Scope

- OpenAI API billing or credit accounting outside codexbar's native subscription tooltip
- Replacing the Claude usage provider
- Vendoring or modifying codexbar
- Automating `codex login`
- Customizing codexbar's native rich tooltip
