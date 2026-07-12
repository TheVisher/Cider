import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPO_ROOT / "scripts" / "codex_usage_monitor.py"
SPEC = importlib.util.spec_from_file_location("codex_usage_monitor", SCRIPT_PATH)
monitor = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(monitor)


RESET_5H = 2_000_018_000
RESET_WEEK = 2_000_604_800
NOW = 2_000_000_000
PRIVACY_SENTINEL = "PRIVATE_SENTINEL_CID778"


def window(duration, used, reset=None):
    return {
        "windowDurationMins": duration,
        "usedPercent": used,
        "resetsAt": reset if reset is not None else NOW + duration * 60,
    }


def snapshot(limit_id="codex", plan="prolite", primary=None, secondary=None, **extra):
    value = {
        "limitId": limit_id,
        "limitName": "Codex" if limit_id == "codex" else "Spark",
        "planType": plan,
        "primary": primary if primary is not None else window(300, 25, RESET_5H),
        "secondary": secondary if secondary is not None else window(10080, 40, RESET_WEEK),
        "rateLimitReachedType": None,
    }
    value.update(extra)
    return value


def account(plan="prolite"):
    return {
        "requiresOpenaiAuth": True,
        "account": {
            "type": "chatgpt",
            "planType": plan,
            "email": f"{PRIVACY_SENTINEL}@example.com",
            "userId": PRIVACY_SENTINEL,
            "accessToken": PRIVACY_SENTINEL,
        },
        "authMetadata": PRIVACY_SENTINEL,
    }


def rate_limits(*buckets):
    bucket_list = buckets or (snapshot(),)
    by_id = {value["limitId"]: value for value in bucket_list}
    return {
        "rateLimits": bucket_list[0],
        "rateLimitsByLimitId": by_id,
        "rateLimitResetCredits": {
            "availableCount": 1,
            "credits": [{"id": PRIVACY_SENTINEL, "description": PRIVACY_SENTINEL}],
        },
        "rawPrivateValue": PRIVACY_SENTINEL,
    }


