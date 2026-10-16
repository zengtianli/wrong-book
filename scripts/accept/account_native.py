#!/usr/bin/env python3
"""Actual iOS account producer, isolated production backend, no synthetic input.

--build creates a source-bound candidate using sim_lane's build slots.
--produce runs four fresh product processes in an owned, hidden simulator.
Only five exercised cases can pass; the other twelve and real mail/SMS remain
missing. This deliberately cannot turn fixture provisioning into registration.
"""
from __future__ import annotations
import argparse
import contextlib
import datetime as dt
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import secrets
import signal
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
from http.cookiejar import CookieJar

ROOT = Path(__file__).resolve().parents[2]
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path.home() / "Dev/tools/dev/lib/tools/macapp/ios"))
sys.path.insert(0, str(Path.home() / "Apps/chapter/engine"))
import sim_lane
import sim_admission
import app_sop

PHASES = ("exercise", "restore", "logged-out", "delete")
CASE_CHECKS = {
    "login": {"exercise": ("login.wrong_password_refused", "login.native_session"),
              "restore": ("login.fresh_process_cookie_restore",)},
    "password_change": {"exercise": ("password_change.wrong_old_refused", "password_change.identity_preserved",
        "password_change.old_password_revoked", "password_change.new_password_login")},
    "logout": {"restore": ("logout.native_cleared",), "logged-out": ("logout.fresh_process_denied",)},
    "account_deletion": {"delete": ("account_deletion.login", "account_deletion.wrong_password_refused",
        "account_deletion.completed", "account_deletion.cannot_login")},
    "data_preservation": {"exercise": ("data_preservation.fixture_present", "data_preservation.after_password_change"),
                          "restore": ("data_preservation.fresh_process",)},
}

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def artifacts(app):
    return {str(path.relative_to(app)): sha(path) for path in sorted(app.rglob("*"))
            if path.is_file() and not path.is_symlink()}

def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(".tmp")
    temp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    temp.chmod(0o600)
    temp.replace(path)

def cases_from_raw(raw):
    """Never credit missing/false checks or same-process 'restarts'."""
    pids = [raw.get(phase, {}).get("pid") for phase in PHASES]
    if any(not isinstance(pid, int) or pid <= 0 for pid in pids) or len(set(pids)) != len(PHASES):
        return []
    if any(row.get("failure_class") is not None or row.get("checks", {}).get("native.login_view_offscreen") is not True
           for row in raw.values()):
        return []
    return [case for case, phases in CASE_CHECKS.items()
            if all(raw.get(phase, {}).get("checks", {}).get(check) is True
                   for phase, checks in phases.items() for check in checks)]

