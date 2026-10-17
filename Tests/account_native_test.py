"""Reject incomplete/native-identity substitutions; exercise real isolated service."""
import importlib.util
from pathlib import Path
import urllib.error
import urllib.request
import json
import sys
from types import SimpleNamespace

import pytest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("account_native", ROOT / "scripts/accept/account_native.py")
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


def completed():
    raw = {phase: {"pid": index + 100, "failure_class": None, "checks": {"native.login_view_offscreen": True}}
           for index, phase in enumerate(native.PHASES)}
    for phases in native.CASE_CHECKS.values():
        for phase, checks in phases.items():
            raw[phase]["checks"].update({check: True for check in checks})
    return raw


def test_missing_or_false_assertion_cannot_credit_case():
    raw = completed()
    del raw["restore"]["checks"]["login.fresh_process_cookie_restore"]
    assert "login" not in native.cases_from_raw(raw)
    raw["exercise"]["checks"]["password_change.old_password_revoked"] = False
    assert "password_change" not in native.cases_from_raw(raw)


def test_same_process_is_not_a_relaunch_and_empty_ok_is_not_evidence():
    raw = completed()
    raw["restore"]["pid"] = raw["exercise"]["pid"]
    assert native.cases_from_raw(raw) == []
    assert native.cases_from_raw({"ok": True}) == []


def test_no_channel_or_registration_credit_from_password_seed():
    assert set(native.cases_from_raw(completed())) == {"login", "password_change", "logout", "account_deletion", "data_preservation"}


def test_mail_cases_require_actual_native_assertions():
    raw = completed()
    raw['live-mail'] = {'pid': 200, 'failure_class': None, 'checks': {'native.login_view_offscreen': True}}
    for checks in native.MAIL_CASE_CHECKS.values():
        raw['live-mail']['checks'].update({name: True for name in checks})
    assert set(native.cases_from_raw(raw)) == set(native.CASE_CHECKS) | set(native.MAIL_CASE_CHECKS)
    del raw['live-mail']['checks']['registration.real_mail_native_session']
    assert 'registration' not in native.cases_from_raw(raw)
    raw['live-mail']['pid'] = raw['exercise']['pid']
    assert native.cases_from_raw(raw) == []


def test_phone_fixture_cannot_credit_carrier_delivery():
    raw = completed()
    raw['phone-fixture'] = {'pid': 250, 'failure_class': None, 'checks': {'native.login_view_offscreen': True}}
    for checks in native.PHONE_CASE_CHECKS.values():
        raw['phone-fixture']['checks'].update({name: True for name in checks})
    cases = native.cases_from_raw(raw)
    assert set(native.PHONE_CASE_CHECKS) <= set(cases)
    assert 'sms_delivery' not in cases
    del raw['phone-fixture']['checks']['phone_change.old_ownership_required']
    assert 'phone_change' not in native.cases_from_raw(raw)


def test_phone_fixture_refuses_nonfixture_phone_and_wrong_scope():
    sys.path.insert(0, str(ROOT / 'scripts/accept'))
    from account_phone_fixture import PhoneFixture
    import pytest
    fixture = PhoneFixture()
    with pytest.raises(RuntimeError): fixture.send('13600000000', 'register', 'challenge')
    fixture.send('+8613800000000', 'register', 'challenge')
    code = fixture.requests['challenge'][2]
    assert fixture.check('+8613800000000', 'register', 'challenge', code)
    assert not fixture.check('+8613900000000', 'register', 'challenge', code)
    assert not fixture.check('+8613800000000', 'login', 'challenge', code)


def test_mail_receiver_does_not_accept_another_recipient_or_an_old_status():
    sys.path.insert(0, str(ROOT / 'scripts/accept'))
    from account_mail import received_code, RealMail
    from email.message import EmailMessage
    message = EmailMessage()
    message['To'] = 'owned+test@example.test'; message['Message-ID'] = '<isolated-test@example.test>'
    message.set_content('本次验证码：246810\n仅供隔离测试')
    assert received_code(message.as_bytes(), 'another@example.test') is None
    assert received_code(message.as_bytes(), 'owned+test@example.test')[0] == '246810'
    message.replace_header('To', 'prefixowned+test@example.test')
    assert received_code(message.as_bytes(), 'owned+test@example.test') is None
    proof = RealMail.__new__(RealMail)
    proof.accepted = 6; proof.events = [{'kind': 'smtp_accepted'}] * 6
    assert not proof.complete()
    proof.events = [{'kind': 'imap_received', 'recipient_sha256': str(index % 4)} for index in range(6)]
    assert proof.complete()