class ReportParsingTests(unittest.TestCase):
    def build(self, limits=None, account_value=None):
        return monitor.build_report(
            account_value or account(), limits or rate_limits(), now_epoch=NOW
        )

    def test_normal_5h_and_weekly_response(self):
        report = self.build()
        self.assertEqual(report["schemaVersion"], "cider.codex-usage-monitor.v1")
        self.assertEqual(report["accountType"], "chatgpt")
        self.assertEqual(report["planType"], "prolite")
        self.assertEqual(len(report["buckets"]), 1)
        bucket = report["buckets"][0]
        self.assertEqual(bucket["limitId"], "codex")
        self.assertEqual([item["windowDurationMins"] for item in bucket["windows"]], [300, 10080])
        self.assertEqual(bucket["windows"][0]["remainingPercent"], 75)
        self.assertEqual(bucket["windows"][1]["remainingPercent"], 60)
        self.assertIsInstance(bucket["windows"][0]["resetsAtLocal"], str)

    def test_prolite_plan_is_preserved(self):
        self.assertEqual(self.build()["planType"], "prolite")

    def test_unknown_future_plan_is_preserved(self):
        report = self.build(account_value=account("future ultra-plan 2"))
        self.assertEqual(report["planType"], "future ultra-plan 2")

    def test_no_secondary_bucket_is_valid(self):
        value = snapshot(secondary=None)
        value["secondary"] = None
        report = self.build(rate_limits(value))
        self.assertEqual(len(report["buckets"][0]["windows"]), 1)
        self.assertEqual(report["buckets"][0]["windows"][0]["windowDurationMins"], 300)

    def test_spark_bucket_remains_separate_and_cannot_authorize_sol(self):
        spark = snapshot("spark", primary=window(300, 0), secondary=window(10080, 0))
        report = self.build(rate_limits(snapshot(), spark))
        self.assertEqual([b["limitId"] for b in report["buckets"]], ["codex", "spark"])
        spark_windows = report["buckets"][1]["windows"]
        self.assertTrue(all(w["policyAction"] == "track_separately_not_sol_authorization" for w in spark_windows))

    def test_live_style_spark_bucket_is_classified_from_public_display_name(self):
        spark = snapshot("codex_bengalfox", primary=window(300, 0), secondary=window(10080, 0))
        spark["limitName"] = "GPT-5.3-Codex-Spark"
        report = self.build(rate_limits(snapshot(), spark))
        live_spark = report["buckets"][1]
        self.assertNotIn("unknownReason", live_spark)
        self.assertTrue(all(
            item["policyAction"] == "track_separately_not_sol_authorization"
            for item in live_spark["windows"]
        ))

    def test_unknown_structurally_valid_bucket_is_visible(self):
        unknown = snapshot("future-bucket", primary=window(720, 20), secondary=None)
        unknown["secondary"] = None
        report = self.build(rate_limits(unknown))
        bucket = report["buckets"][0]
        self.assertEqual(bucket["limitId"], "future-bucket")
        self.assertEqual(bucket["unknownReason"], "unrecognized_limit_id")
        self.assertEqual(bucket["windows"][0]["unknownReason"], "unrecognized_window_duration")

    def assert_schema_error(self, mutate, code):
        value = snapshot()
        mutate(value)
        with self.assertRaises(monitor.MonitorError) as caught:
            self.build(rate_limits(value))
        self.assertEqual(caught.exception.code, code)

    def test_missing_reset_fails(self):
        self.assert_schema_error(lambda value: value["primary"].update(resetsAt=None), "MISSING_RESET")

    def test_missing_percent_fails(self):
        self.assert_schema_error(lambda value: value["primary"].pop("usedPercent"), "MISSING_USED_PERCENT")

    def test_invalid_percent_type_fails(self):
        self.assert_schema_error(lambda value: value["primary"].update(usedPercent="25"), "INVALID_USED_PERCENT")

    def test_impossible_negative_percent_fails(self):
        self.assert_schema_error(lambda value: value["primary"].update(usedPercent=-1), "IMPOSSIBLE_USED_PERCENT")

    def test_impossible_percent_over_100_fails(self):
        self.assert_schema_error(lambda value: value["primary"].update(usedPercent=101), "IMPOSSIBLE_USED_PERCENT")

    def test_missing_window_duration_fails(self):
        self.assert_schema_error(lambda value: value["primary"].pop("windowDurationMins"), "INVALID_WINDOW_DURATION")

    def test_malformed_rate_limit_schema_fails(self):
        with self.assertRaises(monitor.MonitorError) as caught:
            self.build({"rateLimits": []})
        self.assertEqual(caught.exception.code, "MALFORMED_SCHEMA")

    def test_reached_reason_is_preserved_from_allowlisted_field(self):
        value = snapshot(rateLimitReachedType="rate_limit_reached")
        report = self.build(rate_limits(value))
        self.assertTrue(all(w["reachedReason"] == "rate_limit_reached" for w in report["buckets"][0]["windows"]))

    def test_private_fields_and_values_are_absent(self):
        serialized = json.dumps(self.build(), sort_keys=True)
        self.assertNotIn(PRIVACY_SENTINEL, serialized)
        for forbidden in ("email", "userId", "accessToken", "refreshToken", "credits", "authMetadata"):
            self.assertNotIn(forbidden, serialized)


