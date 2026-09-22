"""Bounded OpenCode and Home Assistant transports. Never log credentials."""

import json
from pathlib import Path
import re
import socket
import subprocess
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

MODEL = {"providerID": "openai", "id": "gpt-6-astra", "variant": "medium"}
AGENT = "daily-ha-review"
DIAGNOSTICS = (
    "ha_get_logs", "ha_get_system_health", "ha_get_automation_traces", "ha_get_state", "ha_search",
)
PERMISSIONS = [{"action": "*", "resource": "*", "effect": "deny"}] + [
    {"action": action, "resource": "*", "effect": "allow"}
    for action in ("execute", *(f"home-assistant_{tool}" for tool in DIAGNOSTICS))
]


class ClientError(Exception):
    """A sanitized failure category, safe to persist or log."""

    def __init__(self, category, transient=False):
        super().__init__(category)
        self.transient = transient


def remaining(deadline):
    seconds = deadline - time.monotonic()
    if seconds <= 0:
        raise ClientError("deadline_exceeded")
    return seconds


def retry(operation, deadline):
    for delay in (0, 30, 120):
        if delay:
            if remaining(deadline) <= delay:
                raise ClientError("deadline_exceeded")
            time.sleep(delay)
        remaining(deadline)
        try:
            return operation()
        except ClientError as error:
            if not error.transient or delay == 120:
                raise


class HAClient:
    def __init__(self):
        try:
            config = json.loads((Path.home() / ".claude.json").read_text())
            self.token = config["mcpServers"]["home-assistant"]["env"]["HOMEASSISTANT_TOKEN"]
            if not isinstance(self.token, str) or not self.token.strip():
                raise ValueError("empty token")
        except (OSError, ValueError, KeyError, TypeError):
            raise ClientError("ha_credentials_unavailable") from None

    def request(self, path, deadline, payload=None):
        def operation():
            request = Request("https://ha.antoinedev.io/api/" + path,
                              data=json.dumps(payload).encode() if payload is not None else None,
                              headers={"Authorization": "Bearer " + self.token,
                                       "Content-Type": "application/json"})
            try:
                with urlopen(request, timeout=min(30, remaining(deadline))) as response:
                    return json.load(response)
            except HTTPError as error:
                raise ClientError(f"ha_http_{error.code}", transient=error.code == 429 or error.code >= 500) from None
            except (URLError, TimeoutError, socket.timeout, ConnectionError):
                raise ClientError("ha_connection_failure", transient=True) from None
            except ValueError:
                raise ClientError("ha_invalid_response") from None
        return retry(operation, deadline)

    def services(self, deadline):
        data = self.request("services", deadline)
        return sorted(f"notify.{name}" for item in data if item["domain"] == "notify"
                      for name in item["services"] if name.startswith("mobile_app_"))

    def preflight(self, service, deadline):
        if service not in self.services(deadline):
            raise ClientError("notification_target_unavailable")

    def notify(self, service, title, message, tag, deadline):
        if not re.fullmatch(r"notify\.mobile_app_[a-z0-9_]+", service):
            raise ClientError("invalid_notification_target")
        self.request("services/notify/" + service.removeprefix("notify."), deadline,
                     {"title": title, "message": message, "data": {"tag": tag}})


def final_result(context):
    messages = [message for message in context if message.get("type") == "assistant"]
    if not messages:
        raise ClientError("missing_final_response")
    message = messages[-1]
    if (message.get("finish") != "stop" or message.get("error")
            or not message.get("time", {}).get("completed")
            or message.get("agent") != AGENT or message.get("model") != MODEL):
        raise ClientError("incomplete_or_wrong_model_response")
    text = "".join(part["text"] for part in message.get("content", []) if part.get("type") == "text")
    if len(text.encode()) > 400000:
        raise ClientError("response_too_large")
    try:
        return json.loads(text)
    except (ValueError, TypeError):
        raise ClientError("invalid_result_json") from None


class OpenCodeClient:
    def __init__(self, project: Path, executable="/usr/bin/opencode"):
        self.project = project
        self.executable = executable

    def api(self, method, path, payload=None, timeout=30):
        command = [self.executable, "api", method, path]
        if payload is not None:
            command += ["--data", json.dumps(payload)]
        try:
            completed = subprocess.run(command, cwd=self.project, text=True, capture_output=True,
                                       timeout=timeout, check=True)
        except subprocess.TimeoutExpired:
            raise ClientError("opencode_timeout", transient=True) from None
        except subprocess.CalledProcessError as exc:
            output = (exc.stdout or "") + (exc.stderr or "")
            transient = any(code in output for code in ("HTTP 429", "HTTP 502", "HTTP 503", "HTTP 504"))
            raise ClientError("opencode_api_failure", transient=transient) from None
        except OSError:
            raise ClientError("opencode_unavailable", transient=True) from None
        try:
            return json.loads(completed.stdout) if completed.stdout.strip() else None
        except ValueError:
            raise ClientError("opencode_invalid_api_response") from None

    def preflight(self, deadline):
        query = urlencode({"location[directory]": str(self.project)})
        servers = self.api("get", f"/api/mcp?{query}", timeout=min(45, remaining(deadline)))["data"]
        if not any(s["name"] == "home-assistant" and s.get("status", {}).get("status") == "connected"
                   for s in servers):
            raise ClientError("ha_mcp_not_connected", transient=True)

    def interrupt(self, session_id):
        self.api("post", f"/api/session/{session_id}/interrupt", timeout=10)

    def review(self, prompt: str, session_path: Path, deadline: float):
        from review import atomic_json

        session_id = None
        try:
            if session_path.exists():
                session_id = json.loads(session_path.read_text())["session_id"]
            else:
                created = self.api("post", "/api/session", {
                    "agent": AGENT, "model": MODEL, "permissions": PERMISSIONS,
                    "location": {"directory": str(self.project)}, "title": "Daily Home Assistant review",
                }, timeout=min(60, remaining(deadline)))
                session_id = created["data"]["id"]
                atomic_json(session_path, {"session_id": session_id})
                self.api("post", f"/api/session/{session_id}/prompt", {"text": prompt},
                         timeout=min(60, remaining(deadline)))
            self.api("post", f"/api/experimental/session/{session_id}/wait", timeout=remaining(deadline))
            context = self.api("get", f"/api/session/{session_id}/context",
                               timeout=min(30, remaining(deadline)))["data"]
            return session_id, final_result(context)
        except BaseException as error:
            if session_id:
                try:
                    self.interrupt(session_id)
                except Exception:
                    pass
            if isinstance(error, subprocess.TimeoutExpired):
                raise ClientError("opencode_timeout") from None
            raise
