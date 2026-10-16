#!/usr/bin/env python3
"""Observe the real simulator product without input; never writes acceptance PASS.

Reuse a candidate from a canonical launch attempt, run the ordinary App scene
against the fictional HTTP fixture, and collect a process sample plus requests.
All runtime ownership goes through the shared sim_lane; output stays private.
"""
import argparse
import datetime
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path.home() / "Dev/tools/dev/lib/tools/macapp/ios"))
import sim_lane


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=("ipad", "iphone", "vision"), default="ipad")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--app", type=Path)
    parser.add_argument("--lock-wait", type=float, default=0)
    parser.add_argument("--load-wait", type=float, default=0)
    args = parser.parse_args()
    if args.lock_wait < 0 or args.load_wait < 0:
        parser.error("queue wait budgets must be nonnegative")
    out = args.out.resolve()
    out.relative_to(ROOT / "handoffs")  # diagnostic material never enters public evidence
    if out.exists():
        parser.error("output must be a new directory; preserve previous observations")
    source = ROOT / f"perf/acceptance/launch_{args.platform}.detail.json"
    prior_bytes = source.read_bytes()
    prior = json.loads(prior_bytes)
    app = args.app or Path(prior["build"]["app_path"])
    info = sim_lane.bundle_info(app)
    if info["bundle_id"] != "cyou.tianli.wrongbook":
        parser.error("candidate is not WrongBook")
    if not args.app:
        executable = app / info["executable"]
        if hashlib.sha256(executable.read_bytes()).hexdigest() != prior["build"]["executable_sha256"]:
            parser.error("canonical candidate executable changed")
    code = app / "WrongBook.debug.dylib"
    if not code.is_file():
        parser.error("diagnostic entry requires the actual Debug product dylib")
    spec = importlib.util.spec_from_file_location("wrongbook_demo", ROOT / "scripts/demo/fixture.py")
    fixture = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fixture)
    out.mkdir(parents=True, mode=0o700)
    connection = None
    exit_code = 0
    report = {"scope": "diagnosis_only_not_acceptance", "platform": args.platform,
              "started_at": datetime.datetime.now().astimezone().isoformat(),
              "candidate": str(app), "bundle": info,
              "code_sha256": hashlib.sha256(code.read_bytes()).hexdigest(),
              "canonical_attempt": str(source), "canonical_attempt_sha256": hashlib.sha256(prior_bytes).hexdigest(),
              "admission": {"lock_wait_seconds": args.lock_wait, "load_wait_seconds": args.load_wait}}
    try:
        device = sim_lane.ensure_device(args.platform, prior["device"]["device_type"], "WrongBook Startup QA")
        with sim_lane.Session(args.platform, device["udid"], label="wrong-book startup diagnostics",
                              lock_wait=args.lock_wait, load_wait=args.load_wait) as lane:
            connection = fixture.start(out / "private-fixture")
            lane.install(app)
            launch = sim_lane.simctl("launch", "--terminate-running-process", device["udid"], info["bundle_id"],
                                     "-api_base", connection["url"], "-dev_user", connection["user"], "-dev_pw", connection["pw"])
            pid = int(launch.stdout.strip().rsplit(":", 1)[1])
            report.update(device=device, pid=pid)
            try:
                time.sleep(12)
                command = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "comm="], capture_output=True, text=True, check=True).stdout.strip()
                if device["udid"] not in command or not command.endswith("/WrongBook.app/WrongBook"):
                    raise RuntimeError("candidate process exited or PID no longer belongs to this QA device")
                result = subprocess.run(["/usr/bin/sample", str(pid), "3", "-file", str(out / "process.sample.txt")],
                                        capture_output=True, text=True, timeout=20)
                report["sample_exit_code"] = result.returncode
                lane.shot(out / "screen.png")
                time.sleep(3)
                report["requests"] = (out / "private-fixture/fixture.log").read_text().splitlines()
            finally:
                lane.terminate(info["bundle_id"])
    except sim_lane.Busy as error:
        report["deferred"] = str(error)
        exit_code = 75
    except Exception as error:
        message = str(error)
        if connection is not None:
            message = message.replace(connection["pw"], "<redacted>")
        report["error"] = type(error).__name__ + ": " + message
        exit_code = 1
    finally:
        if connection is not None:
            fixture.stop(out / "private-fixture")
        report["artifacts"] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in out.iterdir() if p.is_file()}
        (out / "diagnosis.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"scope": report["scope"], "out": str(out), "deferred": report.get("deferred"), "error": report.get("error"), "requests": report.get("requests"),
                      "sample_exit_code": report.get("sample_exit_code")}, ensure_ascii=False))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
