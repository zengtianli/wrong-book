#!/usr/bin/env python3
"""Consumer regression checks; every fixture/measurement subprocess is fake."""
import contextlib
import importlib.util
import io
import json
import subprocess
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location("product_measure", Path(__file__).with_name("measure_platforms.py"))
consumer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(consumer)


class ConsumerTests(unittest.TestCase):
    def run_consumer(self, args, codes=(), evidence=None, expires=False):
        shared = Mock()
        shared.lane_config.return_value = {}
        shared.lane_inputs.return_value = "current-input"
        shared.current_evidence.return_value = evidence
        calls, clock = [], [0.0]
        codes = iter(codes)

        def fake_run(command, **kwargs):
            calls.append(list(map(str, command)))
            if "start" in command:
                demo = {"url": "http://127.0.0.1:1", "cookie": "fictional", "user": "fictional", "pw": "fictional"}
                return subprocess.CompletedProcess(command, 0, json.dumps(demo), "")
            if "stop" in command:
                return subprocess.CompletedProcess(command, 0, "", "")
            if expires:
                clock[0] = 61.0
            return subprocess.CompletedProcess(command, next(codes, 0), "", "")

        with patch.object(consumer, "shared_tools", return_value=shared), \
             patch.object(consumer.subprocess, "run", side_effect=fake_run), \
             patch.object(consumer.time, "monotonic", side_effect=lambda: clock[0]), \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            result = consumer.main(args)
        measures = [call for call in calls if str(consumer.PLATFORM_MEASURE) in call]
        self.assertFalse(any("sim_measure.py" in arg for call in calls for arg in call))
        return result, calls, measures, shared

    def test_legacy_alias_measures_iphone_once_and_projects(self):
        result, calls, measures, _ = self.run_consumer(["--only", "legacy,iphone"])
        self.assertEqual(result, 0)
        self.assertEqual(len(measures), 1)
        self.assertEqual(measures[0][measures[0].index("--platform") + 1], "iphone")
        self.assertIn("--sync-ios", measures[0])
        for flag in ("--lock-wait", "--load-wait"):
            self.assertEqual(measures[0][measures[0].index(flag) + 1], "0")
        self.assertEqual(sum("stop" in call for call in calls), 1)

    def test_busy_stops_and_tears_down_fixture(self):
        result, calls, measures, _ = self.run_consumer(["--only", "iphone,ipad"], codes=[75, 0])
        self.assertEqual(result, 75)
        self.assertEqual(len(measures), 1)
        self.assertIn("stop", calls[-1])

    def test_current_iphone_uses_shared_proof_and_projection(self):
        doc = {"input_sha256": "current-input"}
        result, calls, measures, shared = self.run_consumer(["--only", "legacy"], evidence=doc)
        self.assertEqual(result, 0)
        self.assertEqual(calls, [])
        shared.current_evidence.assert_called_once_with(consumer.REPO, "iphone", {}, "current-input", fixture_debug=False)
        shared.sync_ios_evidence.assert_called_once_with(consumer.REPO, doc)

    def test_force_remeasures_valid_evidence(self):
        result, _, measures, shared = self.run_consumer(["--only", "iphone", "--force"], evidence={})
        self.assertEqual(result, 0)
        self.assertEqual(len(measures), 1)
        shared.current_evidence.assert_not_called()

    def test_budget_stops_before_next_lane(self):
        result, calls, measures, _ = self.run_consumer(["--only", "iphone,ipad", "--budget-min", "1"], expires=True)
        self.assertEqual(result, 75)
        self.assertEqual(len(measures), 1)
        self.assertIn("stop", calls[-1])
        result, calls, _, _ = self.run_consumer(["--budget-min", "0"])
        self.assertEqual(result, 75)
        self.assertEqual(calls, [])

    def test_receipts_require_one_lane_and_pass_through(self):
        result, _, measures, _ = self.run_consumer(["--only", "ipad", "--reuse-size-build", "release.json",
                                                   "--reuse-runtime-build", "runtime.json"])
        self.assertEqual(result, 0)
        self.assertIn("release.json", measures[0])
        self.assertIn("runtime.json", measures[0])
        with self.assertRaises(SystemExit) as error, contextlib.redirect_stderr(io.StringIO()):
            consumer.main(["--only", "iphone,ipad", "--reuse-size-build", "release.json"])
        self.assertEqual(error.exception.code, 2)

    def test_watch_fixture_contract(self):
        result, _, measures, _ = self.run_consumer(["--only", "watch"])
        self.assertEqual(result, 0)
        args = measures[0]
        if consumer.APP_ID == "fitcoach-ios":
            self.assertFalse(any(arg.startswith("--launch-arg=") for arg in args))
        else:
            self.assertIn("--launch-arg=-api_base", args)
            self.assertIn("--warmup-arg=-dev_user", args)
            self.assertIn("--warmup-arg=-dev_pw", args)
            self.assertNotIn("--launch-arg=-dev_user", args)
            self.assertNotIn("--launch-arg=-dev_pw", args)


if __name__ == "__main__":
    unittest.main()
