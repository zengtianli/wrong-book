#!/usr/bin/env python3
"""Real stdlib CLI transport against a loopback contract fixture; never sends SMS."""
import json
import os
import subprocess
import sys
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

CLI = Path(__file__).resolve().parents[1] / "cli/mistakes"


class Handler(BaseHTTPRequestHandler):
    calls = []
    bound = False
    has_password = True
    fail_send = False

    def log_message(self, *_):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))) or b"{}")
        self.reply(body)

    def do_GET(self):
        self.reply({})

    def reply(self, body):
        type(self).calls.append((self.path, body))
        result = {"ok": True}
        status = 200
        if self.path == "/api/phone_send":
            result.update(challenge="fixture-challenge")
            if self.fail_send:
                result = {"ok": False, "err": "发送结果未知"}
                status = 503
        elif self.path in ("/api/phone_verify", "/api/email_verify"):
            result.update(grant="fixture-grant")
        elif self.path == "/api/email_send":
            result.update(challenge="fixture-email")
        elif self.path == "/api/me":
            result.update(u="original-account", phone="+8613900000001" if self.bound else "",
                          phone_verified=self.bound, has_password=self.has_password)
        elif self.path in ("/api/phone_login", "/api/phone_register"):
            result.update(u="original-account", has_password=self.has_password)
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(result).encode())


class PhoneCLI(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self):
        Handler.calls = []
        Handler.bound = False
        Handler.has_password = True
        Handler.fail_send = False

    def run_cli(self, args, *, authenticated=False, stdin="", **extra):
        env = {k: v for k, v in os.environ.items() if not k.startswith("EDU_")}
        env.update(EDU_SMS_CODE="123456", EDU_SMS_OLD_CODE="654321", EDU_SMS_IDENTITY_CODE="112233",
                   EDU_NEW_PASSWORD="fixture new long password", EDU_EMAIL_CODE="556677", **extra)
        if authenticated:
            env.update(EDU_USER="original-account", EDU_PASSWORD="fixture old long password")
        r = subprocess.run([sys.executable, str(CLI), "--api", f"http://127.0.0.1:{self.server.server_port}",
                            *args, "--json"], env=env, input=stdin, text=True, capture_output=True, timeout=5)
        # Secrets may exist only in transport, never CLI output/errors.
        self.assertNotIn("fixture new long password", r.stdout + r.stderr)
        self.assertNotIn("fixture old long password", r.stdout + r.stderr)
        self.assertNotIn("fixture-grant", r.stdout + r.stderr)
        return r.returncode, json.loads(r.stdout)

    def test_login_without_password(self):
        code, out = self.run_cli(["account", "phone-login", "--phone", "13900000001", "--request-id", "fixture-stable-login-request"])
        self.assertEqual(code, 0)
        self.assertEqual(out["u"], "original-account")
        self.assertEqual(Handler.calls[0][1]["request_id"], "fixture-stable-login-request")
        self.assertEqual([p for p, _ in Handler.calls], ["/api/phone_send", "/api/phone_verify", "/api/phone_login"])

    def test_registration_requires_agreement_before_send(self):
        code, _ = self.run_cli(["account", "phone-register", "--phone", "13900000001"])
        self.assertEqual(code, 2)
        self.assertEqual(Handler.calls, [])

    def test_registration_verified(self):
        code, _ = self.run_cli(["account", "phone-register", "--phone", "13900000001", "--agreed"])
        self.assertEqual(code, 0)
        self.assertTrue(Handler.calls[-1][1]["agreed"])
        self.assertEqual(Handler.calls[0][1]["purpose"], "register")

    def test_recovery_and_independent_email(self):
        code, _ = self.run_cli(["account", "phone-recover", "--phone", "13900000001", "--risk-email", "fixture@example.test"])
        self.assertEqual(code, 0)
        self.assertEqual(Handler.calls[-1][0], "/api/phone_recover")
        self.assertIn("email_grant", Handler.calls[-1][1])
        self.assertEqual(Handler.calls[0][1]["purpose"], "phone_recover")

    def test_bind_keeps_original_password_session(self):
        code, _ = self.run_cli(["account", "phone-bind", "--phone", "13900000002"], authenticated=True)
        self.assertEqual(code, 0)
        self.assertEqual(Handler.calls[0][0], "/api/login")
        self.assertEqual([b["purpose"] for p, b in Handler.calls if p == "/api/phone_send"], ["phone_new"])
        self.assertNotIn("/api/phone_register", [p for p, _ in Handler.calls])

    def test_change_confirms_both_numbers(self):
        Handler.bound = True
        code, _ = self.run_cli(["account", "phone-bind", "--phone", "13900000002"], authenticated=True)
        self.assertEqual(code, 0)
        self.assertEqual([b["purpose"] for p, b in Handler.calls if p == "/api/phone_send"], ["phone_change_new", "phone_old"])
        self.assertTrue(Handler.calls[-1][1]["old_grant"])

    def test_passwordless_phone_session_and_set(self):
        Handler.bound = True
        Handler.has_password = False
        code, _ = self.run_cli(["--sms-phone", "13900000001", "account", "password-set"])
        self.assertEqual(code, 0)
        self.assertNotIn("/api/login", [p for p, _ in Handler.calls])
        self.assertEqual(Handler.calls[-1][0], "/api/password_set")
        self.assertIn("identity_grant", Handler.calls[-1][1])

    def test_unknown_send_preserves_request_id_and_does_not_retry(self):
        Handler.fail_send = True
        code, out = self.run_cli(["account", "phone-login", "--phone", "13900000001", "--request-id", "fixture-resume-request"])
        self.assertEqual(code, 1)
        self.assertEqual(out["request_id"], "fixture-resume-request")
        self.assertEqual(len(Handler.calls), 1)

    def test_global_sms_session_failure_also_returns_request_id(self):
        Handler.fail_send = True
        code, out = self.run_cli(["--sms-phone", "13900000001", "account", "password-set"])
        self.assertEqual(code, 1)
        self.assertEqual(out["request_id"], Handler.calls[0][1]["request_id"])
        self.assertEqual(len(Handler.calls), 1)


if __name__ == "__main__":
    unittest.main()