def test_unattached_view_and_native_failure_are_required():
    raw = completed()
    raw["delete"]["checks"]["native.login_view_offscreen"] = False
    assert native.cases_from_raw(raw) == []


def test_blank_native_render_is_rejected(tmp_path):
    from PIL import Image, ImageDraw
    path = tmp_path / "native.png"
    Image.new("RGB", (390, 844), "white").save(path)
    assert native.view_evidence(path)["drawn"] is False
    image = Image.new("RGB", (390, 844), "white")
    draw = ImageDraw.Draw(image)
    for index in range(100):
        draw.line((20, 100 + index, 300, 100 + index), fill=(index, index, index))
    image.save(path)
    assert native.view_evidence(path)["drawn"] is True
    raw = completed(); raw["exercise"]["failure_class"] = "TransportError"
    assert native.cases_from_raw(raw) == []


def test_production_service_is_isolated_no_messages_and_actual_auth_storage():
    from http.cookiejar import CookieJar
    with native.service() as (plan, server, events, owner, owner_before):
        assert server.HOME != Path.home()
        assert server.HOME.name.startswith("wrongbook-account-service-")
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(CookieJar()))
        def call(path, body=None):
            request = urllib.request.Request(plan["url"] + "/api/" + path,
                data=json.dumps(body).encode() if body is not None else None,
                headers={"Content-Type": "application/json"})
            try: response = opener.open(request, timeout=15)
            except urllib.error.HTTPError as error: response = error
            with response: return response.status, json.load(response)
        assert call("login", {"u": plan["user"], "p": "bad"})[0] == 401
        assert call("login", {"u": plan["user"], "p": plan["old"]})[0] == 200
        assert call("archive")[1]["data"]["edu:wrongbook-account-qa"] == plan["archive"]
        assert call("passwd", {"old": plan["old"], "new": plan["new"]})[0] == 200
        assert call("account_del", {"p": plan["new"]})[0] == 200
        assert plan["user"] not in server.load_users()["users"]
        assert native.sha(owner) == owner_before
        assert events[-1] == {"path": "/api/account_del", "status": 200}
        assert not any("send" in event["path"] for event in events)


@pytest.fixture
def candidate_queue(tmp_path, monkeypatch):
    """Exercise the fixed entry point without building or touching a device."""
    monkeypatch.setattr(native, "ROOT", tmp_path)
    monkeypatch.setattr(sys, "argv", ["account_native.py", "--produce"])
    monkeypatch.setattr(native.app_sop, "load_apps", lambda *_: [{}])
    monkeypatch.setattr(native.app_sop, "monitor_inputs", lambda *_: {"bindings": {"account": "qa-binding"}})
    app = tmp_path / "candidate/WrongBook.app"
    app.mkdir(parents=True)
    (app / "WrongBook").write_bytes(b"qa executable")
    (app / "WrongBook.debug.dylib").write_bytes(b"qa native implementation")
    built = {"ok": True, "app_path": str(app), "xcode": {"build": "qa-current"}}
    receipt = tmp_path / "perf/account/native-build.json"
    native.write(receipt, {**built, "xcode": {"build": "qa-cache"}, "product_artifacts": native.artifacts(app)})
    queue = SimpleNamespace(receipt=receipt, app=app, reuse_errors=[], builds=[], flows=[],
        result=SimpleNamespace(returncode=0, stdout=json.dumps(built)))

    def reuse(path, *args):
        assert args == ("wrong-book-ios", tmp_path, "iphone", "WrongBook", "Debug")
        if queue.reuse_errors:
            raise queue.reuse_errors.pop(0)
        try:
            return json.loads(path.read_text())
        except FileNotFoundError as exc:
            raise native.sim_lane.LaneError("缓存构建无法核验：missing receipt") from exc

    def build(command, **kwargs):
        queue.builds.append(command)
        return queue.result

    def produce(*args):
        # The actual producer also rechecks immediately before device admission.
        native.verified_candidate(args[0])
        queue.flows.append(args)
        return {"account_cases": dict.fromkeys(native.CASE_CHECKS)}

    monkeypatch.setattr(native.sim_lane, "reuse_build", reuse)
    monkeypatch.setattr(native.subprocess, "run", build)
    monkeypatch.setattr(native, "produce", produce)
    return queue


