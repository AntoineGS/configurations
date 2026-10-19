---
description: Merge this work into main/master, close the completed tasks, and summarize deferred tasks
subagent: false
---

Merge this conversation's branches (plus any named below) into the default
branch, close the tasks they complete, and summarize deferred tasks. This
authorizes local merges only, never a push. Unsure which branches: list and stop.

- Before merging, each branch is committed (planning docs stay uncommitted),
  verified and reviewed. Stop if the target checkout has uncommitted changes in
  touched files; leave my other changes alone.
- `git merge --no-ff`, dependencies first. Resolve mechanical conflicts only;
  behavioral ones get `git merge --abort` and are skipped. Rerun build/tests;
  fix only small merge-caused failures. Then `git worktree remove` (no
  `--force`) and `git branch -d`.
- Close tasks now reachable from the default branch with criteria met
  (`bd close <id> --reason "Merged to <default> in <sha>"`), except `needs:user`
  or ones waiting on me (note what is left). Epics only when all children close.
- Report merged (SHA, verification), skipped, closed tasks, a table of related
  deferred tasks (ID, title, priority, why, decision needed) plus the count of
  other deferred ones, and how far the default branch is ahead of `origin`.

Optional branches, task IDs or notes: $ARGUMENTS
