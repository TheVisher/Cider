#!/usr/bin/env python3
"""Read-only, profile-safe Codex app-server usage monitor."""

import argparse
from datetime import datetime
import json
import math
import os
import re
import selectors
import subprocess
import sys
import time


SCHEMA_VERSION = "cider.codex-usage-monitor.v1"
FIVE_HOUR_MINS = 300
WEEKLY_MINS = 10080

ERROR_MESSAGES = {
    "EXECUTABLE_UNAVAILABLE": "Codex app-server executable is unavailable.",
    "PROCESS_EXIT": "Codex app-server exited before the read completed.",
    "TIMEOUT": "Codex app-server read timed out.",
    "MALFORMED_JSON": "Codex app-server returned malformed JSON.",
    "TRUNCATED_RESPONSE": "Codex app-server returned a truncated response.",
    "MALFORMED_JSON_RPC": "Codex app-server returned malformed JSON-RPC.",
    "MISMATCHED_RESPONSE_ID": "Codex app-server returned an unexpected response ID.",
    "METHOD_ERROR": "Codex app-server returned a method error.",
    "MALFORMED_SCHEMA": "Codex app-server returned an unsupported response schema.",
    "MISSING_USED_PERCENT": "A rate-limit window is missing used percent.",
    "INVALID_USED_PERCENT": "A rate-limit window has invalid used percent.",
    "IMPOSSIBLE_USED_PERCENT": "A rate-limit window has an impossible used percent.",
    "INVALID_WINDOW_DURATION": "A rate-limit window has an invalid duration.",
    "MISSING_RESET": "An active finite rate-limit window is missing its reset time.",
    "INVALID_RESET": "A rate-limit window has an invalid reset time.",
    "INVALID_ARGUMENT": "Monitor configuration is invalid.",
    "INTERNAL_ERROR": "The usage monitor failed safely.",
}


class MonitorError(Exception):
    def __init__(self, code):
        self.code = code if code in ERROR_MESSAGES else "INTERNAL_ERROR"
        super().__init__(ERROR_MESSAGES[self.code])


def _safe_identifier(value, required=True):
    if value is None and not required:
        return None
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:/+() -]{0,79}", value):
        raise MonitorError("MALFORMED_SCHEMA")
    return value


def _safe_data_label(value, required=True):
    if value is None and not required:
        return None
    if not isinstance(value, str):
        raise MonitorError("MALFORMED_SCHEMA")
    stripped = value.strip()
    if not stripped or len(stripped) > 80 or any(ord(character) < 32 or ord(character) == 127 for character in stripped):
        raise MonitorError("MALFORMED_SCHEMA")
    return stripped


def _safe_display_name(value):
    if value is None:
        return None
    if not isinstance(value, str):
        raise MonitorError("MALFORMED_SCHEMA")
    stripped = value.strip()
    if not stripped or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9 ._+()/:-]{0,79}", stripped):
        return None
    return stripped


def _local_iso(epoch):
    try:
        return datetime.fromtimestamp(epoch).astimezone().isoformat(timespec="seconds")
    except (OverflowError, OSError, ValueError):
        raise MonitorError("INVALID_RESET")


def evaluate_policy(window_duration_mins, used_percent, resets_at, now_epoch):
    if window_duration_mins == FIVE_HOUR_MINS:
        if used_percent >= 95:
            severity = "critical"
        elif used_percent >= 85:
            severity = "high"
        elif used_percent >= 70:
            severity = "warning"
        else:
            severity = "normal"
        return severity, "continue"

    if window_duration_mins == WEEKLY_MINS:
        if used_percent >= 92:
            severity = "critical"
        elif used_percent >= 85:
            severity = "high"
        elif used_percent >= 75:
            severity = "warning"
        elif used_percent >= 60:
            severity = "watch"
        else:
            severity = "normal"

        remaining = 100 - used_percent
        if remaining < 8:
            action = "reserve_sol_for_blockers_review_landing"
        elif remaining < 15 and resets_at - now_epoch > 86_400:
            action = "pause_nonessential_sol_coding"
        else:
            action = "continue"
        return severity, action

    return "unknown", "review_unknown_window"