@pytest.mark.parametrize("cache", ["missing", "缓存构建的 Xcode 与当前工具链不同", "缓存构建源码与当前平台输入不同"])
def test_fixed_producer_refreshes_invalid_cache_before_old_failure_guard(candidate_queue, cache):
    queue = candidate_queue
    old_digest = native.sha(queue.receipt)
    if cache == "missing":
        queue.receipt.unlink()
    else:
        queue.reuse_errors.append(native.sim_lane.LaneError(cache))
    prior = queue.receipt.parent / "native-old/failed.json"
    native.write(prior, {"account_input_sha256": "qa-binding", "producer_sha256": native.producer_digest(),
                         "candidate_receipt_sha256": old_digest})
    assert native.main() == 0
    assert len(queue.builds) == len(queue.flows) == 1
    assert queue.builds[0][:5] == [sys.executable, str(Path(native.sim_admission.__file__)), "build",
                                  str(Path(native.sim_lane.__file__)), "build"]
    assert json.loads(queue.receipt.read_text())["product_artifacts"] == native.artifacts(queue.app)
    assert native.sha(queue.receipt) != old_digest
    assert prior.is_file()
    assert not list(queue.receipt.parent.glob("native-*/deferred.json"))


def test_current_candidate_reused_but_identical_failed_candidate_not_retried(candidate_queue):
    queue = candidate_queue
    assert native.main() == 0
    native.write(queue.receipt.parent / "native-old/failed.json", {
        "account_input_sha256": "qa-binding", "producer_sha256": native.producer_digest(),
        "candidate_receipt_sha256": native.sha(queue.receipt)})
    assert native.main() == 1
    assert len(queue.flows) == 1
    assert queue.builds == []


@pytest.mark.parametrize("mode", ["--produce", "--build"])
def test_shared_build_busy_preserves_75_and_original_queue_reason(candidate_queue, monkeypatch, mode):
    queue = candidate_queue
    monkeypatch.setattr(sys, "argv", ["account_native.py", mode])
    queue.reuse_errors.append(native.sim_lane.LaneError("stale Xcode"))
    old_digest = native.sha(queue.receipt)
    queue.result = SimpleNamespace(returncode=75, stdout=json.dumps({"error": "BuildSlot memory pressure"}))
    assert native.main() == 75
    assert queue.flows == []
    assert native.sha(queue.receipt) == old_digest
    assert not list(queue.receipt.parent.glob("native-*/failed.json"))
    if mode == "--produce":
        deferred, = queue.receipt.parent.glob("native-*/deferred.json")
        detail = json.loads(deferred.read_text())
        assert detail["exit_code"] == 75
        assert detail["reason"] == "BuildSlot memory pressure"
        assert native.dt.datetime.fromisoformat(detail["next_attempt_at"]) > native.dt.datetime.now().astimezone()


def test_real_build_error_stays_failed_without_native_flow(candidate_queue):
    queue = candidate_queue
    queue.reuse_errors.append(native.sim_lane.LaneError("stale Xcode"))
    queue.result = SimpleNamespace(returncode=1, stdout=json.dumps({"ok": False, "error": "compiler error"}))
    assert native.main() == 1
    assert queue.flows == []
    failed, = queue.receipt.parent.glob("native-*/failed.json")
    assert "Original shared build failed (exit 1)" in json.loads(failed.read_text())["reason"]
    assert not list(queue.receipt.parent.glob("native-*/deferred.json"))


def test_rebuilt_candidate_must_pass_shared_verifier_without_rebuild_loop(candidate_queue):
    queue = candidate_queue
    queue.reuse_errors.extend([native.sim_lane.LaneError("stale Xcode"),
                               native.sim_lane.LaneError("production source changed during build")])
    assert native.main() == 1
    assert len(queue.builds) == 1
    assert queue.flows == []
    failed, = queue.receipt.parent.glob("native-*/failed.json")
    assert json.loads(failed.read_text())["reason"] == "production source changed during build"


