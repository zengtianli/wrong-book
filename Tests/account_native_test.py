"""Reject incomplete/native-identity substitutions; exercise real isolated service."""
import copy
import importlib.util
from pathlib import Path
import urllib.error
import urllib.request
import json

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


def test_unattached_view_and_native_failure_are_required():
    raw = completed()
    raw["delete"]["checks"]["native.login_view_offscreen"] = False
    assert native.cases_from_raw(raw) == []
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
