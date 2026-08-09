import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from Linux.omp import migrate_from_opencode
from Linux.omp.migrate_from_opencode import migrate_component


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
AskUserQuestion tool is available, but do not use EnterPlanMode.
Run /ui-design:create-component when needed.
""",
      encoding="utf-8",
    )
    (self.source / "commands" / "context.md").write_text(
      "---\ndescription: Context\n---\n\nNative context command.\n",
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
    self.assertNotIn("subtask:", output)
    self.assertNotIn("argument-hint:", output)
    self.assertNotIn("subagent_type", output)
    self.assertNotIn("AskUserQuestion", output)
    self.assertNotIn("EnterPlanMode", output)

  def test_context_command_is_omitted_for_native_equivalent(self):
    migrate_component(self.source, self.destination, "commands")
    self.assertFalse((self.destination / "commands" / "context.md").exists())

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
