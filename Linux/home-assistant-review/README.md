# Daily Home Assistant review

Reviews Home Assistant diagnostics with `openai/gpt-6-astra#medium` at **08:00
America/Toronto**, saves Markdown under `~/gits/home-assistant/reports/`, and
notifies the selected Home Assistant Companion phone when findings are actionable.
The model has diagnostic-only permissions. The wrapper sends notifications;
neither automatically changes Home Assistant configuration.

## Schedule and startup

The systemd user timer uses `Persistent=true`: one missed run happens when the
user manager next starts, including after the PC boots. User lingering must be
enabled for this to work **without login**. The timer does not power on or wake
the PC. Network failures get up to two retries (after 30 and 120 seconds).
The entire invocation is limited to 15 minutes, with a 16-minute service limit.

An exclusive lock prevents concurrent runs. Completed reviews are deduplicated
by the last scheduled Toronto date. Before 08:00, a manual/catch-up run covers
the previous schedule; the upcoming 08:00 run is still due. Multiple missed days
produce one catch-up review rather than multiple paid model runs.

## Installation

Requires Python 3.10+, systemd, authenticated `/usr/bin/opencode`, `uvx`, `jq`,
and `sh` on the service PATH. The project-scoped MCP and the wrapper use the existing token
in `~/.claude.json` at `mcpServers.home-assistant.env.HOMEASSISTANT_TOKEN`.
The HA URL is `https://ha.antoinedev.io`. Tokens are never put in the job config.

### Tidydots (recommended)

The `home-assistant-review` application is scoped to Linux host
`DESKTOP-E07VTRN`. With this repository at `~/gits/configurations`, preview its
changes, then apply the reviewed restore:

```sh
tidydots --dir ~/gits/configurations restore home-assistant-review -n
tidydots --dir ~/gits/configurations restore home-assistant-review
```

It deploys the project MCP configuration and rendered `.review-config.json`,
links the agent and systemd units, sets settings permissions to 0600, enables
user lingering, and enables the persistent timer. Already-correct setup steps
are skipped. `agents/daily-ha-review.md` is a source alias for `review-agent.md`
so the installed OpenCode agent ID remains `daily-ha-review`.

The settings template keeps `notify.mobile_app_phone_antoine` as the selected
target and renders the current HOME into the project path. MCP credentials and
OpenCode authentication must already exist locally; they are not installed or
committed by this application. Reports and `.review-state/` are not managed by
tidydots. Restoring does not run a model review or send a test notification
directly, but enabling a timer with a missed schedule can trigger its catch-up.

### Manual installation

Inspect any existing destination files before running installation commands:

```sh
mkdir -p ~/.config/systemd/user ~/gits/home-assistant/.opencode/agents
ln -s ~/gits/configurations/Linux/home-assistant-review/review-agent.md \
  ~/gits/home-assistant/.opencode/agents/daily-ha-review.md
ln -s ~/gits/configurations/Linux/home-assistant-review/home-assistant-review.service \
  ~/.config/systemd/user/home-assistant-review.service
ln -s ~/gits/configurations/Linux/home-assistant-review/home-assistant-review.timer \
  ~/.config/systemd/user/home-assistant-review.timer
python ~/gits/configurations/Linux/home-assistant-review/review.py list-targets
```

Create `~/gits/home-assistant/.review-config.json` (mode 0600) with absolute paths
for this machine and the selected notification service:

```json
{
  "project": "/home/antoinegs/gits/home-assistant",
  "notify_service": "notify.mobile_app_phone_antoine",
  "opencode": "/usr/bin/opencode"
}
```

Verify the agent is loaded and run a review and a clearly labelled setup
notification before enabling the timer:

```sh
python ~/gits/configurations/Linux/home-assistant-review/review.py run
python ~/gits/configurations/Linux/home-assistant-review/review.py test-notification
loginctl enable-linger "$USER"
loginctl show-user "$USER" -p Linger
systemctl --user daemon-reload
systemctl --user enable --now home-assistant-review.timer
systemctl --user list-timers home-assistant-review.timer
```

An OpenCode server with cached project services may need its project refreshed
after agent/config installation. This machine's V2 server supports
`DELETE /api/debug/location?location[directory]=<URL-encoded project path>`.
Refresh only an idle project; it disposes that project's cached services.

## Operation

```sh
# Run the current scheduled review (no duplicate if it already succeeded).
systemctl --user start home-assistant-review.service

# Inspect failures and scheduling.
systemctl --user status home-assistant-review.service home-assistant-review.timer
journalctl --user -u home-assistant-review.service

# Explicitly rerun a failed review after addressing the cause.
python ~/gits/configurations/Linux/home-assistant-review/review.py run --retry-failed

# Stop future scheduled reviews (does not cancel an already running service).
systemctl --user disable --now home-assistant-review.timer
```

Reports include the requested window, actual available coverage, status, evidence,
recommendations, and the OpenCode session ID. Quiet successful reviews still
save a report. Partial reviews are explicitly marked, not presented as an
all-clear. Home Assistant's structured system-log counts may cover more than
24 hours; retained logs may cover less. No report can reconstruct rotated logs.

Private run records live in `.review-state/` under the HA project, including
`current.json`, timestamped records, and persisted OpenCode session IDs. These
contain diagnostic evidence; keep them and reports local. There is no automatic
deletion/retention policy. Malformed model output, inaccessible logs, and model
failures exit nonzero and do not publish successful reports. They are not
automatically retried with another model session that same schedule; use the
explicit retry command when ready, or allow the next day's review.

If phone delivery fails, the completed report stays saved and the next invocation
retries **delivery only** before considering a new review. Continued delivery
failure is visible in the service journal and blocks a new review until it is
resolved. A stable notification tag collapses repeated deliveries on compatible
Companion clients, but a lost HTTP response can still cause redelivery; this is
at-least-once delivery, not exactly-once. The phone receives a summary and local
report filename, not a link to a publicly hosted report.

## Focused verification

```sh
python -m unittest discover -s Linux/home-assistant-review/tests -p test_review.py -v
systemd-analyze calendar '*-*-* 08:00:00 America/Toronto'
systemd-analyze --user verify Linux/home-assistant-review/home-assistant-review.service Linux/home-assistant-review/home-assistant-review.timer
```

The tests cover invalid reports, atomic persistence, interrupted sessions,
exclusive locking, schedule deduplication, and notification retries. They do not
call the real model or Home Assistant.
