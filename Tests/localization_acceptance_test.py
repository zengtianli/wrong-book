"""Check queue wiring without a simulator, build, owner App or fabricated evidence."""
import importlib.util
from pathlib import Path
from types import SimpleNamespace

import pytest

SPEC = importlib.util.spec_from_file_location(
    "wrongbook_localization_acceptance", Path(__file__).resolve().parents[1] / "scripts/accept/localization.py")
accept = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(accept)


@pytest.mark.parametrize("code", [75, 1])
def test_build_busy_and_failure_are_distinct(monkeypatch, tmp_path, code):
    monkeypatch.setattr(accept.native, "ROOT", tmp_path)
    def missing(*_):
        raise accept.native.sim_lane.LaneError("missing receipt")
    monkeypatch.setattr(accept.native.sim_lane, "reuse_build", missing)
    calls = []
    def build(command, **_):
        calls.append(command)
        return SimpleNamespace(returncode=code, stderr="original failure", stdout="")
    monkeypatch.setattr(accept.subprocess, "run", build)
    expected = accept.native.sim_lane.Busy if code == 75 else accept.native.sim_lane.LaneError
    with pytest.raises(expected, match="original failure"):
        accept.capture_current({})
    assert len(calls) == 1
    assert "sim_admission.py" in calls[0][1]
    assert not (tmp_path / "perf/localization-iphone-build.json").exists()


@pytest.mark.parametrize("current,capture_code", [(True, None), (False, 75), (False, 1), (False, 0)])
def test_fixed_acceptance_reuses_or_produces_current_evidence(monkeypatch, tmp_path, current, capture_code):
    monkeypatch.setattr(accept.native, "ROOT", tmp_path)
    monkeypatch.setattr(accept, "env", lambda: {"out": tmp_path})
    monkeypatch.setattr(accept.native, "verify_source", lambda: None)
    monkeypatch.setattr(accept.native, "output_directory", lambda: tmp_path)
    monkeypatch.setattr(accept.native.app_sop, "load_apps", lambda _: [{"repo": tmp_path}])
    inspections, captures = [], []
    def inspect(_):
        inspections.append(True)
        return {"passed": current or bool(captures), "summary": "observed", "status": "passed",
                "detail": {"screenshots": {"current_binding": current or bool(captures),
                                          "images": {"en": ["en/login.png"], "zh-Hans": ["zh-Hans/login.png"]}}}}
    monkeypatch.setattr(accept.inspector, "inspect", inspect)
    def capture(_):
        captures.append(True)
        return capture_code
    monkeypatch.setattr(accept, "capture_current", capture)
    def finish(ctx, ok, summary, code=None, **detail):
        raise SystemExit(0 if ok else code or 1)
    monkeypatch.setattr(accept, "finish", finish)
    with pytest.raises(SystemExit) as result:
        accept.main()
    assert result.value.code == (capture_code or 0)
    assert len(captures) == (0 if current else 1)
    assert len(inspections) == (2 if capture_code == 0 else 1)
