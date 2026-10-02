#!/usr/bin/env python3
"""Mistake Notebook resource measurement for every platform lane (Chapter sop.measure.command).

    ~/Dev/.venv/bin/python scripts/perf/measure_platforms.py [--only iphone,watch] [--force] [--budget-min 50]

One fictional demo library (scripts/demo/fixture.py: stdlib server on a random 127.0.0.1 port, invented account 小林,
five demo lessons, a random per-start password) serves every run. Every launch gets -api_base; the dev login
(-dev_user / -dev_pw) goes only on the discarded first launch after install (platform_measure --warmup-arg), so the
timed launches are the app's real reopen with the stored session up to its first data-bearing screen (the wrong-book
list; the Watch home), as in the Growth Treasury pilot. The legacy iPhone step times SpringBoard's scene markers,
which a sign-in does not move, and keeps the login on every launch. Steps, each skipped when its evidence already binds the current input:
  legacy  scripts/perf/sim_measure.py → perf/simulator.json (Chapter's iOS perf/budget/speed items read it through
          perf/lightweight.json; bound to sop.source)
  lanes   the shared app-lightweight platform_measure.py → perf/platforms/<lane>.json (bound to
          `app_sop.py lane-inputs`), order iphone, ipad, watch, mac, vision (Vision boots heaviest, last)
Simulators go through the shared sim_lane lock and load gate (one simulator on this Mac at a time) and are always
shut down; the Mac lane launches quietly (sim_lane: open -g -j + the app's -lane_quiet — no window on screen, no Dock
icon), so like the simulators it runs while the owner works.
Exit 0 all current, 75 something deferred (lock held, machine loaded, owner active, or the time budget below ran out;
Chapter runs the same input again and only the missing steps are measured), 1 a step failed.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
APP_ID = "wrong-book-ios"
LANES = ("iphone", "ipad", "watch", "mac", "vision")
ENGINE = Path.home() / "Apps/chapter/engine/app_sop.py"
PLATFORM_MEASURE = Path.home() / "Apps/.claude/skills/app-lightweight/scripts/platform_measure.py"
PY = str(Path.home() / "Dev/.venv/bin/python") if (Path.home() / "Dev/.venv/bin/python").exists() else sys.executable
DEFER = 75


def lane_digest(lane: str) -> str | None:
    r = subprocess.run([PY, str(ENGINE), "lane-inputs", "--app", APP_ID, "--platform", lane, "--json"],
                       capture_output=True, text=True, timeout=300)
    try:
        return json.loads(r.stdout).get("input_sha256") if r.returncode == 0 else None
    except ValueError:
        return None


def recorded(path: Path) -> str | None:
    try:
        return json.loads(path.read_text(encoding="utf-8")).get("input_sha256")
    except (OSError, ValueError, AttributeError):
        return None


def legacy_digest() -> str | None:
    sys.path.insert(0, str(ENGINE.parent))
    import app_sop  # noqa: E402  (the binding Chapter verifies for perf/simulator.json)
    app = app_sop.load_apps(APP_ID)[0]
    return app_sop.app_source_snapshot(app, app["sop"]["source"])["sha256"]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", help="comma-separated steps: legacy and/or lane ids")
    ap.add_argument("--force", action="store_true", help="measure even when the evidence binds the current input")
    ap.add_argument("--budget-min", type=float, default=50.0,
                    help="do not start a new step after this many minutes (Chapter kills the command at 60)")
    a = ap.parse_args(argv)
    steps = ["legacy", *LANES]
    if a.only:
        wanted = [s.strip() for s in a.only.split(",") if s.strip()]
        unknown = [s for s in wanted if s not in steps]
        if unknown:
            print(f"未知步骤 {unknown}（可选 {', '.join(steps)}）", file=sys.stderr)
            return 2
        steps = [s for s in steps if s in wanted]
    todo = []
    for step in steps:
        current = legacy_digest() if step == "legacy" else lane_digest(step)
        path = REPO / ("perf/simulator.json" if step == "legacy" else f"perf/platforms/{step}.json")
        if current and recorded(path) == current and not a.force:
            print(f"＝ {step}: 证据已绑定当前输入 {current[:8]}…，跳过", flush=True)
        else:
            todo.append(step)
    if not todo:
        print(json.dumps({"ok": True, "measured": [], "skipped": steps}, ensure_ascii=False))
        return 0
    t0 = time.time()
    results: dict[str, int | str] = {}
    with tempfile.TemporaryDirectory(prefix="wrongbook-measure.") as scratch:
        r = subprocess.run([PY, str(REPO / "scripts/demo/fixture.py"), "start", "--dir", scratch, "--json"],
                           capture_output=True, text=True, timeout=120)
        if r.returncode:
            print(f"演示学习库没起来（退出码 {r.returncode}）：{(r.stderr or r.stdout)[-300:]}", file=sys.stderr)
            return r.returncode if r.returncode in (DEFER, 78) else 1
        lib = json.loads(r.stdout)
        base = ["-api_base", lib["url"]]
        login = ["-dev_user", lib["user"], "-dev_pw", lib["pw"]]
        print(f"演示学习库 {lib['url']}（{lib['user']}，本机合成数据）", flush=True)
        try:
            for step in todo:
                if time.time() - t0 > a.budget_min * 60:
                    results[step] = "deferred: time budget"
                    continue
                if step == "legacy":
                    cmd = [PY, str(REPO / "scripts/perf/sim_measure.py"), *[f"--launch-arg={x}" for x in base + login]]
                else:
                    cmd = [PY, str(PLATFORM_MEASURE), "--app", APP_ID, "--platform", step, "--repo", str(REPO),
                           *[f"--launch-arg={x}" for x in base], *[f"--warmup-arg={x}" for x in login]]
                print(f"→ {step}", flush=True)
                env = {**os.environ, "SIM_LANE_LABEL": f"wrong-book measure_platforms {step}"}
                proc = subprocess.run(cmd, cwd=REPO, env=env, stdin=subprocess.DEVNULL)
                results[step] = proc.returncode
                print(f"← {step}: 退出码 {proc.returncode}", flush=True)
        finally:
            subprocess.run([PY, str(REPO / "scripts/demo/fixture.py"), "stop", "--dir", scratch], capture_output=True)
    failed = [s for s, c in results.items() if isinstance(c, int) and c not in (0, DEFER)]
    deferred = [s for s, c in results.items() if c == DEFER or isinstance(c, str)]
    print(json.dumps({"ok": not failed and not deferred, "results": results, "failed": failed, "deferred": deferred},
                     ensure_ascii=False))
    return 1 if failed else DEFER if deferred else 0


if __name__ == "__main__":
    sys.exit(main())