@contextlib.contextmanager
def service():
    """Production handler/auth/storage, temporary data home, no mail/SMS mocks.

    A synthetic password user is provisioned as test INPUT, not registration
    evidence. No transport, security policy or handler is replaced.
    """
    backend = Path.home() / "Apps/edu/web/points"
    saved = dict(os.environ)
    with tempfile.TemporaryDirectory(prefix="wrongbook-account-service-") as home:
        old, new = secrets.token_urlsafe(24), secrets.token_urlsafe(24)
        os.environ.update(EDU_POINTS_HOME=home, EDU_POINTS_PORT="0", EDU_KID_USER="qa_owner",
                          EDU_KID_PW=secrets.token_urlsafe(24), EDU_PARENT_PW=secrets.token_urlsafe(24))
        # This no-message lane must not accidentally inherit production senders.
        for key in tuple(os.environ):
            if key.startswith(("EDU_SMTP_", "ALIYUN_", "EDU_SMS_")):
                os.environ.pop(key)
        http = worker = None
        try:
            sys.path.insert(0, str(backend))
            spec = importlib.util.spec_from_file_location("wrongbook_account_backend", backend / "server.py")
            product = importlib.util.module_from_spec(spec)
            sys.modules[spec.name] = product
            with contextlib.redirect_stdout(io.StringIO()):
                spec.loader.exec_module(product)
                assert product.cmd_init([]) == 0
            user, salt = "qa_wrongbook", secrets.token_hex(8)
            users = product.load_users()
            users["users"][user] = {"nick": "隔离错题测试", "email": "", "email_verified": False,
                "site_admin": False, "salt": salt, "hash": product.hash_pw(old, salt), "password_set": True,
                "pwv": 1, "created": product.now().isoformat(), "has_scan_history": False,
                "account_instance": secrets.token_hex(32)}
            product.save_users(users)
            owner_file = product.ledger_path("qa_owner")
            owner_before = sha(owner_file)
            events = []
            class Observed(product.H):
                def log_message(self, *_): pass
                def _json(self, status, obj, cookie=None):
                    events.append({"path": self.path.split("?")[0], "status": status})
                    return super()._json(status, obj, cookie)
            http = product.ThreadingHTTPServer(("127.0.0.1", 0), Observed)
            worker = threading.Thread(target=http.serve_forever, daemon=True); worker.start()
            base = "http://127.0.0.1:" + str(http.server_port)
            opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(CookieJar()))
            def post(path, body):
                req = urllib.request.Request(base + "/api/" + path, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
                with opener.open(req, timeout=15) as response:
                    assert json.load(response)["ok"] is True
            post("login", {"u": user, "p": old})
            marker = "fictional-review-progress-" + secrets.token_hex(6)
            post("archive", {"data": {"edu:wrongbook-account-qa": marker}})
            events.clear()  # input setup is explicitly excluded from native events
            yield {"url": base, "user": user, "old": old, "new": new, "archive": marker}, product, events, owner_file, owner_before
        finally:
            if http: http.shutdown(); http.server_close()
            if worker: worker.join(timeout=3)
            os.environ.clear(); os.environ.update(saved)

def produce(receipt, run, binding):
    build = sim_lane.reuse_build(receipt, "wrong-book-ios", ROOT, "iphone", "WrongBook", "Debug")
    candidate = Path(build["app_path"])
    if not build.get("product_artifacts") or artifacts(candidate) != build["product_artifacts"]:
        raise RuntimeError("Whole candidate package, including Debug dylib, must match its receipt")
    report = {"account_input_sha256": binding, "candidate": True, "phone_installed": False,
              "producer_sha256": sha(Path(__file__)),
              "receipt": str(receipt.relative_to(ROOT)), "receipt_sha256": sha(receipt), "steps": {},
              "messages_sent": {"email": 0, "sms": 0}, "mail_transport": "not_exercised", "sms_transport": "not_exercised"}
    write(run / "attempt.json", report)
    report["admission"] = sim_admission.admit(sim_lane, reuse=False, label="wrong-book native account")
    write(run / "attempt.json", report)
    device = sim_lane.ensure_device("iphone", device_type="iPhone-17-Pro", name="WrongBook Account QA")
    with sim_admission.hooked(sim_lane, run_record=str(run / "simulator-run.json"), label="wrong-book native account"), \
            sim_lane.Session("iphone", device["udid"], label="wrong-book native account", lock_wait=0, load_wait=0) as lane:
        lane.install(candidate)
        info = sim_lane.bundle_info(candidate)
        installed = Path(sim_lane.simctl("get_app_container", device["udid"], info["bundle_id"], "app").stdout.strip())
        if artifacts(installed) != build["product_artifacts"]:
            raise RuntimeError("Installed simulator package differs from candidate/receipt")
        container = Path(sim_lane.simctl("get_app_container", device["udid"], info["bundle_id"], "data").stdout.strip())
        private = container / "tmp" / ("account-" + secrets.token_hex(8)); private.mkdir(mode=0o700)
        try:
            with service() as (plan, product, events, owner_file, owner_before):
                for phase in PHASES:
                    plan["phase"] = phase
                    write(private / "plan.json", plan)
                    output = private / (phase + ".json")
                    child = dict(os.environ, SIMCTL_CHILD_WRONGBOOK_ACCOUNT_PLAN=str(private / "plan.json"),
                        SIMCTL_CHILD_WRONGBOOK_ACCOUNT_OUTPUT=str(output), SIMCTL_CHILD_WRONGBOOK_ACCOUNT_BINDING=binding)
                    result = sim_lane.run(["xcrun", "simctl", "launch", "--terminate-running-process", device["udid"],
                        info["bundle_id"], "--account-self-test", "-api_base", plan["url"]], timeout=30, check=False, env=child, sdk="iphonesimulator")
                    if result.returncode: raise RuntimeError("Native launch failed (no credentials in arguments)")
                    deadline = time.monotonic() + 75
                    while not output.is_file() and time.monotonic() < deadline: time.sleep(.1)
                    if not output.is_file(): raise RuntimeError("Native " + phase + " produced no original output within 75s")
                    raw = json.loads(output.read_text())
                    if raw.get("account_input_sha256") != binding or raw.get("phase") != phase:
                        raise RuntimeError("Native report binding/phase mismatch")
                    report["steps"][phase] = raw
                    shutil.copy2(output, run / output.name)
                    shutil.copy2(private / ("login-" + phase + ".png"), run / ("login-" + phase + ".png"))
                    lane.terminate(info["bundle_id"])
                    if raw.get("failure_class") is not None or any(v is not True for v in raw.get("checks", {}).values()):
                        raise RuntimeError("Native assertions failed in " + phase)
                    if sha(owner_file) != owner_before: raise RuntimeError("Unrelated isolated owner ledger changed")
                report["service_checks"] = {"deleted_user_absent": plan["user"] not in product.load_users()["users"],
                    "deleted_profile_absent": not (product.PROFILES / (plan["user"] + ".json")).exists(),
                    "unrelated_owner_unchanged": sha(owner_file) == owner_before}
                report["service_events"] = events
                report["service_sources"] = {name: sha(Path.home() / "Apps/edu/web/points" / name)
                    for name in ("server.py", "account_security.py", "account_phone.py", "account_deletions.py")}
                if not all(report["service_checks"].values()): raise RuntimeError("Production service postconditions failed")
        finally:
            lane.terminate(info["bundle_id"])
            shutil.rmtree(private)
    report["device"] = device
    report["simulator_shutdown"] = device["udid"] not in sim_lane.booted_udids()
    write(run / "raw.json", report)
    cases = cases_from_raw(report["steps"]) if report["simulator_shutdown"] else []
    if set(cases) != set(CASE_CHECKS): raise RuntimeError("Native five-case report incomplete")
    proof = run / "raw.json"
    index = {"account_input_sha256": binding, "client_environment": "Actual Debug iOS product in hidden iPhone 17 Pro simulator; source-bound candidate, not phone installation",
        "service_environment": "Unmodified education production HTTP handler/auth/storage; temporary data home; synthetic pre-provisioned password user",
        "mail_transport": "not_exercised", "sms_transport": "not_exercised", "account_cases": {
            case: {"status": "passed", "evidence": str(proof.relative_to(ROOT)), "evidence_sha256": sha(proof)} for case in cases},
        "scope": "Only five no-message native cases; registration, recovery, abuse protection and real email/phone lifecycle remain missing"}
    target = ROOT / "perf/account/account-lifecycle.json"
    if target.exists(): shutil.copy2(target, run / "previous-index.json")
    write(target, index)
    return index

def main():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", action="store_true")
    parser.add_argument("--produce", action="store_true")
    parser.add_argument("--receipt", type=Path, default=ROOT / "perf/account/native-build.json")
    args = parser.parse_args()
    receipt = args.receipt.resolve(); receipt.relative_to(ROOT / "perf/account")
    if args.build:
        result = subprocess.run([sys.executable, str(Path(sim_admission.__file__)), "build", str(Path(sim_lane.__file__)),
            "build", "--project-dir", str(ROOT), "--scheme", "WrongBook", "--platform", "iphone",
            "--configuration", "Debug", "--json"], capture_output=True, text=True, timeout=660)
        if result.returncode == 75:
            print(result.stdout.strip()); return 75
        if result.returncode:
            print("Original shared build failed; no account evidence was produced"); return result.returncode
        built = json.loads(result.stdout)
        built["product_artifacts"] = artifacts(Path(built["app_path"]))
        write(receipt, built)
        print(json.dumps({"receipt": str(receipt), "app_path": built["app_path"]})); return 0
    if not args.produce: parser.error("choose --build or --produce")
    app = app_sop.load_apps("wrong-book-ios")[0]
    binding = app_sop.monitor_inputs(app, {})["bindings"]["account"]
    previous = ROOT / "perf/account/account-lifecycle.json"
    if previous.is_file():
        index = json.loads(previous.read_text())
        if index.get("account_input_sha256") == binding:
            cases = index.get("account_cases", {})
            verified = all(case in cases and cases[case].get("status") == "passed"
                and (ROOT / cases[case]["evidence"]).resolve().is_relative_to(ROOT / "perf/account")
                and sha(ROOT / cases[case]["evidence"]) == cases[case].get("evidence_sha256") for case in CASE_CHECKS)
            if verified:
                proof = json.loads((ROOT / cases["login"]["evidence"]).read_text())
                if proof.get("producer_sha256") == sha(Path(__file__)) and set(cases_from_raw(proof.get("steps", {}))) == set(CASE_CHECKS):
                    print("Reused current five-case native originals; missing live-channel cases remain pending")
                    return 0
    if not receipt.is_file(): print("Missing current iOS candidate; run scripts/accept/account_native.py --build"); return 75
    for failure in (ROOT / "perf/account").glob("native-*/failed.json"):
        prior = json.loads(failure.read_text())
        if prior.get("account_input_sha256") == binding and prior.get("producer_sha256") == sha(Path(__file__)):
            print("Same native failure already recorded; repair the original before retry: " + str(failure.relative_to(ROOT)))
            return 1
    run = ROOT / "perf/account" / ("native-" + dt.datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + secrets.token_hex(3))
    run.mkdir(parents=True)
    try:
        index = produce(receipt, run, binding)
        # The strict fixed consumer still reports all twelve missing live cases.
        print("Actual native cases: " + ", ".join(index["account_cases"]))
        return 0
    except sim_lane.Busy as exc:
        write(run / "deferred.json", {"exit_code": 75, "reason": str(exc), "account_input_sha256": binding,
            "next_attempt_at": (dt.datetime.now().astimezone() + dt.timedelta(minutes=10)).isoformat()})
        print("Deferred by original simulator queue: " + str(exc)); return 75
    except Exception as exc:
        write(run / "failed.json", {"exit_code": 1, "error_class": type(exc).__name__, "account_input_sha256": binding,
            "producer_sha256": sha(Path(__file__))})
        print("Native account failed: " + type(exc).__name__); return 1

if __name__ == "__main__":
    raise SystemExit(main())
