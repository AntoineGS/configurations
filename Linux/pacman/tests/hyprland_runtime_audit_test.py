#!/usr/bin/env python3
"""Unit tests for the fail-closed Hyprland runtime audit."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))

from hyprland_runtime_audit import (  # noqa: E402
    AuditError,
    audit_commands,
    audit_sources,
    extract_exec_commands,
    parse_manifest_packages,
)


class HyprlandRuntimeAuditTests(unittest.TestCase):
    manifest = ROOT / "tidydots.yaml"
    active_sources = (
        ROOT / "Linux/hypr/bindings/apps.lua",
        ROOT / "Linux/hypr/autostart.lua",
    )

    def write_fixture(self, source: str) -> tuple[tempfile.TemporaryDirectory[str], Path]:
        temporary_directory = tempfile.TemporaryDirectory()
        path = Path(temporary_directory.name) / "fixture.lua"
        path.write_text(source, encoding="utf-8")
        return temporary_directory, path

    def test_current_inventory_and_package_ownership_are_exact(self) -> None:
        commands = audit_sources(self.manifest, self.active_sources)

        self.assertEqual(len(commands), 26)
        self.assertEqual(sum(command.source.name == "apps.lua" for command in commands), 12)
        self.assertEqual(sum(command.source.name == "autostart.lua" for command in commands), 14)

    def test_multiline_quoted_string_handles_escaped_quotes(self) -> None:
        temporary_directory, path = self.write_fixture(
            'hl.exec_cmd(\n  "signal-desktop --label \\"quoted\\""\n)\n'
        )
        self.addCleanup(temporary_directory.cleanup)

        commands = extract_exec_commands(path)

        self.assertEqual([command.text for command in commands], ['signal-desktop --label "quoted"'])

    def test_multiline_long_string_preserves_newlines(self) -> None:
        temporary_directory, path = self.write_fixture("hl.exec_cmd(\n  [[sleep 1 &&\nhyprctl eval status]]\n)\n")
        self.addCleanup(temporary_directory.cleanup)

        commands = extract_exec_commands(path)

        self.assertEqual([command.text for command in commands], ["sleep 1 &&\nhyprctl eval status"])

    def test_current_multiline_system_chains_are_allowlisted(self) -> None:
        packages = parse_manifest_packages(self.manifest)
        commands = [
            command
            for source in self.active_sources
            for command in extract_exec_commands(source)
            if command.text.startswith("sleep ")
        ]

        self.assertEqual(len(commands), 2)
        audit_commands(commands, packages)

    def test_unsupported_full_commands_fail_closed(self) -> None:
        cases = (
            'hl.exec_cmd(\n  "uwsm-app -- synthetic-quoted-launcher"\n)\n',
            "hl.exec_cmd(\n  [[sleep 1 && synthetic-chain-launcher]]\n)\n",
            "hl.exec_cmd(\n  [[sleep 1 || synthetic-chain-launcher]]\n)\n",
            "hl.exec_cmd(\n  [[sleep 1; synthetic-chain-launcher]]\n)\n",
            "hl.exec_cmd(\n  [[systemctl --user is-active | synthetic-chain-launcher]]\n)\n",
            "hl.exec_cmd(\n  [[uwsm-app -- env FOO=bar xdg-terminal-exec synthetic-launcher]]\n)\n",
            "hl.exec_cmd(\n  [[systemctl --user $(synthetic-command)]]\n)\n",
            "hl.exec_cmd(\n  [[sleep 1 &&\nsynthetic-newline-launcher]]\n)\n",
            'hl.exec_cmd(\n  "signal-desktop --label \\"escaped\\""\n)\n',
        )
        packages = parse_manifest_packages(self.manifest)

        for source in cases:
            with self.subTest(source=source):
                temporary_directory, path = self.write_fixture(source)
                self.addCleanup(temporary_directory.cleanup)

                with self.assertRaises(AuditError):
                    audit_commands(extract_exec_commands(path), packages)


if __name__ == "__main__":
    unittest.main()
