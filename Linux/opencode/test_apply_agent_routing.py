import contextlib
import importlib.util
import io
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).with_name("apply_agent_routing.py")


def load_module():
  spec = importlib.util.spec_from_file_location("apply_agent_routing", MODULE_PATH)
  if spec is None or spec.loader is None:
    raise RuntimeError(f"cannot load {MODULE_PATH}")
  module = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(module)
  return module


class ApplyAgentRoutingTest(unittest.TestCase):
  def setUp(self):
    self.module = load_module()
    self.tempdir = tempfile.TemporaryDirectory()
    self.root = Path(self.tempdir.name)
    self.agents = self.root / "agents"
    self.agents.mkdir()
    self.routing = self.root / "agent-routing.json"

  def tearDown(self):
    self.tempdir.cleanup()

  def write_agent(self, name, frontmatter, body="Agent body.\n"):
    path = self.agents / f"{name}.md"
    path.write_text(f"---\n{frontmatter}---\n\n{body}", encoding="utf-8")
    return path

  def write_routing(self, value):
    self.routing.write_text(json.dumps(value), encoding="utf-8")

  def test_rewrites_only_model_and_variant_and_is_idempotent(self):
    path = self.write_agent(
      "worker",
      "name: worker\ndescription: Worker.\nmode: subagent\nmodel: old/model\ncolor: blue\n",
    )
    self.write_routing({"worker": {"model": "openai/gpt-5.6-terra", "variant": "high"}})

    self.module.apply_routing(self.agents, self.routing)
    first = path.read_text(encoding="utf-8")
    self.module.apply_routing(self.agents, self.routing)
    second = path.read_text(encoding="utf-8")

    self.assertEqual(first, second)
    self.assertIn("description: Worker.\n", first)
    self.assertIn("mode: subagent\n", first)
    self.assertIn("color: blue\n", first)
    self.assertIn("model: openai/gpt-5.6-terra\n", first)
    self.assertIn("variant: high\n", first)
    self.assertTrue(first.endswith("\n\nAgent body.\n"))
    self.assertNotIn("model: old/model", first)

  def test_rejects_inventory_mismatch(self):
    self.write_agent("worker", "name: worker\nmodel: old/model\n")
    self.write_routing({"different": {"model": "openai/gpt-5.6-terra", "variant": "high"}})

    with self.assertRaisesRegex(self.module.RoutingError, "inventory mismatch"):
      self.module.apply_routing(self.agents, self.routing)

  def test_rejects_invalid_route_shape(self):
    self.write_agent("worker", "name: worker\nmodel: old/model\n")
    self.write_routing({"worker": {"model": "openai/gpt-5.6-terra", "variant": "ultra"}})

    with self.assertRaisesRegex(self.module.RoutingError, "invalid variant"):
      self.module.apply_routing(self.agents, self.routing)

  def test_rejects_malformed_and_non_object_manifests(self):
    self.write_agent("worker", "name: worker\nmodel: old/model\n")
    cases = (("{", "invalid routing manifest"), ("[]", "expected an object"))

    for content, message in cases:
      with self.subTest(content=content):
        self.routing.write_text(content, encoding="utf-8")
        with self.assertRaisesRegex(self.module.RoutingError, message):
          self.module.apply_routing(self.agents, self.routing)

  def test_rejects_invalid_route_keys_and_value_types(self):
    self.write_agent("worker", "name: worker\nmodel: old/model\n")
    cases = (
      ({"worker": []}, "invalid route"),
      ({"worker": {"model": "openai/model"}}, "invalid route"),
      ({"worker": {"model": "openai/model", "variant": "high", "extra": True}}, "invalid route"),
      ({"worker": {"model": 1, "variant": "high"}}, "invalid model"),
      ({"worker": {"model": "openai/model", "variant": 1}}, "invalid variant"),
    )

    for routing, message in cases:
      with self.subTest(routing=routing):
        self.write_routing(routing)
        with self.assertRaisesRegex(self.module.RoutingError, message):
          self.module.apply_routing(self.agents, self.routing)

  def test_rejects_models_without_provider_separator(self):
    self.write_agent("worker", "name: worker\nmodel: old/model\n")

    for model in ("", "gpt-5.6-terra"):
      with self.subTest(model=model):
        self.write_routing({"worker": {"model": model, "variant": "high"}})
        with self.assertRaisesRegex(self.module.RoutingError, "invalid model"):
          self.module.apply_routing(self.agents, self.routing)

  def test_rejects_models_with_line_breaks_without_modifying_agent(self):
    original = b"---\nname: worker\nmodel: old/model\n---\n\nAgent body.\n"

    for model in ("openai/model\nname: replaced", "openai/model\rvariant: max"):
      with self.subTest(model=model):
        path = self.agents / "worker.md"
        path.write_bytes(original)
        self.write_routing({"worker": {"model": model, "variant": "high"}})

        with self.assertRaisesRegex(self.module.RoutingError, "invalid model"):
          self.module.apply_routing(self.agents, self.routing)
        self.assertEqual(path.read_bytes(), original)

  def test_rejects_missing_frontmatter_delimiters(self):
    self.write_routing({"worker": {"model": "openai/model", "variant": "high"}})
    cases = (
      (b"name: worker\n---\nBody\n", "missing opening delimiter"),
      (b"---\nname: worker\nBody\n", "missing closing delimiter"),
    )

    for content, message in cases:
      with self.subTest(message=message):
        (self.agents / "worker.md").write_bytes(content)
        with self.assertRaisesRegex(self.module.RoutingError, message):
          self.module.apply_routing(self.agents, self.routing)

  def test_inventory_mismatch_lists_missing_and_unexpected_names(self):
    self.write_agent("alpha", "name: alpha\nmodel: old/model\n")
    self.write_agent("beta", "name: beta\nmodel: old/model\n")
    self.write_routing(
      {
        "beta": {"model": "openai/model", "variant": "high"},
        "gamma": {"model": "openai/model", "variant": "high"},
      }
    )

    with self.assertRaisesRegex(
      self.module.RoutingError,
      r"inventory mismatch: missing=\['alpha'\]; unexpected=\['gamma'\]",
    ):
      self.module.apply_routing(self.agents, self.routing)

  def test_preserves_crlf_and_missing_final_newline(self):
    path = self.agents / "worker.md"
    path.write_bytes(b"---\r\nname: worker\r\nmodel: old/model\r\n---\r\n\r\nBody without newline")
    self.write_routing({"worker": {"model": "openai/model", "variant": "medium"}})

    self.module.apply_routing(self.agents, self.routing)

    self.assertEqual(
      path.read_bytes(),
      b"---\r\nname: worker\r\nmodel: openai/model\r\nvariant: medium\r\n---\r\n\r\nBody without newline",
    )

  def test_validates_every_agent_before_writing_any_file(self):
    alpha = self.write_agent("alpha", "name: alpha\nmodel: old/model\n")
    original = alpha.read_bytes()
    (self.agents / "zeta.md").write_bytes(b"not frontmatter\n")
    self.write_routing(
      {
        "alpha": {"model": "openai/model", "variant": "high"},
        "zeta": {"model": "openai/model", "variant": "high"},
      }
    )

    with self.assertRaisesRegex(self.module.RoutingError, "invalid frontmatter"):
      self.module.apply_routing(self.agents, self.routing)
    self.assertEqual(alpha.read_bytes(), original)

  def test_rejects_missing_and_non_directory_agent_paths(self):
    self.write_routing({})
    non_directory = self.root / "agents-file"
    non_directory.write_text("not a directory", encoding="utf-8")

    for agents in (self.root / "missing", non_directory):
      with self.subTest(agents=agents):
        with self.assertRaisesRegex(self.module.RoutingError, "invalid agent inventory"):
          self.module.apply_routing(agents, self.routing)

  def test_cli_uses_beside_script_defaults_and_reports_updates(self):
    cli_root = self.root / "cli"
    cli_agents = cli_root / "agents"
    cli_agents.mkdir(parents=True)
    script = cli_root / "apply_agent_routing.py"
    shutil.copy2(MODULE_PATH, script)
    (cli_agents / "worker.md").write_text("---\nname: worker\nmodel: old/model\n---\n", encoding="utf-8")
    (cli_root / "agent-routing.json").write_text(
      json.dumps({"worker": {"model": "openai/model", "variant": "high"}}),
      encoding="utf-8",
    )

    result = subprocess.run([sys.executable, str(script)], text=True, capture_output=True, check=False)

    self.assertEqual(result.returncode, 0)
    self.assertEqual(result.stdout, "updated 1 agent files\n")
    self.assertEqual(result.stderr, "")
    self.assertIn("model: openai/model\nvariant: high\n", (cli_agents / "worker.md").read_text(encoding="utf-8"))

  def test_cli_reports_missing_default_agents_directory_without_traceback(self):
    cli_root = self.root / "cli"
    cli_root.mkdir()
    script = cli_root / "apply_agent_routing.py"
    shutil.copy2(MODULE_PATH, script)
    (cli_root / "agent-routing.json").write_text("{}", encoding="utf-8")

    result = subprocess.run([sys.executable, str(script)], text=True, capture_output=True, check=False)

    self.assertEqual(result.returncode, 1)
    self.assertEqual(result.stdout, "")
    self.assertRegex(result.stderr, r"^error: invalid agent inventory: .+ is not a directory\n$")
    self.assertNotIn("Traceback", result.stderr)

  def test_reads_each_agent_once_when_comparing_changes(self):
    path = self.write_agent("worker", "name: worker\nmodel: old/model\n")
    self.write_routing({"worker": {"model": "openai/model", "variant": "high"}})
    real_read_bytes = Path.read_bytes
    agent_reads = 0

    def read_once(candidate):
      nonlocal agent_reads
      if candidate == path:
        agent_reads += 1
        if agent_reads > 1:
          raise OSError("comparison read failed")
      return real_read_bytes(candidate)

    with mock.patch.object(Path, "read_bytes", autospec=True, side_effect=read_once):
      self.module.apply_routing(self.agents, self.routing)

    self.assertEqual(agent_reads, 1)
    self.assertIn(b"model: openai/model\nvariant: high\n", real_read_bytes(path))

  def test_stages_flushes_and_atomically_replaces_in_same_directory(self):
    path = self.write_agent("worker", "name: worker\nmodel: old/model\n")
    self.write_routing({"worker": {"model": "openai/model", "variant": "high"}})
    real_replace = os.replace
    replacements = []

    def inspect_replace(source, destination):
      source_path = Path(source)
      destination_path = Path(destination)
      replacements.append((source_path, destination_path, source_path.read_bytes()))
      real_replace(source, destination)

    with (
      mock.patch("os.fsync", wraps=os.fsync) as fsync,
      mock.patch("os.replace", side_effect=inspect_replace),
    ):
      self.module.apply_routing(self.agents, self.routing)

    self.assertEqual(len(replacements), 1)
    staged, destination, staged_content = replacements[0]
    self.assertEqual(staged.parent, path.parent)
    self.assertEqual(destination, path)
    self.assertIn(b"model: openai/model\nvariant: high\n", staged_content)
    self.assertEqual(fsync.call_count, 1)

  def test_cleans_staged_file_and_preserves_agent_when_flush_fails(self):
    path = self.write_agent("worker", "name: worker\nmodel: old/model\n")
    original = path.read_bytes()
    self.write_routing({"worker": {"model": "openai/model", "variant": "high"}})

    with mock.patch("os.fsync", side_effect=OSError("disk full")):
      with self.assertRaisesRegex(self.module.RoutingError, "cannot stage agent worker.md"):
        self.module.apply_routing(self.agents, self.routing)

    self.assertEqual(path.read_bytes(), original)
    self.assertEqual(sorted(candidate.name for candidate in self.agents.iterdir()), ["worker.md"])

  def test_cleans_staged_file_and_preserves_agent_when_replace_fails(self):
    path = self.write_agent("worker", "name: worker\nmodel: old/model\n")
    original = path.read_bytes()
    self.write_routing({"worker": {"model": "openai/model", "variant": "high"}})

    with mock.patch("os.replace", side_effect=OSError("permission denied")):
      with self.assertRaisesRegex(self.module.RoutingError, "cannot replace agent worker.md"):
        self.module.apply_routing(self.agents, self.routing)

    self.assertEqual(path.read_bytes(), original)
    self.assertEqual(sorted(candidate.name for candidate in self.agents.iterdir()), ["worker.md"])

  def test_does_not_replace_unchanged_agent(self):
    self.write_agent("worker", "name: worker\nmodel: openai/model\nvariant: high\n")
    self.write_routing({"worker": {"model": "openai/model", "variant": "high"}})

    with mock.patch("os.replace") as replace:
      self.module.apply_routing(self.agents, self.routing)

    replace.assert_not_called()

  def test_translates_agent_read_failure(self):
    path = self.write_agent("worker", "name: worker\nmodel: old/model\n")
    self.write_routing({"worker": {"model": "openai/model", "variant": "high"}})
    real_read_bytes = Path.read_bytes

    def fail_agent_read(candidate):
      if candidate == path:
        raise OSError("permission denied")
      return real_read_bytes(candidate)

    with mock.patch.object(Path, "read_bytes", autospec=True, side_effect=fail_agent_read):
      with self.assertRaisesRegex(self.module.RoutingError, "cannot read agent worker.md"):
        self.module.apply_routing(self.agents, self.routing)

  def test_cli_reports_staging_failure_without_traceback(self):
    path = self.write_agent("worker", "name: worker\nmodel: old/model\n")
    original = path.read_bytes()
    self.write_routing({"worker": {"model": "openai/model", "variant": "high"}})
    stdout = io.StringIO()
    stderr = io.StringIO()
    arguments = [str(MODULE_PATH), "--agents", str(self.agents), "--routing", str(self.routing)]

    with (
      mock.patch.object(sys, "argv", arguments),
      mock.patch("os.fsync", side_effect=OSError("disk full")),
      contextlib.redirect_stdout(stdout),
      contextlib.redirect_stderr(stderr),
    ):
      status = self.module.main()

    self.assertEqual(status, 1)
    self.assertEqual(stdout.getvalue(), "")
    self.assertRegex(stderr.getvalue(), r"^error: cannot stage agent worker.md: disk full\n$")
    self.assertNotIn("Traceback", stderr.getvalue())
    self.assertEqual(path.read_bytes(), original)

  def test_updated_agent_retains_exact_permission_bits(self):
    path = self.write_agent("worker", "name: worker\nmodel: old/model\n")
    path.chmod(0o644)
    self.write_routing({"worker": {"model": "openai/model", "variant": "high"}})

    self.module.apply_routing(self.agents, self.routing)

    self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o644)

  def test_translates_agent_mode_read_failure_before_staging(self):
    path = self.write_agent("worker", "name: worker\nmodel: old/model\n")
    original = path.read_bytes()
    self.write_routing({"worker": {"model": "openai/model", "variant": "high"}})
    real_stat = Path.stat

    def fail_agent_stat(candidate, *args, **kwargs):
      if candidate == path:
        raise OSError("permission denied")
      return real_stat(candidate, *args, **kwargs)

    with mock.patch.object(Path, "stat", autospec=True, side_effect=fail_agent_stat):
      with self.assertRaisesRegex(self.module.RoutingError, "cannot read mode for agent worker.md"):
        self.module.apply_routing(self.agents, self.routing)

    self.assertEqual(path.read_bytes(), original)
    self.assertEqual(sorted(candidate.name for candidate in self.agents.iterdir()), ["worker.md"])

  def test_cleans_staged_file_when_chmod_fails(self):
    path = self.write_agent("worker", "name: worker\nmodel: old/model\n")
    original = path.read_bytes()
    self.write_routing({"worker": {"model": "openai/model", "variant": "high"}})

    with mock.patch("os.chmod", side_effect=OSError("operation not permitted")):
      with self.assertRaisesRegex(self.module.RoutingError, "cannot stage agent worker.md"):
        self.module.apply_routing(self.agents, self.routing)

    self.assertEqual(path.read_bytes(), original)
    self.assertEqual(sorted(candidate.name for candidate in self.agents.iterdir()), ["worker.md"])


if __name__ == "__main__":
  unittest.main()
