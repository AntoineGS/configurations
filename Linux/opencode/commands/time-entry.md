---
description: Draft my time entries (TIMETASKS inserts) from last week's commits
subagent: false
---

Draft `TIMETASKS` inserts in the `todos` database from my commits: one entry
per day and MM, user `ANS`, period = previous Monday to Sunday unless given.

- Commits: every repo under `~/gits`, `git log --all --no-merges
  --author='Antoine Gaudreau Simard'`, deduped by hash and by subject + day.
- Read my last 60 days of `TIMETASKS` (`ROWS n`, cast `BILLINGINFO`). Skip work
  already entered in the period; copy the MM, `TIMETYPEID`, `CUSTID` and terse
  verb-led style of past entries. Unknown topic: likely MM + `-- VERIFY MM`.
- Each MM needs `HD2.APPRVDBY = 'A'`, and a matching `HD2TODOSID` if it has
  `HD2TODOS` rows with `EXTREF1 IS NULL`, or the triggers reject the insert.
- `NETTIME` is an estimate (0.25 steps, ~7-8h per day) marked `-- est.`.
- Write `reports/time-entry-<start>.sql` (`GEN_ID(NUMAPPEL, 1)`, `'MM/DD/YYYY'`
  dates, quotes doubled), `check_sql` one statement, show a per-day summary.
  Run the inserts only after I explicitly approve the final script.

Optional period or notes: $ARGUMENTS
