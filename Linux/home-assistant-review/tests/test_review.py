import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from review import atomic_json, publish_report, validate_result, run_once
from clients import ClientError, OpenCodeClient, final_result, retry, HAClient
import subprocess
import time
import fcntl
from datetime import datetime
from zoneinfo import ZoneInfo


def result(actionable=False, status="complete"):
    return {
        "status": status,
        "coverage": "Only the last two hours were retained." if status == "partial" else "24 hours available.",
        "findings": ([{
            "severity": "warning", "title": "Reconnects",
            "evidence": "12 warnings at 07:00", "recommendation": "Check network reachability."
        }] if actionable else []),
        "report_markdown": "## Findings\nRepeated reconnects." if actionable else "No issues found in available logs.",
        "notification": "HA review: repeated reconnects." if actionable else "",
    }


class ReportsTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def test_actionable_result_requires_notification(self):
        value = result(True)
        value["notification"] = ""
        with self.assertRaises(ValueError):
            validate_result(value)

    def test_rejects_untrustworthy_result_shapes(self):
        bad_values = [None, [], True, {**result(), "extra": "unexpected"}]
        for field, value in [("status", "healthy"), ("coverage", ""), ("findings", True),
                             ("notification", "x"), ("report_markdown", "x" * 102401)]:
            bad_values.append({**result(), field: value})
        for value in bad_values:
            with self.subTest(value=str(value)[:100]), self.assertRaises(ValueError):
                validate_result(value)

    def test_atomic_write_preserves_previous_state_on_replace_failure(self):
        path = self.root / "state.json"
        path.write_text('{"phase":"review_complete"}')
        with patch("review.os.replace", side_effect=OSError("disk failure")):
            with self.assertRaises(OSError):
                atomic_json(path, {"phase": "notified"})
        self.assertEqual(json.loads(path.read_text())["phase"], "review_complete")
        self.assertEqual(list(self.root.iterdir()), [path])

    def test_partial_report_discloses_gap_outside_model_text(self):
        value = validate_result(result(status="partial"))
        path = publish_report(self.root, "2026-09-22_080000-abc123", "ses_test", value,
                              "2026-09-21T08:00:00-04:00", "2026-09-22T08:00:00-04:00")
        text = path.read_text()
        self.assertIn("PARTIAL", text)
        self.assertIn("Only the last two hours were retained.", text)
        self.assertIn("ses_test", text)


def assistant(value=None):
    return {
        "id": "msg_test", "type": "assistant", "agent": "daily-ha-review",
        "model": {"providerID": "openai", "id": "gpt-6-astra", "variant": "medium"},
        "time": {"created": 1, "completed": 2}, "finish": "stop",
        "content": [{"type": "text", "text": json.dumps(value or result())}],
    }


class OpenCodeTest(unittest.TestCase):
    def test_final_response_excludes_earlier_commentary(self):
        commentary = assistant()
        commentary["finish"] = "tool-calls"
        commentary["content"] = [{"type": "text", "text": "Investigating..."}]
        self.assertEqual(final_result([commentary, assistant()]), result())

    def test_rejects_incomplete_wrong_model_and_malformed_results(self):
        bad = []
        for field, value in [("finish", "tool-calls"), ("finish", "length"),
                             ("time", {"created": 1}), ("agent", "build"),
                             ("model", {"providerID": "openai", "id": "other"}),
                             ("error", {"message": "failed"}),
                             ("content", [{"type": "text", "text": "not JSON"}])]:
            bad.append({**assistant(), field: value})
        for message in bad:
            with self.subTest(message=message), self.assertRaises(ClientError):
                final_result([message])

    def test_timeout_preserves_session_for_recovery_and_interrupts_server(self):
        with tempfile.TemporaryDirectory() as tmp:
            client = OpenCodeClient(Path(tmp))
            session_path = Path(tmp) / "session.json"
            paths = []

            def transport(method, path, payload=None, timeout=30):
                paths.append(path)
                if path == "/api/session":
                    return {"data": {"id": "ses_timeout"}}
                if path.endswith("/prompt"):
                    self.assertEqual(json.loads(session_path.read_text())["session_id"], "ses_timeout")
                    return {"data": {"id": "msg_input"}}
                if path.endswith("/wait"):
                    raise subprocess.TimeoutExpired("opencode", 1)

            with patch.object(client, "api", side_effect=transport), self.assertRaises(ClientError):
                client.review("Review", session_path, time.monotonic() + 60)
            self.assertIn("/api/session/ses_timeout/interrupt", paths)
            self.assertEqual(json.loads(session_path.read_text())["session_id"], "ses_timeout")


class FakeOpenCode:
    def __init__(self, value):
        self.value = value
        self.review_calls = 0
        self.recovered = False

    def preflight(self, deadline):
        pass

    def review(self, prompt, session_path, deadline):
        self.review_calls += 1
        self.recovered = session_path.exists()
        atomic_json(session_path, {"session_id": "ses_fake"})
        return "ses_fake", copy.deepcopy(self.value)


class FakeHA:
    def __init__(self, root, error=None):
        self.root = root
        self.error = error
        self.deliveries = []

    def preflight(self, service, deadline):
        pass

    def notify(self, service, title, message, tag, deadline):
        state = json.loads((self.root / ".review-state/current.json").read_text())
        if state["phase"] != "notification_pending" or not Path(state["report"]).is_file():
            raise AssertionError("notification attempted before durable report/state")
        if self.error:
            raise self.error
        self.deliveries.append((service, message, tag))


class OrchestrationTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.settings = {"notify_service": "notify.mobile_app_phone_antoine"}
        self.now = datetime(2026, 9, 22, 9, tzinfo=ZoneInfo("America/Toronto"))
        self.time_patch = patch("review.local_now", return_value=self.now)
        self.time_patch.start()
        self.addCleanup(self.time_patch.stop)

    def state(self):
        return json.loads((self.root / ".review-state/current.json").read_text())

    def test_quiet_report_is_saved_and_same_day_is_not_reviewed_twice(self):
        client, ha = FakeOpenCode(result()), FakeHA(self.root)
        self.assertEqual(run_once(self.root, client, ha, self.settings), 0)
        self.assertEqual(len(list((self.root / "reports").glob("*.md"))), 1)
        self.assertEqual(run_once(self.root, client, ha, self.settings), 0)
        self.assertEqual(client.review_calls, 1)
        self.assertEqual(ha.deliveries, [])

    def test_failed_delivery_reuses_report_after_process_restart(self):
        client = FakeOpenCode(result(True))
        bad_ha = FakeHA(self.root, ClientError("ha_delivery_failure"))
        self.assertEqual(run_once(self.root, client, bad_ha, self.settings), 1)
        first = self.state()
        self.assertEqual(first["phase"], "notification_pending")
        good_ha = FakeHA(self.root)
        self.assertEqual(run_once(self.root, client, good_ha, self.settings), 0)
        self.assertEqual(client.review_calls, 1)
        self.assertEqual(self.state()["phase"], "notified")
        self.assertEqual(self.state()["run_id"], first["run_id"])
        self.assertIn(Path(first["report"]).name, good_ha.deliveries[0][1])

    def test_failed_or_malformed_review_cannot_publish_or_notify(self):
        for value in [result(status="failed"), {"unexpected": "text"}]:
            with self.subTest(value=value), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                client, ha = FakeOpenCode(value), FakeHA(root)
                self.assertEqual(run_once(root, client, ha, self.settings), 1)
                self.assertEqual(list(root.glob("reports/*.md")), [])
                self.assertEqual(ha.deliveries, [])
                self.assertEqual(run_once(root, client, ha, self.settings), 1)
                self.assertEqual(client.review_calls, 1)

    def test_locked_job_does_not_start_another_review(self):
        state_dir = self.root / ".review-state"
        state_dir.mkdir()
        with (state_dir / "run.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            client = FakeOpenCode(result())
            self.assertEqual(run_once(self.root, client, FakeHA(self.root), self.settings), 0)
            self.assertEqual(client.review_calls, 0)

    def test_orphaned_run_reuses_persisted_session(self):
        state = {"run_id": "2026-09-22_080000-abc123", "slot": "2026-09-22", "phase": "reviewing",
                 "start": "2026-09-21T08:00:00-04:00", "end": "2026-09-22T08:00:00-04:00"}
        atomic_json(self.root / ".review-state/current.json", state)
        atomic_json(self.root / ".review-state" / (state["run_id"] + ".session.json"),
                    {"session_id": "ses_previous"})
        client = FakeOpenCode(result())
        self.assertEqual(run_once(self.root, client, FakeHA(self.root), self.settings), 0)
        self.assertTrue(client.recovered)
        self.assertEqual(self.state()["run_id"], state["run_id"])

    def test_old_delivery_does_not_suppress_todays_review(self):
        client = FakeOpenCode(result(True))
        self.assertEqual(run_once(self.root, client, FakeHA(self.root, ClientError("offline")), self.settings), 1)
        with patch("review.local_now", return_value=self.now.replace(day=23)):
            ha = FakeHA(self.root)
            self.assertEqual(run_once(self.root, client, ha, self.settings), 0)
        self.assertEqual(client.review_calls, 2)
        self.assertEqual(len(ha.deliveries), 2)

    def test_requested_window_is_24_elapsed_hours_across_dst(self):
        after_fallback = datetime(2026, 11, 1, 9, tzinfo=ZoneInfo("America/Toronto"))
        with patch("review.local_now", return_value=after_fallback):
            self.assertEqual(run_once(self.root, FakeOpenCode(result()), FakeHA(self.root), self.settings), 0)
        state = self.state()
        elapsed = datetime.fromisoformat(state["end"]) - datetime.fromisoformat(state["start"])
        self.assertEqual(elapsed.total_seconds(), 86400)

    def test_echoed_credential_is_not_persisted_or_sent(self):
        value = result(True)
        value["report_markdown"] = "Accidentally echoed private-test-token"
        ha = FakeHA(self.root)
        ha.token = "private-test-token"
        self.assertEqual(run_once(self.root, FakeOpenCode(value), ha, self.settings), 1)
        self.assertEqual(list(self.root.glob("reports/*.md")), [])
        self.assertNotIn("private-test-token", (self.root / ".review-state/current.json").read_text())
        self.assertEqual(ha.deliveries, [])


class RetryTest(unittest.TestCase):
    def test_transient_failures_have_bounded_attempts(self):
        attempts = []
        def operation():
            attempts.append(1)
            raise ClientError("offline", transient=True)
        with patch("clients.time.sleep"), self.assertRaises(ClientError):
            retry(operation, time.monotonic() + 300)
        self.assertEqual(len(attempts), 3)

    def test_permanent_failure_is_not_retried(self):
        attempts = []
        def operation():
            attempts.append(1)
            raise ClientError("unauthorized")
        with self.assertRaises(ClientError):
            retry(operation, time.monotonic() + 300)
        self.assertEqual(len(attempts), 1)


if __name__ == "__main__":
    unittest.main()
