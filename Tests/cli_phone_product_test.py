#!/usr/bin/env python3
"""Run the shipped CLI against the real isolated education HTTP service.

Only PNVS and mail transport are test doubles. Account persistence, sessions,
challenges, learning archives and entitlement projections are production code.
No production account or real SMS is touched; never counts as sms_transport=real.
Set MISTAKES_CLI to validate an installed app's bundled CLI rather than source.
"""
from contextlib import closing, redirect_stdout, redirect_stderr
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
SERVER = Path(os.environ.get("EDU_SERVER_PY") or REPO.parents[2] / "web/points/server.py")
CLI = Path(os.environ.get("MISTAKES_CLI") or REPO / "cli/mistakes").resolve()
sys.path.insert(0, str(SERVER.parent))
import account_phone
import ai_access
from test_phone_account import FakePNVS
from test_treasury_prd import Client, TreasuryPRD


class ProductPhoneCLI(unittest.TestCase):
    def setUp(self):
        self.fixture = TreasuryPRD(methodName="test_registration_requires_verified_email_and_replays_one_account")
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            self.fixture.setUp()
        self.gateway = FakePNVS()
        self.provider = patch.object(account_phone, "gateway", return_value=self.gateway)
        self.provider.start()
        self.log_mute = patch.object(self.fixture.server.H, "log_message", lambda *_: None)
        self.log_mute.start()
        self.service = account_phone.PhoneChallenges(self.fixture.server.HOME, self.fixture.server.load_cfg()["secret"])

    def tearDown(self):
        self.log_mute.stop()
        self.provider.stop()
        self.fixture.tearDown()

    def clear_resend(self, *numbers):
        with closing(self.service.connect()) as db, db:
            for number in numbers:
                db.execute("DELETE FROM hits WHERE bucket=?", ("sms-resend:" + self.service.digest(account_phone.phone(number)),))

    def run_cli(self, args, *, account=None, new_password="a separate SMS CLI passphrase", code="246810"):
        env = {key: value for key, value in os.environ.items() if not key.startswith(("EDU_", "ALIYUN_", "ALIBABA_CLOUD_"))}
        env.update(EDU_API_BASE=self.fixture.base, EDU_SMS_CODE=code, EDU_SMS_OLD_CODE="246810",
                   EDU_SMS_IDENTITY_CODE="246810", EDU_NEW_PASSWORD=new_password)
        if account:
            env.update(EDU_USER=account[0], EDU_PASSWORD=account[1])
        result = subprocess.run([str(CLI), *args, "--json"], env=env, input="", text=True,
                                capture_output=True, timeout=15)
        self.assertNotIn(new_password, result.stdout + result.stderr)
        if account:
            self.assertNotIn(account[1], result.stdout + result.stderr)
        return result.returncode, json.loads(result.stdout or "{}")

    def succeed(self, args, **kwargs):
        code, response = self.run_cli(args, **kwargs)
        self.assertEqual(code, 0, response.get("err"))
        return response

    def ok_http(self, client, path, body=None):
        status, response = client.call(path, body)
        self.assertEqual(status, 200, response.get("err"))
        return response

    def test_register_then_set_password_keeps_account_instance(self):
        number = "13800000000"
        registered = self.succeed(["account", "phone-register", "--phone", number, "--agreed"])
        self.assertFalse(registered["has_password"])
        record = self.fixture.server.load_users()["users"][registered["u"]]
        instance = record["account_instance"]
        self.clear_resend(number)
        # The real server enforces resend between SMS login and identity verification;
        # scope the timing override to this isolated service, never product configuration.
        with patch.object(account_phone, "RESEND_SECONDS", 0):
            self.succeed(["--sms-phone", number, "account", "password-set"])
        status = self.succeed(["status"], account=(number, "a separate SMS CLI passphrase"))
        self.assertEqual(status["user"], registered["u"])
        self.assertEqual(self.fixture.server.load_users()["users"][registered["u"]]["account_instance"], instance)

    def test_existing_account_bind_swap_preserves_archive_trial_and_subscription(self):
        family = ("family", "old-short")
        server = self.fixture.server
        users = server.load_users()
        record = users["users"]["family"]
        record.setdefault("account_instance", "4" * 64)
        record["ai_trial_used"] = 3
        record["apple_transactions"] = {"synthetic-transaction": {
            "product_id": sorted(ai_access.PRODUCTS)[0], "expires": int(time.time() * 1000) + 86400000}}
        server.save_users(users)
        archive = {"edu:sms-preservation": json.dumps({"done": 7, "wrong": [{"gid": "synthetic-gid", "wrong": 2}]})}
        self.ok_http(self.fixture.client, "archive", {"data": archive})
        before = self.ok_http(self.fixture.client, "ai_access")
        instance = record["account_instance"]
        self.succeed(["account", "phone-bind", "--phone", "13800000000"], account=family)
        self.assertEqual(self.fixture.client.call("state")[0], 401)
        self.clear_resend("13800000000", "13900000000")
        self.succeed(["account", "phone-bind", "--phone", "13900000000"], account=family)
        current = Client(self.fixture.base)
        self.ok_http(current, "login", {"u": "13900000000", "p": family[1]})
        after = self.ok_http(current, "ai_access")
        self.assertEqual(self.ok_http(current, "me")["u"], "family")
        self.assertEqual(self.ok_http(current, "archive")["data"], archive)
        self.assertEqual(server.load_users()["users"]["family"]["account_instance"], instance)
        self.assertEqual((after["remaining"], after["subscribed"], after["app_account_token"]),
                         (before["remaining"], before["subscribed"], before["app_account_token"]))
        self.assertIsNone(account_phone.find(server.load_users(), "+8613800000000"))

    def test_phone_recovery_revokes_old_session_and_retains_learning_archive(self):
        number = "13800000000"
        self.succeed(["account", "phone-bind", "--phone", number], account=("family", "old-short"))
        original = Client(self.fixture.base)
        self.ok_http(original, "login", {"u": "family", "p": "old-short"})
        archive = {"edu:recovery-preservation": json.dumps({"done": 4})}
        self.ok_http(original, "archive", {"data": archive})
        self.clear_resend(number)
        self.succeed(["account", "phone-recover", "--phone", number], account=("family", "old-short"))
        self.assertEqual(original.call("state")[0], 401)
        restored = Client(self.fixture.base)
        self.ok_http(restored, "login", {"u": number, "p": "a separate SMS CLI passphrase"})
        self.assertEqual(self.ok_http(restored, "me")["u"], "family")
        self.assertEqual(self.ok_http(restored, "archive")["data"], archive)

    def test_wrong_code_never_creates_an_account(self):
        before = len(self.fixture.server.load_users()["users"])
        code, _ = self.run_cli(["account", "phone-register", "--phone", "13800000000", "--agreed"], code="000000")
        self.assertEqual(code, 1)
        self.assertEqual(len(self.fixture.server.load_users()["users"]), before)

    def test_unknown_send_resume_does_not_send_again(self):
        self.gateway.unknown = True
        arguments = ["account", "phone-login", "--phone", "13800000000", "--request-id", "product-unknown-request-01"]
        for _ in range(2):
            code, response = self.run_cli(arguments)
            self.assertEqual(code, 1)
            self.assertEqual(response["request_id"], "product-unknown-request-01")
        self.assertEqual(self.gateway.calls, 1)

    def test_bound_number_collision_does_not_merge_accounts(self):
        registered = self.succeed(["account", "phone-register", "--phone", "13800000000", "--agreed"])
        self.clear_resend("13800000000")
        code, _ = self.run_cli(["account", "phone-bind", "--phone", "13800000000"], account=("family", "old-short"))
        self.assertEqual(code, 1)
        self.assertEqual(account_phone.find(self.fixture.server.load_users(), "+8613800000000"), registered["u"])
        self.assertEqual(len(self.fixture.server.load_users()["users"]), 2)


if __name__ == "__main__":
    unittest.main(defaultTest="ProductPhoneCLI")
