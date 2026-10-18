"""Installed native UI must use production binding without trusting stale lane copies."""
import importlib.util
from pathlib import Path
from types import SimpleNamespace

import pytest


spec = importlib.util.spec_from_file_location(
    "wrongbook_product_basics", Path(__file__).resolve().parents[1] / "scripts/accept/product_basics.py")
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


@pytest.fixture
def installed(monkeypatch, tmp_path):
    executable = tmp_path / "WrongBook"
    executable.write_bytes(b"real fixture executable")
    business = {"Sources/App.swift": "source-hash"}
    binding = native.app_sop.digest_value([business])
    monkeypatch.setenv("SOP_BUILD_CURRENT", "1")
    monkeypatch.setenv("SOP_CODE_BINDING_SHA256", binding)
    monkeypatch.setattr(native.app_sop, "load_apps", lambda _: [{"repo": native.ROOT}])
    monkeypatch.setattr(native.app_sop, "business_code_files", lambda *_: ({}, business))
    monkeypatch.setattr(native.sim_lane, "reuse_build", lambda *_: pytest.fail("installed delivery must not read lane cache"))
    monkeypatch.setattr(native.sim_lane, "bundle_info", lambda _: {
        "mac": True, "bundle_id": "cyou.tianli.wrongbook", "version": "1", "build": "2",
        "executable": str(executable)})
    monkeypatch.setattr(native.subprocess, "run", lambda *_args, **_kwargs: SimpleNamespace(returncode=0))
    monkeypatch.setattr(native, "artifacts", lambda _: {"Contents/MacOS/WrongBook": native.sha(executable)})
    return {"SOP_BUILD_CURRENT": "1", "SOP_CODE_BINDING_SHA256": binding}


def test_installed_does_not_need_pruned_temporary_receipt(installed):
    built, app = native.verified(Path("/missing/cache.json"), "mac", None)
    assert app == Path("/Applications/错题本.app")
    assert built["code_binding"] == installed
    assert built["product_artifacts"]["Contents/MacOS/WrongBook"] == built["executable_sha256"]


@pytest.mark.parametrize("key,value", [
    ("SOP_BUILD_CURRENT", "0"), ("SOP_CODE_BINDING_SHA256", "stale"),
    ("SOP_CODE_BINDING_SHA256", None)])
def test_changed_or_incomplete_production_binding_fails(installed, monkeypatch, key, value):
    if value is None:
        monkeypatch.delenv(key)
    else:
        monkeypatch.setenv(key, value)
    with pytest.raises(native.sim_lane.LaneError, match="生产输入绑定未通过"):
        native.verified(Path("/missing/cache.json"), "mac", None)


def test_direct_cli_uses_same_chapter_artifact_verifier(installed, monkeypatch):
    for key in installed:
        monkeypatch.delenv(key)
    calls = []
    def verify(app, *, bundle):
        calls.append(bundle)
        return installed
    monkeypatch.setattr(native.app_sop, "acceptance_code_environment", verify)
    native.verified(Path("/missing/cache.json"), "mac", None)
    assert calls == [Path("/Applications/错题本.app")]


def test_bad_installed_signature_fails(installed, monkeypatch):
    monkeypatch.setattr(native.subprocess, "run", lambda *_args, **_kwargs:
                        SimpleNamespace(returncode=1, stderr="invalid seal", stdout=""))
    with pytest.raises(native.sim_lane.LaneError, match="装机签名核验失败"):
        native.verified(Path("/missing/cache.json"), "mac", None)


def test_explicit_candidate_still_requires_lane_source_verification(monkeypatch):
    def reject(*_):
        raise native.sim_lane.LaneError("缓存构建源码与当前平台输入不同")
    monkeypatch.setattr(native.sim_lane, "reuse_build", reject)
    with pytest.raises(native.sim_lane.LaneError, match="当前平台输入不同"):
        native.verified(Path("candidate.json"), "mac", Path("candidate.app"))