def _parse_window(raw, reached_reason, bucket_kind, now_epoch):
    if not isinstance(raw, dict):
        raise MonitorError("MALFORMED_SCHEMA")
    if "usedPercent" not in raw:
        raise MonitorError("MISSING_USED_PERCENT")
    used = raw["usedPercent"]
    if isinstance(used, bool) or not isinstance(used, (int, float)) or not math.isfinite(used):
        raise MonitorError("INVALID_USED_PERCENT")
    if not float(used).is_integer():
        raise MonitorError("INVALID_USED_PERCENT")
    used = int(used)
    if used < 0 or used > 100:
        raise MonitorError("IMPOSSIBLE_USED_PERCENT")

    duration = raw.get("windowDurationMins")
    if isinstance(duration, bool) or not isinstance(duration, int) or duration <= 0:
        raise MonitorError("INVALID_WINDOW_DURATION")

    reset = raw.get("resetsAt")
    if reset is None:
        raise MonitorError("MISSING_RESET")
    if isinstance(reset, bool) or not isinstance(reset, int) or reset <= 0:
        raise MonitorError("INVALID_RESET")

    if bucket_kind == "codex":
        severity, action = evaluate_policy(duration, used, reset, now_epoch)
    elif bucket_kind == "spark":
        severity, action = "separate", "track_separately_not_sol_authorization"
    else:
        severity, action = "unknown", "review_unknown_bucket"

    parsed = {
        "windowDurationMins": duration,
        "usedPercent": used,
        "remainingPercent": 100 - used,
        "resetsAt": reset,
        "resetsAtLocal": _local_iso(reset),
        "reachedReason": reached_reason,
        "severity": severity,
        "policyAction": action,
    }
    if duration not in (FIVE_HOUR_MINS, WEEKLY_MINS):
        parsed["unknownReason"] = "unrecognized_window_duration"
    return parsed


def _parse_account(raw):
    if not isinstance(raw, dict):
        raise MonitorError("MALFORMED_SCHEMA")
    account = raw.get("account")
    if not isinstance(account, dict):
        raise MonitorError("MALFORMED_SCHEMA")
    account_type = _safe_data_label(account.get("type"))
    plan_type = account.get("planType")
    if plan_type is not None:
        plan_type = _safe_data_label(plan_type)
    return account_type, plan_type


def _bucket_source(raw):
    if not isinstance(raw, dict):
        raise MonitorError("MALFORMED_SCHEMA")
    by_id = raw.get("rateLimitsByLimitId")
    if by_id is not None:
        if not isinstance(by_id, dict):
            raise MonitorError("MALFORMED_SCHEMA")
        if by_id:
            return list(by_id.items())
    legacy = raw.get("rateLimits")
    if not isinstance(legacy, dict):
        raise MonitorError("MALFORMED_SCHEMA")
    limit_id = legacy.get("limitId")
    if limit_id is None:
        raise MonitorError("MALFORMED_SCHEMA")
    return [(limit_id, legacy)]


def _parse_bucket(map_id, raw, now_epoch):
    limit_id = _safe_identifier(map_id)
    if not isinstance(raw, dict):
        raise MonitorError("MALFORMED_SCHEMA")
    embedded_id = raw.get("limitId")
    if embedded_id is not None and _safe_identifier(embedded_id) != limit_id:
        raise MonitorError("MALFORMED_SCHEMA")

    display_name = _safe_display_name(raw.get("limitName"))
    normalized_id = limit_id.lower()
    normalized_name = (display_name or "").lower()
    if normalized_id == "codex":
        bucket_kind = "codex"
    elif normalized_id == "spark" or "codex-spark" in normalized_name:
        bucket_kind = "spark"
    else:
        bucket_kind = "unknown"

    reached_reason = raw.get("rateLimitReachedType")
    if reached_reason is not None:
        reached_reason = _safe_identifier(reached_reason)

    windows = []
    for key in ("primary", "secondary"):
        value = raw.get(key)
        if value is not None:
            windows.append(_parse_window(value, reached_reason, bucket_kind, now_epoch))
    if not windows:
        raise MonitorError("MALFORMED_SCHEMA")
    windows.sort(key=lambda item: item["windowDurationMins"])

    parsed = {"limitId": limit_id}
    if display_name is not None:
        parsed["displayName"] = display_name
    if bucket_kind == "unknown":
        parsed["unknownReason"] = "unrecognized_limit_id"
    parsed["windows"] = windows
    return parsed