class ThresholdPolicyTests(unittest.TestCase):
    def assert_policy(self, duration, used, severity, action="continue"):
        result = monitor.evaluate_policy(duration, used, NOW + 3 * 86_400, NOW)
        self.assertEqual(result, (severity, action))

    def test_5h_thresholds_immediately_below_at_and_above(self):
        expected = {
            69: "normal", 70: "warning", 71: "warning",
            84: "warning", 85: "high", 86: "high",
            94: "high", 95: "critical", 96: "critical",
        }
        for used, severity in expected.items():
            with self.subTest(used=used):
                self.assert_policy(300, used, severity)

    def test_weekly_thresholds_immediately_below_at_and_above(self):
        expected = {
            59: "normal", 60: "watch", 61: "watch",
            74: "watch", 75: "warning", 76: "warning",
            84: "warning", 85: "high", 86: "high",
            91: "high", 92: "critical", 93: "critical",
        }
        for used, severity in expected.items():
            with self.subTest(used=used):
                action = "continue"
                if used > 92:
                    action = "reserve_sol_for_blockers_review_landing"
                elif used > 85:
                    action = "pause_nonessential_sol_coding"
                self.assert_policy(10080, used, severity, action)

    def test_weekly_below_15_percent_remaining_and_over_24h_pauses(self):
        result = monitor.evaluate_policy(10080, 86, NOW + 86_401, NOW)
        self.assertEqual(result, ("high", "pause_nonessential_sol_coding"))

    def test_weekly_exactly_15_percent_remaining_does_not_pause(self):
        result = monitor.evaluate_policy(10080, 85, NOW + 86_401, NOW)
        self.assertEqual(result, ("high", "continue"))

    def test_weekly_below_8_percent_remaining_reserves_sol(self):
        result = monitor.evaluate_policy(10080, 93, NOW + 1, NOW)
        self.assertEqual(result, ("critical", "reserve_sol_for_blockers_review_landing"))

    def test_weekly_exactly_8_percent_remaining_does_not_reserve(self):
        result = monitor.evaluate_policy(10080, 92, NOW + 86_401, NOW)
        self.assertEqual(result, ("critical", "pause_nonessential_sol_coding"))

    def test_reset_within_24h_does_not_pause(self):
        result = monitor.evaluate_policy(10080, 90, NOW + 86_400, NOW)
        self.assertEqual(result, ("high", "continue"))

    def test_unknown_duration_has_unknown_policy(self):
        result = monitor.evaluate_policy(720, 50, NOW + 10, NOW)
        self.assertEqual(result, ("unknown", "review_unknown_window"))


FAKE_SERVER = r'''
import json
import os
import signal
import sys
import time

mode = sys.argv[1]
marker = sys.argv[2] if len(sys.argv) > 2 else None

def reply(request, result=None, error=None, response_id=None):
    value = {"id": request["id"] if response_id is None else response_id}
    if error is not None:
        value["error"] = {"code": -32000, "message": error}
    else:
        value["result"] = result
    print(json.dumps(value), flush=True)

def account_result():
    return {"requiresOpenaiAuth": True, "account": {"type": "chatgpt", "planType": "prolite", "email": "PRIVATE_SENTINEL_CID778@example.com"}}

def limit_result():
    snap = {"limitId": "codex", "limitName": "Codex", "planType": "prolite", "primary": {"windowDurationMins": 300, "usedPercent": 25, "resetsAt": 2000018000}, "secondary": {"windowDurationMins": 10080, "usedPercent": 40, "resetsAt": 2000604800}, "rateLimitReachedType": None}
    return {"rateLimits": snap, "rateLimitsByLimitId": {"codex": snap}, "rateLimitResetCredits": {"credits": [{"id": "PRIVATE_SENTINEL_CID778"}]}}

if mode == "timeout":
    if marker:
        with open(marker, "w") as stream:
            stream.write(str(os.getpid()))
    def stop_timeout(*_args):
        if marker:
            with open(marker + ".terminated", "w") as stream:
                stream.write("yes")
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, stop_timeout)
    time.sleep(60)
    raise SystemExit

for line in sys.stdin:
    request = json.loads(line)
    method = request.get("method")
    if method == "initialized" and "id" not in request:
        continue
    if mode == "malformed_json":
        print("{not-json", flush=True)
        break
    if mode == "truncated":
        sys.stdout.write('{"jsonrpc":"2.0","id":')
        sys.stdout.flush()
        break
    if mode == "malformed_rpc":
        print(json.dumps({"jsonrpc": "1.0", "id": request["id"], "result": {}}), flush=True)
        break
    if mode == "method_error":
        reply(request, error="PRIVATE_SENTINEL_CID778 backend detail")
        break
    if mode == "mismatched_id":
        reply(request, result={}, response_id=999999)
        break
    if mode == "exit_nonzero":
        print("PRIVATE_SENTINEL_CID778", file=sys.stderr, flush=True)
        raise SystemExit(7)
    if mode == "notifications":
        print(json.dumps({"method": "account/rateLimits/updated", "params": {"private": "PRIVATE_SENTINEL_CID778"}}), flush=True)
    if method == "initialize":
        reply(request, {"userAgent": "fake"})
    elif method == "account/read":
        reply(request, account_result())
    elif method == "account/rateLimits/read":
        if marker:
            with open(marker + ".pid", "w") as stream:
                stream.write(str(os.getpid()))
            with open(marker, "w") as stream:
                stream.write("complete")
            def stop_success(*_args):
                with open(marker + ".terminated", "w") as stream:
                    stream.write("yes")
                raise SystemExit(0)
            signal.signal(signal.SIGTERM, stop_success)
        reply(request, limit_result())
        if marker:
            time.sleep(60)
        break
    else:
        reply(request, error="forbidden method")
'''


