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

TIERS = {
  "light": {
    "openai": {"id": "gpt-5.6-terra", "variant": "medium"},
    "anthropic": {"id": "claude-haiku-4-5-20251001", "variant": "high"},
  },
  "coding": {
    "openai": {"id": "gpt-5.6-luna", "variant": "max"},
    "anthropic": {"id": "claude-sonnet-5", "variant": "max"},
  },
}


def load_module():
  spec = importlib.util.spec_from_file_location("apply_agent_routing", MODULE_PATH)
  if spec is None or spec.loader is None:
    raise RuntimeError(f"cannot load {MODULE_PATH}")
  module = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(module)
  return module


def manifest_for(agents, tiers=None, **extra):
  return {"default_provider": "openai", "tiers": tiers if tiers is not None else TIERS, "agents": agents, **extra}


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

  def write_routing(self, agents, tiers=None, **extra):
    """Write a well-formed manifest routing `agents` (a name -> tier mapping)."""
    self.write_manifest(manifest_for(agents, tiers, **extra))

  def write_manifest(self, value):
    self.routing.write_text(json.dumps(value), encoding="utf-8")

  def test_strips_only_model_and_variant_and_is_idempotent(self):
    path = self.write_agent(
      "worker",
      "name: worker\ndescription: Worker.\nmode: subagent\nmodel: openai/gpt-6-astra\nvariant: high\ncolor: blue\n",
    )
    self.write_routing({"worker": "light"})

    self.module.apply_routing(self.agents, self.routing)
    first = path.read_text(encoding="utf-8")
    self.module.apply_routing(self.agents, self.routing)
    second = path.read_text(encoding="utf-8")

    self.assertEqual(first, second)
    self.assertIn("description: Worker.\n", first)
    self.assertIn("mode: subagent\n", first)
    self.assertIn("color: blue\n", first)
    self.assertNotIn("model:", first)
    self.assertNotIn("variant:", first)
    self.assertTrue(first.endswith("\n\nAgent body.\n"))

  def test_rejects_agent_file_missing_from_manifest(self):
    self.write_agent("worker", "name: worker\nmodel: old/model\n")
    self.write_routing({"different": "light"})

    with self.assertRaisesRegex(self.module.RoutingError, r"agents missing from routing manifest: \['worker'\]"):
      self.module.apply_routing(self.agents, self.routing)

  def test_accepts_manifest_entries_without_an_agent_file(self):
    path = self.write_agent("worker", "name: worker\nmodel: old/model\n")
    # plan and general are builtins the plugin routes by ID; they have no file.
    self.write_routing({"worker": "light", "plan": "coding", "general": "coding"})

    self.module.apply_routing(self.agents, self.routing)

    self.assertNotIn("model:", path.read_text(encoding="utf-8"))

  def test_rejects_unknown_tier_reference(self):
    self.write_agent("worker", "name: worker\nmodel: old/model\n")
    self.write_routing({"worker": "reasoning"})

    with self.assertRaisesRegex(self.module.RoutingError, "invalid tier for worker"):
      self.module.apply_routing(self.agents, self.routing)

  def test_rejects_malformed_and_non_object_manifests(self):
    self.write_agent("worker", "name: worker\nmodel: old/model\n")
    cases = (("{", "invalid routing manifest"), ("[]", "expected an object"))

    for content, message in cases:
      with self.subTest(content=content):
        self.routing.write_text(content, encoding="utf-8")
        with self.assertRaisesRegex(self.module.RoutingError, message):
          self.module.apply_routing(self.agents, self.routing)

  def test_rejects_missing_or_empty_tiers_and_agents(self):
    self.write_agent("worker", "name: worker\nmodel: old/model\n")
    cases = (
      ({"agents": {"worker": "light"}}, "non-empty tiers"),
      ({"tiers": {}, "agents": {"worker": "light"}}, "non-empty tiers"),
      ({"tiers": TIERS}, "non-empty agents"),
      ({"tiers": TIERS, "agents": {}}, "non-empty agents"),
      ({"tiers": TIERS, "agents": []}, "non-empty agents"),
    )

    for value, message in cases:
      with self.subTest(value=value):
        self.write_manifest(value)
        with self.assertRaisesRegex(self.module.RoutingError, message):
          self.module.apply_routing(self.agents, self.routing)

  def test_rejects_invalid_tier_targets(self):
    self.write_agent("worker", "name: worker\nmodel: old/model\n")
    cases = (
      ({"light": []}, "non-empty provider map"),
      ({"light": {}}, "non-empty provider map"),
      ({"light": {"openai": {"variant": "high"}}}, "invalid target for light.openai"),
      ({"light": {"openai": {"id": "m", "extra": "x"}}}, "invalid target for light.openai"),
      ({"light": {"openai": {"id": 1}}}, "invalid id for light.openai"),
      ({"light": {"openai": {"id": "m", "variant": 1}}}, "invalid variant for light.openai"),
      ({"light": {"openai": {"id": ""}}}, "invalid id for light.openai"),
      ({"light": {"openai": {"id": "m\nname: replaced"}}}, "invalid id for light.openai"),
    )

    for tiers, message in cases:
      with self.subTest(tiers=tiers):
        self.write_routing({"worker": "light"}, tiers=tiers)
        with self.assertRaisesRegex(self.module.RoutingError, message):
          self.module.apply_routing(self.agents, self.routing)

  def test_rejects_default_provider_absent_from_tiers(self):
    self.write_agent("worker", "name: worker\nmodel: old/model\n")
    self.write_routing({"worker": "light"}, default_provider="google")

    with self.assertRaisesRegex(self.module.RoutingError, "invalid default_provider"):
      self.module.apply_routing(self.agents, self.routing)

  def test_rejects_invalid_manifest_without_modifying_agent(self):
    original = b"---\nname: worker\nmodel: old/model\n---\n\nAgent body.\n"
    path = self.agents / "worker.md"
    path.write_bytes(original)
    self.write_routing({"worker": "missing-tier"})

    with self.assertRaisesRegex(self.module.RoutingError, "invalid tier for worker"):
      self.module.apply_routing(self.agents, self.routing)
    self.assertEqual(path.read_bytes(), original)

  def test_rejects_missing_frontmatter_delimiters(self):
    self.write_routing({"worker": "light"})
    cases = (
      (b"name: worker\n---\nBody\n", "missing opening delimiter"),
      (b"---\nname: worker\nBody\n", "missing closing delimiter"),
    )

    for content, message in cases:
      with self.subTest(message=message):
        (self.agents / "worker.md").write_bytes(content)
        with self.assertRaisesRegex(self.module.RoutingError, message):
          self.module.apply_routing(self.agents, self.routing)

  def test_rejects_frontmatter_that_is_only_model_and_variant(self):
    self.write_agent("worker", "model: openai/gpt-6-astra\nvariant: high\n")
    self.write_routing({"worker": "light"})

    with self.assertRaisesRegex(self.module.RoutingError, "nothing left after stripping"):
      self.module.apply_routing(self.agents, self.routing)

  def test_preserves_crlf_and_missing_final_newline(self):
    path = self.agents / "worker.md"
    path.write_bytes(b"---\r\nname: worker\r\nmodel: old/model\r\nvariant: max\r\n---\r\n\r\nBody without newline")
    self.write_routing({"worker": "light"})

    self.module.apply_routing(self.agents, self.routing)

    self.assertEqual(path.read_bytes(), b"---\r\nname: worker\r\n---\r\n\r\nBody without newline")

  def test_validates_every_agent_before_writing_any_file(self):
    alpha = self.write_agent("alpha", "name: alpha\nmodel: old/model\n")
    original = alpha.read_bytes()
    (self.agents / "zeta.md").write_bytes(b"not frontmatter\n")
    self.write_routing({"alpha": "light", "zeta": "light"})

    with self.assertRaisesRegex(self.module.RoutingError, "invalid frontmatter"):
      self.module.apply_routing(self.agents, self.routing)
    self.assertEqual(alpha.read_bytes(), original)

  def test_rejects_missing_and_non_directory_agent_paths(self):
    self.write_routing({"worker": "light"})
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
    (cli_root / "agent-routing.json").write_text(json.dumps(manifest_for({"worker": "light"})), encoding="utf-8")

    result = subprocess.run([sys.executable, str(script)], text=True, capture_output=True, check=False)

    self.assertEqual(result.returncode, 0)
    self.assertEqual(result.stdout, "updated 1 agent files\n")
    self.assertEqual(result.stderr, "")
    self.assertNotIn("model:", (cli_agents / "worker.md").read_text(encoding="utf-8"))

  def test_cli_reports_missing_default_agents_directory_without_traceback(self):
    cli_root = self.root / "cli"
    cli_root.mkdir()
    script = cli_root / "apply_agent_routing.py"
    shutil.copy2(MODULE_PATH, script)
    (cli_root / "agent-routing.json").write_text(json.dumps(manifest_for({"worker": "light"})), encoding="utf-8")

    result = subprocess.run([sys.executable, str(script)], text=True, capture_output=True, check=False)

    self.assertEqual(result.returncode, 1)
    self.assertEqual(result.stdout, "")
    self.assertRegex(result.stderr, r"^error: invalid agent inventory: .+ is not a directory\n$")
    self.assertNotIn("Traceback", result.stderr)

  def test_reads_each_agent_once_when_comparing_changes(self):
    path = self.write_agent("worker", "name: worker\nmodel: old/model\n")
    self.write_routing({"worker": "light"})
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
    self.assertNotIn(b"model:", real_read_bytes(path))

  def test_stages_flushes_and_atomically_replaces_in_same_directory(self):
    path = self.write_agent("worker", "name: worker\nmodel: old/model\n")
    self.write_routing({"worker": "light"})
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
    self.assertNotIn(b"model:", staged_content)
    self.assertEqual(fsync.call_count, 1)

  def test_cleans_staged_file_and_preserves_agent_when_flush_fails(self):
    path = self.write_agent("worker", "name: worker\nmodel: old/model\n")
    original = path.read_bytes()
    self.write_routing({"worker": "light"})

    with mock.patch("os.fsync", side_effect=OSError("disk full")):
      with self.assertRaisesRegex(self.module.RoutingError, "cannot stage agent worker.md"):
        self.module.apply_routing(self.agents, self.routing)

    self.assertEqual(path.read_bytes(), original)
    self.assertEqual(sorted(candidate.name for candidate in self.agents.iterdir()), ["worker.md"])

  def test_cleans_staged_file_and_preserves_agent_when_replace_fails(self):
    path = self.write_agent("worker", "name: worker\nmodel: old/model\n")
    original = path.read_bytes()
    self.write_routing({"worker": "light"})

    with mock.patch("os.replace", side_effect=OSError("permission denied")):
      with self.assertRaisesRegex(self.module.RoutingError, "cannot replace agent worker.md"):
        self.module.apply_routing(self.agents, self.routing)

    self.assertEqual(path.read_bytes(), original)
    self.assertEqual(sorted(candidate.name for candidate in self.agents.iterdir()), ["worker.md"])

  def test_does_not_replace_already_stripped_agent(self):
    self.write_agent("worker", "name: worker\nmode: subagent\n")
    self.write_routing({"worker": "light"})

    with mock.patch("os.replace") as replace:
      self.module.apply_routing(self.agents, self.routing)

    replace.assert_not_called()

  def test_translates_agent_read_failure(self):
    path = self.write_agent("worker", "name: worker\nmodel: old/model\n")
    self.write_routing({"worker": "light"})
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
    self.write_routing({"worker": "light"})
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
    self.write_routing({"worker": "light"})

    self.module.apply_routing(self.agents, self.routing)

    self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o644)

  def test_translates_agent_mode_read_failure_before_staging(self):
    path = self.write_agent("worker", "name: worker\nmodel: old/model\n")
    original = path.read_bytes()
    self.write_routing({"worker": "light"})
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
    self.write_routing({"worker": "light"})

    with mock.patch("os.chmod", side_effect=OSError("operation not permitted")):
      with self.assertRaisesRegex(self.module.RoutingError, "cannot stage agent worker.md"):
        self.module.apply_routing(self.agents, self.routing)

    self.assertEqual(path.read_bytes(), original)
    self.assertEqual(sorted(candidate.name for candidate in self.agents.iterdir()), ["worker.md"])


class RepositoryManifestTest(unittest.TestCase):
  """The checked-in manifest must route every agent that ships in this repo."""

  def test_repository_manifest_matches_agent_inventory(self):
    module = load_module()
    base = MODULE_PATH.parent
    manifest = module._load_manifest(base / "agent-routing.json")
    inventory = {path.stem for path in (base / "agents").glob("*.md")}

    self.assertEqual(inventory - set(manifest["agents"]), set())


if __name__ == "__main__":
  unittest.main()
