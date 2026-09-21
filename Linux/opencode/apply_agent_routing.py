"""Keep agent frontmatter free of provider-specific models.

Routing lives in agent-routing.json and is applied at runtime by the
agent-provider-routing plugin, which assigns each agent the model its tier
maps to for the active provider. Frontmatter must therefore carry no model or
variant line; this script validates the manifest against the agents on disk and
strips those lines.
"""

import argparse
import json
import os
import stat
import sys
import tempfile
from pathlib import Path


class RoutingError(Exception):
  pass


def _load_manifest(routing_path: Path) -> dict:
  try:
    manifest = json.loads(routing_path.read_text(encoding="utf-8"))
  except (OSError, UnicodeError, json.JSONDecodeError) as error:
    raise RoutingError(f"invalid routing manifest: {error}") from error

  if not isinstance(manifest, dict):
    raise RoutingError("invalid routing manifest: expected an object")

  tiers = manifest.get("tiers")
  if not isinstance(tiers, dict) or not tiers:
    raise RoutingError("invalid routing manifest: expected a non-empty tiers object")

  for tier, providers in tiers.items():
    if not isinstance(providers, dict) or not providers:
      raise RoutingError(f"invalid tier {tier}: expected a non-empty provider map")
    for provider, target in providers.items():
      if not isinstance(target, dict) or not set(target) <= {"id", "variant"} or "id" not in target:
        raise RoutingError(f"invalid target for {tier}.{provider}: expected id and optional variant")
      for field, value in target.items():
        if not isinstance(value, str) or not value or "\n" in value or "\r" in value:
          raise RoutingError(f"invalid {field} for {tier}.{provider}")

  agents = manifest.get("agents")
  if not isinstance(agents, dict) or not agents:
    raise RoutingError("invalid routing manifest: expected a non-empty agents object")

  for name, tier in agents.items():
    if not isinstance(tier, str) or tier not in tiers:
      raise RoutingError(f"invalid tier for {name}: {tier!r} is not a defined tier")

  default_provider = manifest.get("default_provider")
  if default_provider is not None:
    known = {provider for providers in tiers.values() for provider in providers}
    if default_provider not in known:
      raise RoutingError(f"invalid default_provider: {default_provider!r} is not a defined provider")

  return manifest


def _rewritten_content(path: Path) -> tuple[bytes, bytes]:
  try:
    content = path.read_bytes()
  except OSError as error:
    raise RoutingError(f"cannot read agent {path.name}: {error}") from error

  lines = content.splitlines(keepends=True)
  if not lines or lines[0].rstrip(b"\r\n") != b"---":
    raise RoutingError(f"invalid frontmatter in {path.name}: missing opening delimiter")

  closing = next((index for index, line in enumerate(lines[1:], 1) if line.rstrip(b"\r\n") == b"---"), None)
  if closing is None:
    raise RoutingError(f"invalid frontmatter in {path.name}: missing closing delimiter")

  frontmatter = [line for line in lines[1:closing] if not line.startswith((b"model:", b"variant:"))]
  if not frontmatter:
    raise RoutingError(f"invalid frontmatter in {path.name}: nothing left after stripping model and variant")
  return content, b"".join([lines[0], *frontmatter, *lines[closing:]])


def _cleanup_staged(staged: list[tuple[Path, Path]]) -> OSError | None:
  cleanup_error = None
  for _, temporary in staged:
    try:
      temporary.unlink(missing_ok=True)
    except OSError as error:
      if cleanup_error is None:
        cleanup_error = error
  return cleanup_error


def _apply_routing(agents_dir: Path, routing_path: Path) -> int:
  manifest = _load_manifest(routing_path)
  if not agents_dir.is_dir():
    raise RoutingError(f"invalid agent inventory: {agents_dir} is not a directory")
  try:
    agent_paths = sorted(agents_dir.glob("*.md"))
  except OSError as error:
    raise RoutingError(f"invalid agent inventory: {error}") from error

  # Manifest entries without a file are builtins such as plan and general, which
  # the plugin routes by ID. A file without a manifest entry would silently keep
  # whatever model it shipped with, so that direction is an error.
  unrouted = sorted({path.stem for path in agent_paths} - set(manifest["agents"]))
  if unrouted:
    raise RoutingError(f"agents missing from routing manifest: {unrouted}")

  updates = []
  for path in agent_paths:
    original, rewritten = _rewritten_content(path)
    if rewritten != original:
      try:
        mode = stat.S_IMODE(path.stat().st_mode)
      except OSError as error:
        raise RoutingError(f"cannot read mode for agent {path.name}: {error}") from error
      updates.append((path, rewritten, mode))

  staged = []
  for path, content, mode in updates:
    try:
      with tempfile.NamedTemporaryFile("wb", dir=path.parent, prefix=f".{path.name}.", delete=False) as temporary:
        temporary_path = Path(temporary.name)
        staged.append((path, temporary_path))
        temporary.write(content)
        temporary.flush()
        os.fsync(temporary.fileno())
        os.chmod(temporary_path, mode)
    except OSError as error:
      cleanup_error = _cleanup_staged(staged)
      detail = f"; cleanup failed: {cleanup_error}" if cleanup_error else ""
      raise RoutingError(f"cannot stage agent {path.name}: {error}{detail}") from error

  for path, temporary in staged:
    try:
      os.replace(temporary, path)
    except OSError as error:
      cleanup_error = _cleanup_staged(staged)
      detail = f"; cleanup failed: {cleanup_error}" if cleanup_error else ""
      raise RoutingError(f"cannot replace agent {path.name}: {error}{detail}") from error
  return len(updates)


def apply_routing(agents_dir: Path, routing_path: Path) -> None:
  _apply_routing(agents_dir, routing_path)


def main() -> int:
  base = Path(__file__).parent
  parser = argparse.ArgumentParser(description="Strip provider-specific models from OpenCode agent frontmatter.")
  parser.add_argument("--agents", type=Path, default=base / "agents")
  parser.add_argument("--routing", type=Path, default=base / "agent-routing.json")
  args = parser.parse_args()

  try:
    updated = _apply_routing(args.agents, args.routing)
  except RoutingError as error:
    print(f"error: {error}", file=sys.stderr)
    return 1

  print(f"updated {updated} agent files")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
