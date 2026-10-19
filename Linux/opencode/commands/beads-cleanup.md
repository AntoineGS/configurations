---
description: Review the Beads database, close finished-and-merged tasks, recommend the rest
subagent: false
---

Review every non-closed Beads issue in this repo (or every `~/gits/*/.beads`
if the scope says "all"; split 40+ issues across subagents, close them yourself).

- Close only work reachable from the default branch (commit naming the ID,
  merged branch, or recorded SHA that is an ancestor) with acceptance criteria
  met and nothing waiting on me (`needs:user`, push, deploy). Epics close only
  when all children are closed. `bd close <id> --reason "Merged in <sha> ..."`.
- Recommend the rest: duplicate/superseded, outdated, abandoned claim, or keep.
- Report closed (with SHA), a recommendations table, items waiting on me, and
  counts. Run approved recommendations exactly; `delete`, `prune`, `purge`,
  `gc`, `compact`, `flatten`, `sync` and `dolt push` need me to name them.

Optional scope (repository path or "all"): $ARGUMENTS
