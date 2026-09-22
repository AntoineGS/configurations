"""Daily HA review: validate results, persist progress, and deliver notifications."""

import json
import os
from pathlib import Path
import tempfile
import argparse
from datetime import datetime, timedelta, timezone
import fcntl
import signal
import sys
import time
import uuid
from zoneinfo import ZoneInfo

from clients import ClientError, HAClient, OpenCodeClient, retry

TORONTO = ZoneInfo("America/Toronto")


def validate_result(value: object) -> dict:
    keys = {"status", "coverage", "findings", "report_markdown", "notification"}
    if not isinstance(value, dict) or set(value) != keys:
        raise ValueError("invalid result fields")
    if value["status"] not in ("complete", "partial", "failed"):
        raise ValueError("invalid review status")
    for field in ("coverage", "report_markdown"):
        if not isinstance(value[field], str) or not value[field].strip():
            raise ValueError(f"missing {field}")
    if len(value["report_markdown"].encode()) > 102400 or len(value["coverage"]) > 10000:
        raise ValueError("report too large")
    findings = value["findings"]
    if not isinstance(findings, list) or len(findings) > 20:
        raise ValueError("invalid findings")
    for finding in findings:
        if not isinstance(finding, dict) or set(finding) != {"severity", "title", "evidence", "recommendation"}:
            raise ValueError("invalid finding fields")
        if any(not isinstance(text, str) or not text.strip() or len(text) > 10000 for text in finding.values()):
            raise ValueError("invalid finding text")
        if finding["severity"] not in ("critical", "warning", "improvement"):
            raise ValueError("invalid severity")
    notification = value["notification"]
    if not isinstance(notification, str) or len(notification) > 500:
        raise ValueError("invalid notification")
    if bool(notification.strip()) != bool(findings):
        raise ValueError("notification does not match findings")
    return value