def build_report(account_response, rate_limits_response, now_epoch=None):
    now_epoch = int(time.time()) if now_epoch is None else int(now_epoch)
    account_type, plan_type = _parse_account(account_response)
    source = _bucket_source(rate_limits_response)
    buckets = [_parse_bucket(map_id, raw, now_epoch) for map_id, raw in source]
    buckets.sort(key=lambda item: item["limitId"].lower())

    if plan_type is None:
        plans = {
            raw.get("planType")
            for _, raw in source
            if isinstance(raw, dict) and raw.get("planType") is not None
        }
        if len(plans) == 1:
            plan_type = _safe_data_label(plans.pop())

    return {
        "schemaVersion": SCHEMA_VERSION,
        "accountType": account_type,
        "planType": plan_type,
        "retrievedAt": _local_iso(now_epoch),
        "buckets": buckets,
    }


class AppServerClient:
    def __init__(self, command, timeout):
        self.command = list(command)
        self.timeout = timeout
        self.process = None
        self.selector = None
        self.buffer = bytearray()
        self.next_id = 1
        self.deadline = None
        self.saw_mismatched_id = False

    def __enter__(self):
        try:
            self.process = subprocess.Popen(
                self.command,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
            )
        except (FileNotFoundError, PermissionError, OSError):
            raise MonitorError("EXECUTABLE_UNAVAILABLE")
        self.deadline = time.monotonic() + self.timeout
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        return self

    def __exit__(self, _exc_type, _exc, _traceback):
        self.close()
        return False

    def close(self):
        if self.selector is not None:
            self.selector.close()
            self.selector = None
        if self.process is None:
            return
        if self.process.stdin is not None:
            try:
                self.process.stdin.close()
            except OSError:
                pass
        if self.process.poll() is None:
            try:
                self.process.terminate()
            except ProcessLookupError:
                pass
            try:
                self.process.wait(timeout=0.5)
            except subprocess.TimeoutExpired:
                try:
                    self.process.kill()
                except ProcessLookupError:
                    pass
                try:
                    self.process.wait(timeout=0.5)
                except subprocess.TimeoutExpired:
                    pass
        if self.process.stdout is not None:
            self.process.stdout.close()
        self.process = None

    def _remaining(self):
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise MonitorError("TIMEOUT")
        return remaining

    def _read_message(self, expected_id):
        while True:
            newline = self.buffer.find(b"\n")
            if newline >= 0:
                raw_line = bytes(self.buffer[:newline])
                del self.buffer[: newline + 1]
                if not raw_line.strip():
                    continue
                try:
                    message = json.loads(
                        raw_line.decode("utf-8"),
                        parse_constant=lambda _value: (_ for _ in ()).throw(ValueError()),
                    )
                except (UnicodeDecodeError, json.JSONDecodeError, ValueError):
                    raise MonitorError("MALFORMED_JSON")
                if not isinstance(message, dict):
                    raise MonitorError("MALFORMED_JSON_RPC")
                protocol_version = message.get("jsonrpc")
                if protocol_version is not None and protocol_version != "2.0":
                    raise MonitorError("MALFORMED_JSON_RPC")
                if "id" not in message:
                    if isinstance(message.get("method"), str):
                        continue
                    raise MonitorError("MALFORMED_JSON_RPC")
                if message["id"] != expected_id:
                    self.saw_mismatched_id = True
                    continue
                if "error" in message:
                    if not isinstance(message["error"], dict):
                        raise MonitorError("MALFORMED_JSON_RPC")
                    raise MonitorError("METHOD_ERROR")
                if "result" not in message or not isinstance(message["result"], dict):
                    raise MonitorError("MALFORMED_JSON_RPC")
                return message["result"]

            ready = self.selector.select(self._remaining())
            if not ready:
                if self.saw_mismatched_id:
                    raise MonitorError("MISMATCHED_RESPONSE_ID")
                raise MonitorError("TIMEOUT")
            chunk = os.read(self.process.stdout.fileno(), 65_536)
            if not chunk:
                if self.buffer:
                    raise MonitorError("TRUNCATED_RESPONSE")
                if self.saw_mismatched_id:
                    raise MonitorError("MISMATCHED_RESPONSE_ID")
                raise MonitorError("PROCESS_EXIT")
            self.buffer.extend(chunk)

    def call(self, method, params):
        request_id = self.next_id
        self.next_id += 1
        payload = {
            "id": request_id,
            "method": method,
            "params": params,
        }
        try:
            encoded = json.dumps(payload, separators=(",", ":")).encode("utf-8") + b"\n"
            self.process.stdin.write(encoded)
            self.process.stdin.flush()
        except (BrokenPipeError, OSError):
            raise MonitorError("PROCESS_EXIT")
        return self._read_message(request_id)

    def notify(self, method, params):
        if self.process is None or self.process.stdin is None:
            raise MonitorError("PROCESS_EXIT")
        payload = {"method": method, "params": params}
        try:
            encoded = json.dumps(payload, separators=(",", ":")).encode("utf-8") + b"\n"
            self.process.stdin.write(encoded)
            self.process.stdin.flush()
        except (BrokenPipeError, OSError):
            raise MonitorError("PROCESS_EXIT")


