#!/usr/bin/env python3
"""Regressions for window-scoped ownership of the Office PC SSH tunnel."""

import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "rustdesk-office"
HANDOFF = SCRIPT.parent.parent / "hypr/rustdesk-focus-handoff.sh"


def wait_for(predicate, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    raise AssertionError("condition did not become true before timeout")


class OfficeSessionTest(unittest.TestCase):
    def test_connected_window_with_remote_hostname_is_recognized(self):
        with tempfile.TemporaryDirectory(prefix="office-title-") as directory:
            root = Path(directory)
            hyprctl = root / "hyprctl"
            hyprctl.write_text('#!/bin/sh\ncat "$CLIENTS"\n')
            hyprctl.chmod(0o755)
            clients = root / "clients.json"
            clients.write_text(json.dumps([
                {"address": "0x111", "class": "rustdesk", "title": "127.0.0.1:211200@other - Remote Desktop - RustDesk"},
                {"address": "0x123", "class": "rustdesk", "title": "127.0.0.1:21120@antoinews-linux - Remote Desktop - RustDesk"},
            ]))
            result = subprocess.run(
                ["bash", "-ec", 'source "$SCRIPT"; office_window'],
                env=dict(os.environ, SCRIPT=str(SCRIPT), PATH=f"{root}:{os.environ['PATH']}", CLIENTS=str(clients)),
                capture_output=True, text=True, check=True,
            )
            self.assertEqual(result.stdout.strip(), "0x123")

    def test_handoff_only_moves_focus_from_the_office_session(self):
        # A callback must not change focus while another RustDesk session is active.
        with tempfile.TemporaryDirectory(prefix="office-handoff-") as directory:
            root = Path(directory)
            active = root / "active.json"
            actions = root / "actions"
            hyprctl = root / "hyprctl"
            hyprctl.write_text('''#!/bin/sh
case "$1" in
  activewindow) cat "$ACTIVE" ;;
  eval) printf '%s\\n' "$2" >> "$ACTIONS" ;;
  *) exit 2 ;;
esac
''')
            hyprctl.chmod(0o755)
            environment = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}",
                               ACTIVE=str(active), ACTIONS=str(actions))
            for title, should_focus in [
                ("another - Remote Desktop - RustDesk", False),
                ("RustDesk", False),
                ("127.0.0.1:21120 - Remote Desktop - RustDesk", True),
                ("127.0.0.1:21120@antoinews-linux - Remote Desktop - RustDesk", True),
            ]:
                with self.subTest(title=title):
                    actions.unlink(missing_ok=True)
                    active.write_text(json.dumps({"address": "0x123", "class": "rustdesk", "title": title}))
                    subprocess.run(["bash", str(HANDOFF), "receive"], input="focus-left\n",
                                   env=environment, text=True, check=True)
                    self.assertEqual(actions.exists(), should_focus)

    def test_signal_cleans_owned_children_but_not_other_sessions(self):
        # A broad pkill, a missing trap, or inherited ownership would break this.
        with tempfile.TemporaryDirectory(prefix="office-session-") as directory:
            root = Path(directory)
            script = '''
set -e
source "$SCRIPT"
run_dir=$(mktemp -d "$ROOT/session.XXXXXX")
trap cleanup EXIT
trap 'exit 143' TERM
sleep 60 & ssh_pid=$!
sleep 60 & listener_pid=$!
printf '%s %s %s\n' "$ssh_pid" "$listener_pid" "$run_dir" > "$ROOT/children"
while :; do sleep 0.1; done
'''
            unrelated = subprocess.Popen(["sleep", "60"])
            process = subprocess.Popen(
                ["bash", "-c", script],
                env=dict(os.environ, SCRIPT=str(SCRIPT), ROOT=str(root)),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
            )
            children = []
            try:
                wait_for(lambda: (root / "children").exists() or process.poll() is not None)
                self.assertIsNone(process.poll(), "launcher must expose its session cleanup")
                ssh_pid, listener_pid, runtime = (root / "children").read_text().split()
                children = [int(ssh_pid), int(listener_pid)]
                process.terminate()
                _, stderr = process.communicate(timeout=5)
                self.assertEqual(process.returncode, 143, stderr)
                self.assertFalse(Path(runtime).exists())
                for pid in children:
                    self.assertFalse(Path(f"/proc/{pid}").exists(), f"owned child {pid} survived")
                self.assertIsNone(unrelated.poll(), "another session was terminated")
            finally:
                if process.poll() is None:
                    process.kill()
                process.communicate()
                for pid in children:
                    try:
                        os.kill(pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                unrelated.terminate()
                unrelated.wait()

    def test_window_close_ends_session_while_shared_rustdesk_process_lives(self):
        # Waiting for RustDesk's PID instead of the selected window leaks tunnels.
        with tempfile.TemporaryDirectory(prefix="office-window-") as directory:
            root = Path(directory)
            clients = root / "clients.json"
            target = {"address": "0x123", "class": "rustdesk", "title": "127.0.0.1:21120 - Remote Desktop - RustDesk"}
            other = {"address": "0x456", "class": "rustdesk", "title": "another - Remote Desktop - RustDesk"}

            def set_windows(windows):
                pending = root / "pending.json"
                pending.write_text(json.dumps(windows))
                pending.replace(clients)

            set_windows([target, other])
            hyprctl = root / "hyprctl"
            hyprctl.write_text('#!/bin/sh\ncat "$CLIENTS"\n')
            hyprctl.chmod(0o755)
            shared_rustdesk = subprocess.Popen(["sleep", "60"])
            process = subprocess.Popen(
                ["bash", "-ec", 'source "$SCRIPT"; ssh_pid=$SHARED_PID; listener_pid=$SHARED_PID; touch "$READY"; watch_window 0x123'],
                env=dict(os.environ, SCRIPT=str(SCRIPT), PATH=f"{root}:{os.environ['PATH']}",
                         CLIENTS=str(clients), SHARED_PID=str(shared_rustdesk.pid), READY=str(root / "ready")),
                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
            )
            try:
                wait_for(lambda: (root / "ready").exists() or process.poll() is not None)
                self.assertIsNone(process.poll(), "window watcher must start")
                set_windows([target])
                time.sleep(0.7)
                self.assertIsNone(process.poll(), "closing a different window ended this session")
                set_windows([])
                _, stderr = process.communicate(timeout=5)
                self.assertEqual(process.returncode, 0, stderr)
                self.assertIsNone(shared_rustdesk.poll(), "shared RustDesk process was killed")
            finally:
                if process.poll() is None:
                    process.kill()
                process.communicate()
                shared_rustdesk.terminate()
                shared_rustdesk.wait()


if __name__ == "__main__":
    unittest.main()