class ProtocolAndCLITests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.fake_path = Path(self.temp.name) / "fake_app_server.py"
        self.fake_path.write_text(textwrap.dedent(FAKE_SERVER), encoding="utf-8")

    def tearDown(self):
        self.temp.cleanup()

    def command(self, mode, *extra, timeout="1"):
        return [
            sys.executable, str(SCRIPT_PATH), "--json", "--timeout", timeout,
            "--command", sys.executable,
            "--command-arg", str(self.fake_path),
            "--command-arg", mode,
            *extra,
        ]

    def run_cli(self, mode, *extra, timeout="1"):
        return subprocess.run(
            self.command(mode, *extra, timeout=timeout),
            text=True, capture_output=True, timeout=5, check=False,
        )

    def assert_sanitized_error(self, completed, code):
        self.assertNotEqual(completed.returncode, 0)
        payload = json.loads(completed.stdout)
        self.assertEqual(payload, {"error": {"code": code, "message": monitor.ERROR_MESSAGES[code]}, "schemaVersion": "cider.codex-usage-monitor.v1"})
        self.assertNotIn(PRIVACY_SENTINEL, completed.stdout + completed.stderr)

    def test_notifications_before_responses_are_tolerated(self):
        completed = self.run_cli("notifications")
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertEqual(json.loads(completed.stdout)["planType"], "prolite")
        self.assertNotIn(PRIVACY_SENTINEL, completed.stdout + completed.stderr)

    def test_malformed_json_fails_safely(self):
        self.assert_sanitized_error(self.run_cli("malformed_json"), "MALFORMED_JSON")

    def test_truncated_response_fails_safely(self):
        self.assert_sanitized_error(self.run_cli("truncated"), "TRUNCATED_RESPONSE")

    def test_malformed_json_rpc_fails_safely(self):
        self.assert_sanitized_error(self.run_cli("malformed_rpc"), "MALFORMED_JSON_RPC")

    def test_method_error_fails_without_server_message(self):
        self.assert_sanitized_error(self.run_cli("method_error"), "METHOD_ERROR")

    def test_mismatched_ids_fail(self):
        self.assert_sanitized_error(self.run_cli("mismatched_id"), "MISMATCHED_RESPONSE_ID")

    def test_timeout_fails_and_cleans_up_child(self):
        marker = Path(self.temp.name) / "child"
        completed = self.run_cli("timeout", "--command-arg", str(marker), timeout="0.1")
        self.assert_sanitized_error(completed, "TIMEOUT")
        for _ in range(40):
            if Path(str(marker) + ".terminated").exists():
                break
            time.sleep(0.025)
        self.assertTrue(Path(str(marker) + ".terminated").exists())
        pid = int(marker.read_text())
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)

    def test_unavailable_executable_fails(self):
        command = [sys.executable, str(SCRIPT_PATH), "--json", "--command", "/definitely/not/codex"]
        completed = subprocess.run(command, text=True, capture_output=True, check=False)
        self.assert_sanitized_error(completed, "EXECUTABLE_UNAVAILABLE")

    def test_nonzero_process_exit_fails_without_stderr_leak(self):
        self.assert_sanitized_error(self.run_cli("exit_nonzero"), "PROCESS_EXIT")

    def test_success_cleans_up_child(self):
        marker = Path(self.temp.name) / "success"
        completed = self.run_cli("normal", "--command-arg", str(marker))
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertEqual(marker.read_text(), "complete")
        self.assertTrue(Path(str(marker) + ".terminated").exists())
        pid = int(Path(str(marker) + ".pid").read_text())
        with self.assertRaises(ProcessLookupError):
            os.kill(pid, 0)

    def test_default_does_not_call_usage_or_any_forbidden_method(self):
        client = mock.MagicMock()
        client.__enter__.return_value = client
        client.call.side_effect = [{}, account(), rate_limits()]
        with mock.patch.object(monitor, "AppServerClient", return_value=client):
            monitor.collect(["codex", "app-server", "--stdio"], timeout=1, now_epoch=NOW)
        methods = [entry.args[0] for entry in client.call.call_args_list]
        self.assertEqual(methods, ["initialize", "account/read", "account/rateLimits/read"])
        client.notify.assert_called_once_with("initialized", {})
        self.assertEqual(client.call.call_args_list[1].args[1], {})
        self.assertEqual(client.call.call_args_list[2].args[1], {})
        serialized = " ".join(methods)
        for forbidden in ("usage/read", "thread/start", "turn/start", "consume", "login", "logout", "purchase"):
            self.assertNotIn(forbidden, serialized)

    def test_source_never_uses_shell_true_or_forbidden_rpc_methods(self):
        source = SCRIPT_PATH.read_text(encoding="utf-8")
        self.assertNotIn("shell=True", source)
        for forbidden in ("thread/start", "turn/start", "rateLimitResetCredit/consume", "account/login", "account/logout", "credits/purchase"):
            self.assertNotIn(forbidden, source)

    def test_current_app_server_envelope_without_jsonrpc_version_is_supported(self):
        completed = self.run_cli("normal")
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertEqual(json.loads(completed.stdout)["planType"], "prolite")

    def test_default_command_matches_proven_host_invocation(self):
        parser = monitor._parser()
        args = parser.parse_args([])
        command_args = args.command_arg if args.command_arg is not None else [
            "-y", "@openai/codex@latest", "app-server", "--stdio"
        ]
        self.assertEqual([args.command] + command_args, [
            "npx", "-y", "@openai/codex@latest", "app-server", "--stdio"
        ])

    def test_human_output_is_concise_and_content_free(self):
        completed = subprocess.run(self.command("normal")[0:2] + self.command("normal")[3:], text=True, capture_output=True, check=False)
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertLessEqual(len(completed.stdout.splitlines()), 4)
        self.assertNotIn(PRIVACY_SENTINEL, completed.stdout + completed.stderr)

    def test_help_documents_safe_configuration(self):
        completed = subprocess.run([sys.executable, str(SCRIPT_PATH), "--help"], text=True, capture_output=True, check=False)
        self.assertEqual(completed.returncode, 0)
        self.assertIn("--timeout", completed.stdout)
        self.assertIn("--command", completed.stdout)
        self.assertIn("read-only", completed.stdout.lower())


if __name__ == "__main__":
    unittest.main()
