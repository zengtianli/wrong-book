#!/usr/bin/env python3
"""Mistake Notebook: fictional library and budget around the shared platform measurer.

--only legacy maps to iphone; its one raw measurement is projected with --sync-ios.
Every lane keeps -api_base. -dev_user/-dev_pw are only discarded warmup arguments,
including Watch, so timed reopens use the stored session rather than repeated logins.
Current evidence must match source and raw evidence hashes; --force explicitly remeasures.
Busy or exhausted budget returns 75 immediately, without continuing to another lane.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
LANES = ("iphone", "ipad", "watch", "mac", "vision")
PLATFORM_MEASURE = Path.home() / "Apps/.claude/skills/app-lightweight/scripts/platform_measure.py"
PY = str(Path.home() / "Dev/.venv/bin/python") if (Path.home() / "Dev/.venv/bin/python").exists() else sys.executable
DEFER = 75


APP_ID = "wrong-book-ios"
FIXTURE = "scripts/demo/fixture.py"
FIXTURE_TIMEOUT = 120
SCRATCH_PREFIX = "wrongbook-measure."


def fixture_args(lane, demo):
    base = ["-api_base", demo["url"]]
    login = ["-dev_user", demo["user"], "-dev_pw", demo["pw"]]
    return [f"--launch-arg={arg}" for arg in base] + [f"--warmup-arg={arg}" for arg in login]


def shared_tools():
    spec = importlib.util.spec_from_file_location("_shared_platform_measure", PLATFORM_MEASURE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def current(shared, lane):
    """只消费总部输入绑定、原件哈希与 iOS 投影，不再单独测 legacy。"""
    cfg = shared.lane_config(REPO, lane)
    if cfg.get("not_applicable") or cfg.get("component"):
        return True
    digest = shared.lane_inputs(APP_ID, lane, None)
    doc = shared.current_evidence(REPO, lane, cfg, digest, fixture_debug=False)
    if doc is not None and lane == "iphone":
        shared.sync_ios_evidence(REPO, doc)
    return doc is not None


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", default=os.environ.get("SOP_PERF_PLATFORM"),
                        help="comma-separated lanes; legacy is an alias for iphone; default SOP_PERF_PLATFORM")
    parser.add_argument("--force", action="store_true", help="measure requested lanes even with valid current evidence")
    parser.add_argument("--budget-min", type=float, default=50.0, help="stop before starting the next step at this deadline")
    parser.add_argument("--reuse-size-build", type=Path, help="shared Release receipt; requires --only one lane")
    parser.add_argument("--reuse-runtime-build", type=Path, help="shared runtime receipt; requires --only one lane")
    options = parser.parse_args(argv)
    if options.budget_min < 0:
        parser.error("--budget-min cannot be negative")
    wanted = [part.strip() for part in options.only.split(",") if part.strip()] if options.only is not None else list(LANES)
    unknown = [lane for lane in wanted if lane not in (*LANES, "legacy")]
    if unknown or not wanted:
        parser.error(f"unknown or empty lanes: {wanted}")
    selected = {"iphone" if lane == "legacy" else lane for lane in wanted}
    lanes = [lane for lane in LANES if lane in selected]
    if (options.reuse_size_build or options.reuse_runtime_build) and (not options.only or len(lanes) != 1):
        parser.error("build receipts require --only a single lane")
    started = time.monotonic()

    def remaining():
        return options.budget_min * 60 - (time.monotonic() - started)

    if remaining() <= 0:
        return DEFER
    shared = shared_tools()
    todo = []
    for lane in lanes:
        if remaining() <= 0:
            return DEFER
        if not options.force and current(shared, lane):
            print(f"＝ {lane}: current source and raw evidence verified; skip", flush=True)
        else:
            todo.append(lane)
    if not todo:
        return 0
    if remaining() <= 0:
        return DEFER
    with tempfile.TemporaryDirectory(prefix=SCRATCH_PREFIX) as scratch:
        try:
            fixture_budget = remaining()
            if fixture_budget <= 0:
                return DEFER
            fixture = subprocess.run([PY, str(REPO / FIXTURE), "start", "--dir", scratch, "--json"],
                                     capture_output=True, text=True, timeout=min(FIXTURE_TIMEOUT, fixture_budget))
            if fixture.returncode:
                print(f"isolated fixture failed: {(fixture.stderr or fixture.stdout)[-300:]}", file=sys.stderr)
                return fixture.returncode if fixture.returncode in (DEFER, 78) else 1
            demo = json.loads(fixture.stdout)
            for lane in todo:
                if remaining() <= 0:
                    return DEFER
                command = [PY, str(PLATFORM_MEASURE), "--app", APP_ID, "--repo", str(REPO),
                           "--platform", lane, "--sync-ios", "--lock-wait", "0", "--load-wait", "0",
                           *fixture_args(lane, demo)]
                for flag, value in (("--reuse-size-build", options.reuse_size_build),
                                    ("--reuse-runtime-build", options.reuse_runtime_build)):
                    if value:
                        command += [flag, str(value)]
                print(f"→ {lane}", flush=True)
                proc = subprocess.run(command, cwd=REPO, stdin=subprocess.DEVNULL,
                                      env={**os.environ, "SIM_LANE_LABEL": f"{APP_ID} measure {lane}"})
                print(f"← {lane}: {proc.returncode}", flush=True)
                if proc.returncode:
                    return proc.returncode if proc.returncode in (DEFER, 78) else 1
            return 0
        except subprocess.TimeoutExpired:
            print("fixture exceeded the remaining time budget; no further lane started", file=sys.stderr)
            return DEFER
        finally:
            subprocess.run([PY, str(REPO / FIXTURE), "stop", "--dir", scratch],
                           capture_output=True, timeout=30)


if __name__ == "__main__":
    sys.exit(main())
