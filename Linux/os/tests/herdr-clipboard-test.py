#!/usr/bin/env python3
"""Regression checks for switching clipboard sources in SSH-started Herdr panes."""

import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import unittest


HELPERS = Path(__file__).resolve().parents[1] / "helpers"


class ClipboardSelectionTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="herdr-clipboard-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.local = self.root / "wayland-local"
        self.remote = self.root / "waypipe-remote"
        for path in (self.local, self.remote):
            connection = socket.socket(socket.AF_UNIX)
            self.addCleanup(connection.close)
            connection.bind(str(path))
        self.state = self.root / "state" / "waypipe.env"
        self.desktop = self.root / "desktop.json"
        self.desktop.write_text(json.dumps({
            "WAYLAND_DISPLAY": str(self.local),
            "XDG_RUNTIME_DIR": str(self.root),
            "DISPLAY": ":0",
        }))
        binary = self.root / "bin"
        binary.mkdir()
        systemctl = binary / "systemctl"
        systemctl.write_text('#!/bin/sh\ncat "$TEST_DESKTOP_ENV"\n')
        systemctl.chmod(0o755)
        self.env = {
            **os.environ,
            "PATH": f"{binary}:{HELPERS}:{os.environ['PATH']}",
            "TEST_DESKTOP_ENV": str(self.desktop),
            "HERDR_WAYPIPE_ENV_FILE": str(self.state),
            "HERDR_ENV": "",
            "SSH_CONNECTION": "test SSH connection",
            "WAYLAND_DISPLAY": str(self.remote),
            "XDG_RUNTIME_DIR": str(self.root),
            "DISPLAY": "",
        }

    def run_helper(self, mode, **environment):
        return subprocess.run(
            ["bash", str(HELPERS / "herdr-clipboard"), mode],
            env={**self.env, **environment}, capture_output=True, text=True,
        )

    def selected(self):
        result = subprocess.run(
            [str(HELPERS / "herdr-waypipe-env"), "read"],
            env=self.env, capture_output=True, text=True, check=True,
        )
        return dict(line.split("=", 1) for line in result.stdout.splitlines())

    def test_local_ignores_ssh_and_stale_pane_environment(self):
        result = self.run_helper(
            "local", HERDR_ENV="1", WAYLAND_DISPLAY="",
            PATH=f"{self.root / 'bin'}:/usr/bin:/bin",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.selected()["WAYLAND_DISPLAY"], str(self.local))
        self.assertEqual(self.selected()["DISPLAY"], ":0")

    def test_remote_replaces_local_selection_with_forwarded_socket(self):
        self.assertEqual(self.run_helper("local").returncode, 0)
        result = self.run_helper("remote")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.selected()["WAYLAND_DISPLAY"], str(self.remote))
        self.assertEqual(self.selected()["DISPLAY"], "")

    def test_invalid_remote_preserves_working_selection(self):
        self.assertEqual(self.run_helper("local").returncode, 0)
        before = self.state.read_bytes()
        for environment in (
            {"WAYLAND_DISPLAY": ""},
            {"WAYLAND_DISPLAY": str(self.root / "missing")},
            {"WAYLAND_DISPLAY": str(self.local)},
            {"HERDR_ENV": "1"},
        ):
            with self.subTest(environment=environment):
                self.assertNotEqual(self.run_helper("remote", **environment).returncode, 0)
                self.assertEqual(self.state.read_bytes(), before)

    def test_missing_desktop_preserves_remote_selection(self):
        self.assertEqual(self.run_helper("remote").returncode, 0)
        before = self.state.read_bytes()
        self.desktop.write_text("{}")
        self.assertNotEqual(self.run_helper("local").returncode, 0)
        self.assertEqual(self.state.read_bytes(), before)

    def test_status_detects_disconnected_source_without_changing_it(self):
        self.assertEqual(self.run_helper("remote").returncode, 0)
        before = self.state.read_bytes()
        result = self.run_helper("status")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(str(self.remote), result.stdout)
        self.remote.unlink()
        self.assertNotEqual(self.run_helper("status").returncode, 0)
        self.assertEqual(self.state.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
