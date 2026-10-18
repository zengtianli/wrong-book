#!/usr/bin/env python3
"""Produce missing current bilingual screenshots, then run Chapter's inspector.

Uses the existing sim_lane build slots and strict hidden simulator admission.
No installation on the owner's Mac/phone, registration changes or release.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import sys

NATIVE_SPEC = importlib.util.spec_from_file_location(
    "wrongbook_native_acceptance", Path(__file__).with_name("product_basics.py"))
native = importlib.util.module_from_spec(NATIVE_SPEC)
NATIVE_SPEC.loader.exec_module(native)
import localization as inspector

sys.path.insert(0, str(Path.home() / "Apps/chapter/engine/acceptors"))
from _common import env, finish


def capture_current(app):
    receipt = native.ROOT / "perf/localization-iphone-build.json"
    try:
        native.sim_lane.reuse_build(receipt, native.APP_ID, native.ROOT, "iphone", "WrongBook", "Debug")
    except (native.sim_lane.LaneError, OSError, ValueError, KeyError):
        # Build admission is owned by sim_admission/BuildSlot, not the strict
        # simulator quiet gate. A single busy attempt returns to the jobs queue.
        command = [sys.executable, str(Path.home() / "Apps/chapter/engine/sim_admission.py"),
                   "build", str(Path(native.sim_lane.__file__)), "build", "--project-dir", str(native.ROOT),
                   "--scheme", "WrongBook", "--platform", "iphone", "--configuration", "Debug", "--json"]
        built = subprocess.run(command, capture_output=True, text=True, timeout=660)
        if built.returncode == 75:
            raise native.sim_lane.Busy((built.stderr or built.stdout)[-700:])
        if built.returncode:
            raise native.sim_lane.LaneError("多语言候选构建失败：" + (built.stderr or built.stdout)[-700:])
        native.write(receipt, json.loads(built.stdout))
    spec = importlib.util.spec_from_file_location(
        "wrongbook_l10n_capture", native.SCRIPT_ROOT / "scripts/media/localization_shots.py")
    capture = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(capture)
    capture.REPO = native.ROOT
    return capture.main(["--receipt", str(receipt), "--out", str(native.ROOT / "perf/acceptance/l10n")])


def main():
    ctx = env()
    ctx["app_id"], ctx["check"] = native.APP_ID, "localization"
    try:
        native.verify_source()
        native.output_directory()
        app = native.app_sop.load_apps(native.APP_ID)[0]
        if Path(app["repo"]).resolve() != native.ROOT:
            raise native.sim_lane.LaneError("多语言验收源目录与产品登记不同")
        result = inspector.inspect(app)
        shots = result["detail"].get("screenshots", {})
        if not shots.get("current_binding") or not all(shots.get("images", {}).values()):
            code = capture_current(app)
            if code:
                finish(ctx, False, "多语言截图推迟" if code == 75 else "多语言截图失败",
                       code=code, capture_receipt=str(native.ROOT / "perf/acceptance/l10n/result.json"))
            native.verify_source()
            result = inspector.inspect(app)
        finish(ctx, result["passed"], result["summary"], **result["detail"], localization_status=result["status"])
    except native.sim_lane.Busy as exc:
        finish(ctx, False, str(exc), code=75)
    except (native.sim_lane.LaneError, OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        finish(ctx, False, str(exc), code=1)


if __name__ == "__main__":
    main()