def test_debug_dylib_tampering_cannot_be_rebuilt_away_or_credited(candidate_queue):
    queue = candidate_queue
    (queue.app / "WrongBook.debug.dylib").write_bytes(b"changed implementation")
    assert native.main() == 1
    assert queue.builds == queue.flows == []
    failed, = queue.receipt.parent.glob("native-*/failed.json")
    assert "including Debug dylib" in json.loads(failed.read_text())["reason"]


@pytest.mark.parametrize("stage", ["prepare", "native"])
def test_term_unwinds_cleanup_and_defers_without_shared_cli_wrapping_143(candidate_queue, monkeypatch, stage):
    queue = candidate_queue
    previous = native.signal.getsignal(native.signal.SIGTERM)
    cleaned = []

    def interrupted(*args):
        try:
            try:
                native.signal.raise_signal(native.signal.SIGTERM)
            except SystemExit as exc:
                # Chapter's registry CLI catches SystemExit and turns it into
                # ValueError, which reuse_build wraps as this original error.
                raise native.sim_lane.LaneError("缓存构建无法核验：" + str(exc.code)) from None
        finally:
            # A repeated TERM during teardown must not abort cleanup.
            native.signal.raise_signal(native.signal.SIGTERM)
            cleaned.append(stage)

    monkeypatch.setattr(native, "prepare_candidate" if stage == "prepare" else "produce", interrupted)
    try:
        assert native.main() == 75
        assert native.signal.getsignal(native.signal.SIGTERM) == previous
    finally:
        native.signal.signal(native.signal.SIGTERM, previous)
    assert cleaned == [stage]
    assert not list(queue.receipt.parent.glob("native-*/failed.json"))
    assert not (queue.receipt.parent / "account-lifecycle.json").exists()
    deferred, = queue.receipt.parent.glob("native-*/deferred.json")
    detail = json.loads(deferred.read_text())
    assert detail["exit_code"] == 75
    assert "SIGTERM" in detail["reason"]
    assert native.dt.datetime.fromisoformat(detail["next_attempt_at"]) > native.dt.datetime.now().astimezone()


@pytest.mark.parametrize("code", [-15, 143])
def test_shared_build_termination_is_deferred_without_failure_evidence(candidate_queue, code):
    queue = candidate_queue
    queue.reuse_errors.append(native.sim_lane.LaneError("stale candidate"))
    queue.result = SimpleNamespace(returncode=code, stdout="")
    assert native.main() == 75
    assert queue.flows == []
    assert not list(queue.receipt.parent.glob("native-*/failed.json"))
    deferred, = queue.receipt.parent.glob("native-*/deferred.json")
    assert "SIGTERM" in json.loads(deferred.read_text())["reason"]


def test_term_in_actual_shared_registry_before_run_creation_returns_75(tmp_path):
    # Use a child so a regression in signal handling cannot stop pytest's worker.
    # Only the inventory input is replaced; load_apps' actual SystemExit handler runs.
    import subprocess
    program = '''
import importlib.util, signal, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("native_term_test", Path(sys.argv[1]))
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)
native.ROOT = Path(sys.argv[2])
import fleet_audit
fleet_audit.registry_inventory = lambda: signal.raise_signal(signal.SIGTERM)
sys.argv = ["account_native.py", "--produce"]
raise SystemExit(native.main())
'''
    result = subprocess.run([sys.executable, "-B", "-c", program, str(ROOT / "scripts/accept/account_native.py"), str(tmp_path)],
                            capture_output=True, text=True, timeout=30)
    assert result.returncode == 75, result.stdout + result.stderr
    assert "SIGTERM" in result.stdout
    assert not list(tmp_path.rglob("failed.json"))


@pytest.mark.parametrize("error", [RuntimeError("Native assertions failed in exercise"),
                                  urllib.error.HTTPError("http://127.0.0.1/api/login", 500, "Server error", {}, None)])
def test_business_or_http_error_stays_failed(candidate_queue, monkeypatch, error):
    def fail(*args):
        raise error
    monkeypatch.setattr(native, "produce", fail)
    assert native.main() == 1
    failed, = candidate_queue.receipt.parent.glob("native-*/failed.json")
    assert json.loads(failed.read_text())["error_class"] == type(error).__name__
    assert not list(candidate_queue.receipt.parent.glob("native-*/deferred.json"))
