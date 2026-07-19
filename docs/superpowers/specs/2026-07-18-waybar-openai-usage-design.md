# Waybar OpenAI Usage Design

## Goal

Show ChatGPT/Codex subscription usage beside the existing Claude Code usage in Waybar. Keep both bar readouts compact and identify each provider in its hover tooltip.

## Current State

The Waybar configuration exposes `custom/claude-usage`, which calls `waybar-ai-usage claude` every 120 seconds. It conditionally displays active 5-hour and 7-day percentages with their reset times. The installed `waybar-ai-usage` binary also supports ChatGPT/Codex usage through its `codex` subcommand.

The source template, rendered template, and active tracked configuration contain equivalent Claude module definitions:

- `Linux/waybar/config.jsonc.tmpl`
- `Linux/waybar/config.jsonc.tmpl.rendered`
- `Linux/waybar/config.jsonc`

## Design

Add a separate `custom/openai-usage` module immediately after `custom/claude-usage` in the right-side module list. The new module will call `waybar-ai-usage codex` with Brave as the cookie source and use the same conditional 5-hour and 7-day format as the Claude module.

Both modules will remain unlabeled in the bar. Their custom tooltips will use these layouts:

```text
Claude
5-Hour: {5h_pct}%  Reset: {5h_reset}
7-Day: {7d_pct}%  Reset: {7d_reset}
```

```text
OpenAI
5-Hour: {5h_pct}%  Reset: {5h_reset}
7-Day: {7d_pct}%  Reset: {7d_reset}
```

This makes the provider clear on hover while preserving the current compact bar layout.

The OpenAI module will match Claude's operational settings:

- JSON output for Waybar
- 120-second polling
- tooltip support
- click-to-refresh through Waybar signal 8

The existing Claude CSS rule will be expanded to style both usage modules with the same opacity and right margin. No wrapper script or Waybar group is needed because separate custom modules preserve independent output and hover regions with less configuration.

## Data Flow

1. Waybar invokes each provider command on its polling interval or after signal 8.
2. `waybar-ai-usage` reads the relevant authenticated Brave cookies.
3. The tool fetches provider usage limits and emits Waybar JSON.
4. Waybar renders the compact text and provider-specific tooltip independently for each module.

## Error Handling

The existing CLI-generated Waybar error state will remain unchanged. Authentication, browser-cookie, or network failures are rendered by the affected module without preventing the other provider module from updating.

Users may need to refresh their authenticated Claude and ChatGPT sessions in Brave when cookie-based requests return HTTP 403.

## Validation

- Confirm all three tracked Waybar configuration variants contain matching module lists and definitions.
- Parse `config.jsonc` and `config.jsonc.tmpl.rendered` with an available JSONC-aware validator and inspect the unrendered template additions for equivalent structure.
- Run both provider commands and confirm they emit valid Waybar JSON, accepting an explicit authentication error as valid command structure when browser cookies are stale.
- Inspect the diff to ensure CSS affects only the two usage modules.

## Out of Scope

- OpenAI API billing or credit usage
- Changes to the `waybar-ai-usage` program
- Automatic browser login or cookie renewal
- Labels or provider icons in the always-visible bar text
