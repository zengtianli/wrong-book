"""Reject incomplete/native-identity substitutions; exercise real isolated service."""
import importlib.util
from pathlib import Path
import urllib.error
import urllib.request
import json
import sys

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