def collect(command, timeout=10.0, now_epoch=None):
    if not command or timeout <= 0 or not math.isfinite(timeout):
        raise MonitorError("INVALID_ARGUMENT")
    with AppServerClient(command, timeout) as client:
        client.call(
            "initialize",
            {"clientInfo": {"name": "cider-usage-monitor", "title": "Cider Usage Monitor", "version": "1"}},
        )
        client.notify("initialized", {})
        account_response = client.call("account/read", {})
        rate_limits_response = client.call("account/rateLimits/read", {})
    return build_report(account_response, rate_limits_response, now_epoch=now_epoch)


def format_human(report):
    lines = [
        "Codex usage: {0} plan={1} at {2}".format(
            report["accountType"], report["planType"] or "unknown", report["retrievedAt"]
        )
    ]
    for bucket in report["buckets"]:
        summaries = []
        for value in bucket["windows"]:
            duration = value["windowDurationMins"]
            label = "5h" if duration == FIVE_HOUR_MINS else "weekly" if duration == WEEKLY_MINS else "{}m".format(duration)
            summaries.append(
                "{0} {1}% used ({2}; {3})".format(
                    label, value["usedPercent"], value["severity"], value["policyAction"]
                )
            )
        suffix = " [unknown bucket]" if "unknownReason" in bucket else ""
        lines.append("{0}{1}: {2}".format(bucket["limitId"], suffix, "; ".join(summaries)))
    return "\n".join(lines)


def _parser():
    parser = argparse.ArgumentParser(
        description="Read-only Codex usage monitor using app-server JSON-RPC; it never starts a model turn.",
    )
    parser.add_argument("--json", action="store_true", help="emit deterministic sanitized JSON")
    parser.add_argument("--timeout", type=float, default=10.0, help="total app-server timeout in seconds (default: 10)")
    parser.add_argument("--command", default="npx", help="app-server executable (default: npx)")
    parser.add_argument(
        "--command-arg",
        action="append",
        default=None,
        help="argument for the configured executable; repeat as needed (default: -y @openai/codex@latest app-server --stdio)",
    )
    return parser


def _error_payload(error):
    return {
        "schemaVersion": SCHEMA_VERSION,
        "error": {"code": error.code, "message": ERROR_MESSAGES[error.code]},
    }


def main(argv=None):
    parser = _parser()
    args = parser.parse_args(argv)
    command_args = args.command_arg if args.command_arg is not None else [
        "-y", "@openai/codex@latest", "app-server", "--stdio"
    ]
    command = [args.command] + command_args
    try:
        report = collect(command, timeout=args.timeout)
    except MonitorError as error:
        if args.json:
            print(json.dumps(_error_payload(error), sort_keys=True, separators=(",", ":")))
        else:
            print("Codex usage unavailable: {0} ({1})".format(ERROR_MESSAGES[error.code], error.code))
        return 2
    except Exception:
        error = MonitorError("INTERNAL_ERROR")
        if args.json:
            print(json.dumps(_error_payload(error), sort_keys=True, separators=(",", ":")))
        else:
            print("Codex usage unavailable: {0} ({1})".format(ERROR_MESSAGES[error.code], error.code))
        return 2

    if args.json:
        print(json.dumps(report, sort_keys=True, separators=(",", ":")))
    else:
        print(format_human(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
