# Jev assistance for OpenCode V2

The local `plugins/jev.js` plugin uses Jev for four bounded decisions:

- **Task routing:** select a model tier and primary agent before an eligible new
  task starts. `/provider` remains the source of provider selection. Optional
  specialist hints respect the normal delegation workflow.
- **Adaptive review:** retain mandatory correctness review and select additional
  review dimensions from the actual diff. Selection is not a correctness verdict.
- **Context selection:** shorten supported oversized results using verbatim
  excerpts, with complete pre-filter text available through a recovery tool.
- **Domain skills:** rank descriptions, independently check shortlisted excerpts,
  and suggest up to three skills. The agent still decides which skills to load.

All four are enabled by default. Failed, uncertain, cancelled, or oversized
decisions fall back to the ordinary workflow.

## Installation and authentication

Ship `plugins/jev.js` and the complete `jev/` directory together through the
existing OpenCode configuration mapping. `agent-provider-routing.js` also imports
`jev/routing.mjs`. No additional npm package or separate TypeSafe account is needed.
The existing regeneration script preserves these paths.

The plugin resolves the active **OpenRouter** API-key connection through OpenCode's
V2 integration API. Reconnect OpenRouter through OpenCode's integration interface
if `/jev doctor` reports HTTP 401. Keys are never placed in this directory, status
messages, caches, or command arguments. Coding agents continue using the provider
selected by `/provider`; only Jev decisions use OpenRouter.

After installing, open a fresh location or reload configuration at an idle boundary:

```sh
opencode api post /api/location/reload
```

That command reloads all loaded locations, so finish active work first. Run
`/jev status` and `/jev doctor` in a session to confirm discovery and connectivity.
An isolated worktree does not activate its files in the canonical configuration.

## Controls

| Command | Effect |
| --- | --- |
| `/jev status` | Enabled features, credential availability, route ownership, cooldown, and session-local Jev usage |
| `/jev off` | Disable all four features for this session and cancel pending decisions |
| `/jev on` | Enable features and release the routing pin; routing can resume at an eligible idle task boundary |
| `/jev pin` | Hold the current model and agent while leaving the other features enabled |
| `/jev doctor` | One small synthetic batch checking Choice, Noul, and Score; report HTTP failure or served model, latency, and usage |
| `/review-adaptive [requirements]` | Select dimensions for the working diff, then submit a review assignment to the normal coordinator |

Status/on/off/pin/doctor use non-resuming messages, so displaying their results does
not request a coding-model response. Controls survive reload and session moves.
New children inherit the parent's enabled/off setting when first observed and can
override it independently; assigned child roles are preserved.

**V2.0.14 limitation:** selecting the already-current model produces no event or
history record. Use `/jev pin` to hold that route. Actual changes to the model or
agent and explicit initial selections remain protected automatically. Unknown
selection provenance is treated conservatively. A route stays stable through tool
iterations and follow-up corrections; ambiguous continuations do not reroute.
Jev keeps the initial request plus an approximately 8,000-character window of
complete follow-up messages, always retaining the current request intact. Omitted
older follow-ups are explicitly counted; OpenCode's full conversation is unchanged.

## Review integration

`jev_review_select` takes `requirements`, a `scope`, and explicit `policy`:

```json
{
  "requirements": "Review the transaction changes against the task requirements",
  "scope": { "mode": "working", "files": ["src/db.ts"] },
  "policy": {
    "mode": "adaptive",
    "delegationAllowed": true,
    "baselineRequired": true,
    "requiredAgents": []
  }
}
```

Scope modes are `working`, `branch`, and `committed`; `base` is optional. Omit
`files` for the whole scope. The tool rechecks its scope hash after selection.
Missing files, incomplete/binary/truncated diffs, missing required agents, and
failed decisions explicitly return fallback. There is no numerical cap on required
reviews. A no-delegation policy returns dimensions for the current agent instead
of specialist assignments.

The direct command first selects dimensions without authorizing delegation. The
coordinator confirms semantic repository/user policy before requesting specialist
assignments. The plugin never starts reviewers after arbitrary edits, adds a review
phase to `/oneshot`, or narrows the explicit comprehensive-review workflow. Current
expanded command prefixes identify those workflows on V2.0.14; assigned full-review
children keep their role. Custom commands must supply their constraints through
normal instructions and review-tool policy.

Recommended reviewers are recorded. Actual launched-reviewer counts are **unknown**;
selection counts must not be reported as completed reviews or avoided charges.

## Context and recovery

Selection starts at **16,000 UTF-16 characters**, targeting **8,000**. These are
character counts, not token counts. Supported shapes:

- V2 grep's structured match array plus matching human-readable text. Both
  representations are selected consistently, with original paths and line numbers.
- Plain textual grep/webfetch results, including a single text part alongside
  non-text parts, when no unrecognized structured representation is present.
