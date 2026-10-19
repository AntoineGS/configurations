---
description: Complete tasks autonomously using subagents and worktrees
subagent: false
---

Complete the clear, low-risk tasks from the list/path below or this
conversation without asking questions. No clear list: report and stop.

- I authorize skipping routine approval prompts and delegating to subagents in
  worktrees under `.worktrees/`; without either facility, skip the task rather
  than editing the main checkout. Project instructions, required tests/reviews
  and safety rules still apply; never discard work or force-remove worktrees;
  commit, merge or push only if authorized before.
- Skip and record anything ambiguous, risky, destructive or needing a decision
  or access only I have; continue until no eligible task remains.
- Parallelize independent tasks, serialize overlapping ones, verify subagent
  work yourself, then mark tasks done in the existing list.
- Report completed tasks with checks, skipped items with reasons, decisions
  needed, worktrees/branches, and integration status.

Optional list/path/scope: $ARGUMENTS
