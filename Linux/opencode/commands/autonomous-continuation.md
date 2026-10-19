---
description: Continue the current work autonomously with subagents and worktrees
subagent: false
---

I am not watching: finish this conversation's agreed work without questions,
then send one report. No agreed work means report that and stop.

- I authorize self-approving specs, plans and "proceed?" checks, delegating to
  subagents, worktrees under `.worktrees/`, and local branch commits. Project
  instructions, required tests/reviews and safety rules still apply; merge,
  push, deploy or shared writes only with earlier authorization.
- Fix discovered items only if in scope or in touched code, small, low risk
  and verifiable; defer the rest (`bd create ... --status deferred`) along with
  decisions only I can make, and keep going.
- Parallelize independent streams, serialize overlapping ones, rerun each
  subagent's verification yourself, and leave the main checkout untouched.
- Report completed work (evidence, branches, SHAs), fixes along the way,
  deferred items with the decision needed, and integration status.

Optional notes or scope: $ARGUMENTS