def atomic_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory_fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def atomic_json(path: Path, value: dict) -> None:
    atomic_text(path, json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def publish_report(root: Path, run_id: str, session_id: str, result: dict, start: str, end: str) -> Path:
    path = root / "reports" / f"{run_id}.md"
    if not path.exists():
        text = (f"# Home Assistant review — {end}\n\n"
                f"- Status: **{result['status'].upper()}**\n"
                f"- Requested window: {start} → {end}\n"
                f"- Coverage: {result['coverage']}\n"
                f"- OpenCode session: `{session_id}`\n\n")
        if result["status"] == "partial":
            text += "> Incomplete log coverage: this report is not an all-clear.\n\n"
        atomic_text(path, text + result["report_markdown"] + "\n")
    return path


def local_now():
    return datetime.now(TORONTO)


def scheduled_slot(now):
    # Before 08:00, catch up yesterday's schedule; today's run is still due later.
    return (now.date() if now.hour >= 8 else (now - timedelta(days=1)).date()).isoformat()


def save_state(directory, state):
    atomic_json(directory / "current.json", state)
    atomic_json(directory / f"{state['run_id']}.json", state)


def failure_category(error):
    if isinstance(error, ClientError):
        return str(error)
    if isinstance(error, ValueError):
        return "invalid_review_result"
    if isinstance(error, InterruptedError):
        return "run_interrupted"
    if isinstance(error, OSError):
        return "local_io_failure"
    return "unexpected_failure"


def finish_run(root, directory, state, opencode, ha, settings, deadline):
    session_path = directory / (state["run_id"] + ".session.json")
    try:
        if state["phase"] in ("review_pending", "reviewing"):
            ha.preflight(settings["notify_service"], deadline)
            retry(lambda: opencode.preflight(deadline), deadline)
            state["phase"] = "reviewing"
            save_state(directory, state)
            prompt = (f"Perform the approved daily Home Assistant review. Requested window: "
                      f"{state['start']} through {state['end']}. Return only the JSON contract "
                      "defined in your agent instructions. Do not delegate or ask questions.")
            session_id, value = opencode.review(prompt, session_path, deadline)
            value = validate_result(value)
            token = getattr(ha, "token", None)
            if token and token in json.dumps(value):
                raise ClientError("sensitive_output_rejected")
            state.update(session_id=session_id, result=value)
            if value["status"] == "failed":
                raise ClientError("diagnostic_review_failed")
            state["phase"] = "review_complete"
            save_state(directory, state)

        if state["phase"] == "review_complete":
            value = validate_result(state["result"])
            report = publish_report(root, state["run_id"], state["session_id"], value, state["start"], state["end"])
            state["report"] = str(report)
            state["phase"] = "notification_pending" if value["findings"] else "complete"
            save_state(directory, state)
            print(f"Report saved: {report}", flush=True)

        if state["phase"] == "notification_pending":
            message = state["result"]["notification"] + "\nReport: " + Path(state["report"]).name
            ha.notify(settings["notify_service"], "Home Assistant daily review", message,
                      "ha-review-" + state["run_id"], deadline)
            state["phase"] = "notified"
            state.pop("last_error", None)
            save_state(directory, state)
            print("Phone notification delivered.", flush=True)
        return 0
    except Exception as error:
        state["last_error"] = failure_category(error)
        if state["phase"] not in ("notification_pending", "review_complete"):
            state["phase"] = "failed"
        if session_path.exists():
            state["session_id"] = json.loads(session_path.read_text())["session_id"]
        save_state(directory, state)
        print(f"Review job failed: {state['last_error']} (run {state['run_id']})", file=sys.stderr, flush=True)
        return 1


def run_once(root: Path, opencode, ha, settings: dict) -> int:
    directory = root / ".review-state"
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    directory.chmod(0o700)
    deadline = time.monotonic() + 900
    with (directory / "run.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("Another review is already running.", flush=True)
            return 0
        now = local_now()
        slot = scheduled_slot(now)
        current = directory / "current.json"
        state = json.loads(current.read_text()) if current.exists() else None
        if state and state["phase"] not in ("complete", "notified", "failed"):
            if finish_run(root, directory, state, opencode, ha, settings, deadline):
                return 1
        if state and state["slot"] >= slot:
            if state["phase"] != "failed":
                print(f"Scheduled review for {slot} is already complete.", flush=True)
                return 0
            if not settings.get("retry_failed", False):
                print("Today's review failed; inspect diagnostics or use --retry-failed.", file=sys.stderr)
                return 1
        state = {
            "run_id": now.strftime("%Y-%m-%d_%H%M%S-") + uuid.uuid4().hex[:8],
            "slot": slot, "phase": "review_pending",
            "start": (now.astimezone(timezone.utc) - timedelta(hours=24)).astimezone(TORONTO).isoformat(),
            "end": now.isoformat(),
        }
        save_state(directory, state)
        return finish_run(root, directory, state, opencode, ha, settings, deadline)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("run", "list-targets", "test-notification"))
    parser.add_argument("--project", type=Path, default=Path.home() / "gits/home-assistant")
    parser.add_argument("--retry-failed", action="store_true", help="Explicitly retry a failed review for this schedule")
    args = parser.parse_args(argv)
    os.umask(0o077)

    def interrupted(signum, frame):
        raise InterruptedError("terminated")

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        ha = HAClient()
        deadline = time.monotonic() + 180
        if args.command == "list-targets":
            print("\n".join(ha.services(deadline)))
            return 0
        settings = json.loads((args.project / ".review-config.json").read_text())
        if Path(settings["project"]).expanduser().resolve() != args.project.resolve():
            raise ValueError("project mismatch")
        if args.command == "test-notification":
            ha.notify(settings["notify_service"], "Home Assistant review — setup test",
                      "Daily Astra reviews are being configured for 08:00 Toronto. This is a setup test.",
                      "ha-review-setup-test", deadline)
            print("Setup notification delivered.")
            return 0
        settings["retry_failed"] = args.retry_failed
        return run_once(args.project, OpenCodeClient(args.project, settings.get("opencode", "/usr/bin/opencode")),
                        ha, settings)
    except Exception as error:
        print(f"Review job failed: {failure_category(error)}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