- Recognized direct compiler/test commands (`node --test`, pytest, Cargo/Go tests,
  TypeScript) with identifiable diagnostic text. The full failure tail is retained,
  even if it exceeds the target. Unrecognized shell output passes through.

Exact reads, patches, skills, instructions, user attachments, diffs, mutation
results, and generic Code Mode container output are not filtered. Unknown or
inconsistent representations pass through. Original metadata, tool pairing, and
non-text parts are preserved. Already-filtered results carry a processed marker.

Each replacement includes an opaque recovery ID and expiration. Call
`jev_context_read` with `id`, optional `offset` (default 0), and `limit` (default and
maximum 16,000). Offsets count UTF-16 characters. References work only in the
session that produced them. Recovery reads bypass selection and never rerun the
original command. Disabling Jev does not prevent recovery.

Complete **pre-filter** text is written atomically before replacing output. An
upstream truncation marker remains visible; recovery cannot restore text the
original tool never supplied. Failed writes leave the result unchanged.

Records expire after **30 days**, with daily best-effort cleanup. Cache roots:

- Linux: `$XDG_CACHE_HOME/opencode/jev`, or `~/.cache/opencode/jev`.
- Windows: `%LOCALAPPDATA%/opencode/jev`, with a home-cache fallback.

Directories/files use user-only permissions where supported. Runtime paths are
platform-neutral; live Windows behavior has not been exercised.

## Configuration and bounds

Defaults live in `config.mjs`. V2 plugin options can override the same keys when
loading the plugin explicitly; avoid loading the same plugin twice. Unknown keys
and invalid values disable setup with a local configuration error.

| Setting | Default |
| --- | --- |
| Model / endpoint | `typesafe/jev-1.13` / OpenRouter `/api/v1/systemone` |
| Interactive stage deadline | 2,000 ms, including queue time |
| Concurrent transport requests | 2 per plugin instance |
| Serialized request / response guards | 48,000 / 262,144 bytes |
| Exact-decision cache | 256 entries, 15 minutes, in memory |
| Cooldown | 3 consecutive transport/auth failures → 30 seconds |
| Skill shortlist / suggestion cap | 6 checked / 3 suggested |
| Routing confidence threshold | 0.8 |
| Specialist/skill fit and context keep probability | 0.65 |
| Review omission probability | Below 0.15; uncertain dimensions retained |

Thresholds are initial tunable policy, not calibrated correctness guarantees.
OpenRouter documents a 32,000-token Jev request limit; the byte guard is a
conservative size estimate, not an exact tokenizer. Requirements are never silently
truncated. Multi-batch stages share one deadline, and incomplete scoring falls back.
Cached answers are keyed by credentials, backend/model, rubric, and all inputs;
raw source text and keys are not stored in the decision cache. Each subscriber has
independent cancellation, so cancelling one session does not cancel another's
shared request.

## Usage and verification status

`/jev status` shows Jev costs separately from coding-agent costs. One transport
request is attributed to its initiating session; other consumers get shared/cache
hits. `usage.cost` is recorded when returned. Missing cost is **unknown**; an
input-token estimate at $0.042/M tokens is labelled separately. No avoided calls or
percentage savings are invented. Fixed coding subscriptions may yield quota rather
than invoice savings. The latest 100 metadata-only summaries are retained per
session along with aggregate counters.

Verified on Linux with **OpenCode 2.0.14**:

- Prompt-time switching precedes model dispatch; explicit initial selection and
  silent same-model re-selection behavior were checked on the installed runtime.
- Controls load through normal local-plugin discovery. Off and pin survive a
  location reload and a moved/resumed session; smoke sessions used zero model tokens.
- An actual 27,091-character V2 grep result replayed with deterministic scores
  selected 1,804 characters (16 of 250 matches). Two recovery reads reproduced the
  original text completely. This measures fixture selection, not Jev quality.
- Focused tests cover transport, independent cancellation, accounting, session
  isolation, routing/pins, skill fit, recovery, review policy, and cross-feature
  stale-result handling. Run changed files individually with
  `node --test Linux/opencode/tests/jev-<module>.test.mjs`.

**Live decision validation is blocked:** the saved OpenRouter credential returned
HTTP **401** from both `/api/v1/systemone` and the non-billable `/api/v1/key` check on
2026-09-27. Doctor reported authentication fallback in 137 ms; no served model or
billed usage was returned. Reconnect OpenRouter, run `/jev doctor`, then exercise a
small task plus continuation, an oversized-result investigation, and a substantial
review. Successful live decision quality, downstream outcomes, and savings have
not yet been established.

The post-restart retry also returned HTTP 401 (144 ms). Restarting alone did not
refresh the saved credential. Independent code review found three issues—stale
hint publication, incomplete full-review status, and accumulating follow-up
context—which were fixed with failing-then-passing regressions. All **43** focused
tests passed after those fixes.
