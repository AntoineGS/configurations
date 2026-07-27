# YASB Codex Usage Design

## Goal

Show Codex subscription usage in the Windows YASB bar with the same compact weekly percentage and reset countdown used by the Linux Waybar configuration. Keep Codex credentials inside Codex, retain the last successful display during transient failures, and make the usage page available with one click.

## Current State

The Linux Waybar configuration runs `codexbar` every 300 seconds and renders:

```text
{weekly_pct}%/{weekly_reset}
```

The Windows configuration uses YASB 2.0.5. This release has no native Codex usage widget, but `yasb.custom.CustomWidget` can periodically run a command and render JSON fields. Codex CLI 0.145.0 is installed and exposes the `codex app-server` stdio transport and `account/rateLimits/read` request.

The relevant files are:

- `Windows/Yasb/config.yaml`: bar and widget definitions
- `Windows/Yasb/styles.css`: YASB appearance
- `Windows/Yasb/codex-usage.ps1`: new Codex app-server adapter
- `tidydots.yaml`: YASB installation and configuration deployment

## Chosen Approach

Add a PowerShell helper that acts as a narrow adapter between YASB and Codex app-server. YASB invokes the helper every 300 seconds. The helper starts `codex app-server --stdio`, performs the JSON-RPC initialization handshake, requests `account/rateLimits/read`, emits one JSON document for YASB, and terminates the child process.

This approach is preferred over directly reading `%USERPROFILE%\.codex\auth.json` and calling `https://chatgpt.com/backend-api/wham/usage`. The direct endpoint is undocumented, requires the helper to handle bearer tokens, and may fail when Codex stores credentials in the Windows credential manager. App-server owns authentication and token refresh and does not expose credentials to YASB or the helper.

A custom YASB build based on the unreleased Codex widget pull request is also rejected. It would require maintaining a separate YASB package and currently uses the same undocumented endpoint.

## Helper Interface

`codex-usage.ps1` writes exactly one compact JSON object to standard output. Informational and diagnostic messages must not be written to standard output because YASB parses the complete stream as JSON.

Successful output contains:

- `label`: preformatted weekly percentage and reset text
- `weekly_percent`: secondary-window usage percentage
- `weekly_reset`: compact secondary-window countdown, such as `6d20h`
- `primary_percent`: primary-window usage percentage
- `primary_reset`: compact primary-window countdown
- `tooltip`: a two-line primary and weekly usage summary
- `stale`: `false`

The Codex response names windows `primary` and `secondary`; the widget must not assume fixed durations when formatting the tooltip. It labels the secondary window `Weekly` to match the current Waybar display, while including the server-provided duration when it differs from seven days.

Reset timestamps are Unix seconds. Countdown formatting uses the largest two non-zero units from days, hours, and minutes, removes spacing between units, and clamps elapsed resets to `now` rather than producing negative values.

## YASB Widget

Add a `codex_usage` custom widget at the beginning of the bar's right-side widget list so its position matches the Linux usage module. Configure it with:

- type `yasb.custom.CustomWidget`
- JSON return format
- 300000-millisecond polling interval
- main label `{data[label]}`
- tooltip from `{data[tooltip]}`
- a dedicated `codex-usage-widget` class
- left-click opening `https://chatgpt.com/codex/settings/usage`
- no alternate label or additional click behavior

Style the widget with the existing dim text color and spacing used for subdued bar information. Do not add severity colors because the Linux module currently forces one neutral foreground color at every usage level.

## Deployment

Add `codex-usage.ps1` to the existing YASB tidydots entry so it is restored beside `config.yaml` and `styles.css` under `~/.config/yasb`. The YASB command invokes this deployed path with PowerShell 7 using `pwsh.exe -NoProfile -NonInteractive -File`.

Codex remains an external prerequisite. This change does not install Codex CLI or automate `codex login`.

## Cache And Error Handling

After a successful response, write only the normalized widget output to `%LOCALAPPDATA%\yasb\codex-usage.json`. Never cache app-server messages, bearer tokens, account identifiers, or complete upstream responses.

When app-server startup, initialization, response parsing, or the rate-limit request fails:

1. Return the cached normalized value when available.
2. Prefix the cached tooltip with a stale-data warning and a concise error reason.
3. Set `stale` to `true`.
4. If no cache exists, return a valid fallback object whose visible label becomes `Codex ?` and whose tooltip describes the failure.

The helper has a finite timeout for the complete app-server exchange and always terminates the child process. A failed refresh must still exit successfully after emitting valid fallback JSON so YASB can render the stale or unavailable state.

The cache is not given an age-based expiry. A stale tooltip includes the cache timestamp so the user can judge its age, and the next scheduled poll always retries Codex.

## Testing And Validation

Test response normalization and countdown formatting against fixture objects before wiring the live process. Cover:

- normal primary and secondary windows
- null reset timestamps
- elapsed reset timestamps
- alternate secondary duration
- missing secondary data
- valid cache fallback
- no-cache fallback

Then validate the complete integration:

- query the installed `codex app-server` and verify one valid JSON object is emitted
- confirm no credentials or complete server responses appear in the cache
- parse `Windows/Yasb/config.yaml`
- run the configured helper command from the deployed path
- run a tidydots dry-run and confirm the helper is mapped to `~/.config/yasb`
- run `git diff --check` on changed files
- reload YASB and verify the compact label, tooltip, stale behavior, and click action

## Out Of Scope

- Installing or authenticating Codex CLI
- Calling the undocumented ChatGPT usage endpoint directly
- Building or patching YASB
- A rich popup with progress bars
- Displaying token counts, API billing, credits, or non-Codex usage buckets
- Running a persistent app-server daemon
