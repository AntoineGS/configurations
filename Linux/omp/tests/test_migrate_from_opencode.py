import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from Linux.omp import migrate_from_opencode
from Linux.omp.migrate_from_opencode import migrate_command, migrate_component


class MigrationTests(unittest.TestCase):
  def setUp(self):
    self.tempdir = tempfile.TemporaryDirectory()
    root = Path(self.tempdir.name)
    self.source = root / "source"
    self.destination = root / "destination"

    (self.source / "agents").mkdir(parents=True)
    (self.source / "skills" / "sample" / "references").mkdir(parents=True)
    (self.source / "commands").mkdir(parents=True)

    (self.source / "agents" / "reviewer.md").write_text(
      "---\n"
      "name: suite__reviewer\n"
      "description: Review code\n"
      "mode: subagent\n"
      "model: old/model\n"
      "variant: max\n"
      "---\n\n"
      "Review the assigned code.\n",
      encoding="utf-8",
    )
    (self.source / "skills" / "sample" / "SKILL.md").write_text(
      "---\nname: sample\ndescription: Sample skill\n---\n\nSkill body.\n",
      encoding="utf-8",
    )
    (self.source / "skills" / "sample" / "references" / "guide.md").write_text(
      "reference content",
      encoding="utf-8",
    )
    (self.source / "commands" / "suite__review.md").write_text(
      """---
description: Review a target
argument-hint: <target>
subtask: true
---

Use subagent_type: "suite-reviewer" with the Task tool.
All `subagent_type` references use agents bundled with this plugin or `general-purpose`.
AskUserQuestion tool is available, but do not use EnterPlanMode.
Run /ui-design:create-component when needed.

```
Task:
  subagent_type: "suite-reviewer"
  description: "Review the target"
  prompt: |
    Review the target thoroughly.
```
""",
      encoding="utf-8",
    )
    (self.source / "commands" / "context.md").write_text(
      "---\ndescription: Context\n---\n\nNative context command.\n",
      encoding="utf-8",
    )
    (self.source / "commands" / "literal-dollar-fixtures.md").write_text(
      """---
description: Literal dollar fixtures
---

JavaScript replacement groups:

```javascript
const rendered = source.replace(pattern, '<template v-if="$1">$2</template>');
```

Shell positional parameters:

```bash
value="$1"
database=$2
```

Currency examples:

Annual Cost: $150/hour = $36,000

OMP placeholders remain intentional: $ARGUMENTS $@ $@[1]
""",
      encoding="utf-8",
    )

  def tearDown(self):
    self.tempdir.cleanup()

  def test_agent_keeps_identity_and_drops_opencode_routing(self):
    migrate_component(self.source, self.destination, "agents")
    output = (self.destination / "agents" / "reviewer.md").read_text()
    self.assertIn("name: suite__reviewer", output)
    self.assertIn("description: Review code", output)
    self.assertNotIn("mode:", output)
    self.assertNotIn("model:", output)
    self.assertNotIn("variant:", output)
    self.assertIn("Review the assigned code.", output)
    self.assertTrue(output.endswith("\n"))

  def test_skill_tree_is_copied_with_support_files(self):
    migrate_component(self.source, self.destination, "skills")
    self.assertEqual(
      "reference content",
      (self.destination / "skills" / "sample" / "references" / "guide.md").read_text(),
    )

  def test_command_uses_omp_fields_and_agent_names(self):
    migrate_component(self.source, self.destination, "commands")
    output = (self.destination / "commands" / "suite__review.md").read_text()
    self.assertIn("**Arguments:** `<target>`", output)
    self.assertIn('agent: "suite__reviewer"', output)
    self.assertIn("`task` tool", output)
    self.assertIn("`ask` tool", output)
    self.assertIn("All `agent` references use agents bundled with this plugin or `task`.", output)
    self.assertNotIn("subtask:", output)
    self.assertNotIn("argument-hint:", output)
    self.assertNotIn("subagent_type", output)
    self.assertNotIn("general-purpose", output)
    self.assertNotIn("AskUserQuestion", output)
    self.assertNotIn("EnterPlanMode", output)

  def test_task_dispatch_uses_omp_batch_shape_and_waits_for_results(self):
    migrate_component(self.source, self.destination, "commands")
    output = (self.destination / "commands" / "suite__review.md").read_text()
    self.assertIn(
      "Task:\n"
      "  context: |\n"
      "    This batch handles the workflow assignment: Review the target.\n"
      "    Use the current workspace and return the complete final result to the parent.\n"
      "  tasks:\n"
      '    - agent: "suite__reviewer"\n'
      "      task: |\n"
      "        Review the target thoroughly.\n",
      output,
    )
    self.assertNotIn('  description: "Review the target"', output)
    self.assertNotIn("  prompt: |", output)
    self.assertIn(
      "After this dispatch, use the `hub` tool with `op: \"wait\"` and the returned job ID(s) "
      "(or omit `ids` to wait on all jobs you own) until every spawned job has delivered its final result. "
      "Associate each delivered result with this task before saving artifacts or advancing state.",
      output,
    )
    self.assertTrue(output.endswith("\n"))

  def test_context_command_is_omitted_for_native_equivalent(self):
    migrate_component(self.source, self.destination, "commands")
    self.assertFalse((self.destination / "commands" / "context.md").exists())

  def test_command_without_dispatch_preserves_terminal_newline(self):
    output = migrate_command("---\ndescription: No dispatch\n---\n\nNo dispatch here.\n")
    self.assertTrue(output.endswith("\n"))

  def test_command_normalizes_literal_dollars_and_preserves_omp_placeholders(self):
    migrate_component(self.source, self.destination, "commands")
    output = (self.destination / "commands" / "literal-dollar-fixtures.md").read_text()

    self.assertIn(r"\x241", output)
    self.assertIn(r"\x242", output)
    self.assertIn('value="${1}"', output)
    self.assertIn("database=${2}", output)
    self.assertIn("Annual Cost: USD 150/hour = USD 36,000", output)
    self.assertIn("OMP placeholders remain intentional: $ARGUMENTS $@ $@[1]", output)
    self.assertNotRegex(output, r"\$[0-9]+")

  def test_command_rejects_unclassified_numeric_dollars(self):
    with self.assertRaisesRegex(ValueError, "unclassified numeric dollar token"):
      migrate_command("---\ndescription: Unclassified\n---\n\nLiteral prose: $1\n")

  def test_parallel_dispatch_waits_for_all_results_before_consolidating(self):
    source = """---
description: Parallel review
---

Run both agents in parallel.

### Step A

```
Task:
  subagent_type: "suite-reviewer"
  description: "Review architecture"
  prompt: |
    Review architecture.
```

### Step B

```
Task:
  subagent_type: "suite-reviewer"
  description: "Review security"
  prompt: |
    Review security.
```

After both complete, consolidate into `.review/report.md`.
"""
    output = migrate_command(source)
    self.assertEqual(output.count("  context: |"), 2)
    self.assertEqual(output.count("  tasks:"), 2)
    self.assertEqual(output.count("After dispatching this parallel group"), 1)
    self.assertNotIn("After both complete", output)
    self.assertNotIn("After this dispatch", output)
    self.assertIn("Then consolidate into `.review/report.md`.", output)

  def test_cli_uses_native_agent_destination_root(self):
    with mock.patch.object(migrate_from_opencode, "migrate_component") as migrate:
      with mock.patch.object(sys, "argv", ["migrate_from_opencode.py", "--component", "agents"]):
        migrate_from_opencode.main()

    repository_root = Path(__file__).resolve().parents[3]
    self.assertEqual(
      (repository_root / "Linux" / "opencode", repository_root / "Linux" / "omp" / "agent", "agents"),
      migrate.call_args.args,
    )


if __name__ == "__main__":
  unittest.main()
