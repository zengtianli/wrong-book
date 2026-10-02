#!/usr/bin/env python3
"""Mistake Notebook (wrong-book) iOS simulator resource measurement (Release, isolated headless simulator).

Builds the *current working tree* (the exact files app_sop hashes as sop.source) in a temporary copy,
installs it on a dedicated, windowless simulator, and measures:
  - size: zipped .app (download proxy) and .app bytes (installed proxy) — simulator build, not an IPA;
  - launch: unified-log markers "Requesting launch" -> scene content "ready" / "Dropping launch assertion";
  - idle: shared app-lightweight measure.py (45 s settle, 60 s CPU window, footprint after window).
Writes perf/raw/simulator-full-<date>.json and updates perf/simulator.json only if the source snapshot
is unchanged across the whole run. Never opens Simulator.app, never touches the clipboard or input.
Exit 75 (Chapter retries the same input when steady): the host is busy before any work, the simulator lock is held,
or — only with --min-user-idle > 0 — the owner is not idle or comes back mid-run (the simulator is shut down at once).
Exit 1: a sample rejected after the build.

  ~/Dev/.venv/bin/python scripts/perf/sim_measure.py [--runs 5] [--max-load 12] [--min-user-idle 0]
      [--launch-arg=-api_base --launch-arg=http://127.0.0.1:PORT --launch-arg=-dev_user ...]
Adapted from the Growth Treasury pilot (~/Apps/edu/ios/points/01-源程序/scripts/perf/sim_measure.py). The simulator is
booted through the shared sim_lane Session (the machine-wide one-simulator lock, the load gate, always shut down) on
the shared default iPhone 17 Pro device, and scripts/perf/measure_platforms.py passes the fictional demo library
(scripts/demo/fixture.py) and a dev login as launch arguments, so the app is measured on its data-bearing first
screen (the wrong-book list) and never reaches edu.tianli.cyou.
"""
import argparse, datetime as dt, hashlib, json, os, plistlib, re, shutil, statistics, subprocess, sys, tempfile, time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, "/Users/tianli/Apps/chapter/engine")
import app_sop  # noqa: E402  (source snapshot = the binding app_sop verifies)

MEASURE = Path.home() / "Apps/.claude/skills/app-lightweight/scripts/measure.py"
MACAPP = Path.home() / "Dev/tools/dev/lib/tools/macapp"
sys.path.insert(0, str(MACAPP / "ios"))
import sim_lane  # noqa: E402  (machine-wide simulator lock + load gate + headless boot/shutdown)
DEVICE_NAME, DEVICE_TYPE = None, "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"   # shared default device
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
BUNDLE = "cyou.tianli.wrongbook"


def sh(cmd, **kw):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, **kw).stdout


def snapshot():
    app = app_sop.load_apps("wrong-book-ios")[0]
    return app_sop.app_source_snapshot(app, app["sop"]["source"])


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def device():
    return sim_lane.ensure_device("iphone", DEVICE_TYPE, DEVICE_NAME, RUNTIME)["udid"]


def build(work):
    """Release simulator build of the working tree through the shared sim_lane (copy outside the repo, xcodegen,
    scrubbed env). Since the Watch app is a dependency (embedded under WrongBook.app/Watch/), the build must not
    pin `-sdk iphonesimulator`: that forces the watchOS target onto the iOS SDK and fails (2026-10-02)."""
    t = time.time()
    built = sim_lane.build(REPO, "WrongBook", "iphone", "Release", work)
    xc = built["xcode"]
    return Path(built["app_path"]), round(time.time() - t, 1), f"{xc['name']} {xc['version']} ({xc['build']})"


def log_markers(udid, start, pid):
    out = sh(["xcrun", "simctl", "spawn", udid, "log", "show", "--style", "json", "--start", start, "--predicate",
              f'eventMessage CONTAINS "{BUNDLE}" OR eventMessage CONTAINS "app<{BUNDLE}>"'])
    rows = [{"timestamp": e["timestamp"], "process": Path(e.get("processImagePath", "")).name, "message": e["eventMessage"]}
            for e in json.loads(out or "[]")]
    def at(pred):
        hit = next((r for r in rows if pred(r)), None)
        return dt.datetime.strptime(hit["timestamp"][:26], "%Y-%m-%d %H:%M:%S.%f") if hit else None
    req = at(lambda r: r["message"].startswith(f"Requesting launch of {BUNDLE}"))
    ready = at(lambda r: f"sceneID:{BUNDLE}-default] scene content state changed: ready" in r["message"])
    done = at(lambda r: r["process"] == "SpringBoard" and f"[app<{BUNDLE}>:{pid}] Dropping launch assertion" in r["message"])
    ms = lambda a: round((a - req).total_seconds() * 1000, 1) if a and req else None
    keep = [r for r in rows if any(k in r["message"] for k in ("Requesting launch", "Launch successful", "content state changed: ready", "Dropping launch assertion"))]
    return ms(ready), ms(done), keep


def user_idle_s():
    out = sh(["ioreg", "-c", "IOHIDSystem"])
    m = re.search(r'"HIDIdleTime" = (\d+)', out)
    return int(m.group(1)) / 1e9 if m else 0.0


# app_sop's DEFER_EXIT: the environment stopped the run, not the input, so Chapter forgets the attempt and runs
# the same input again in the next steady window. Any other non-zero exit is recorded as a failed measurement
# of this input and is not retried until the input changes or the owner presses retry.
DEFER_EXIT = 75


def defer(reason):
    print(reason, file=sys.stderr)
    sys.exit(DEFER_EXIT)


WATCH_OWNER = False   # set from --min-user-idle in main()


def owner_back(t0, stage):
    """Input since the run started (idle time shorter than the run): stop now; it lags the owner and skews timing.
    Only with an idle gate (--min-user-idle > 0): the headless simulator takes no input or focus, so by default the
    owner may keep working (owner 2026-09-26: sampling does not wait for the owner to leave); host load stays gated."""
    if WATCH_OWNER and user_idle_s() < time.time() - t0:
        defer(f"{stage}：用户回来操作了，停止测量并关闭模拟器，空闲时再测")


def settle_gate(limit, stage, wait_s=600, t0=None, defer_on_timeout=False):
    deadline = time.time() + wait_s
    while os.getloadavg()[0] > limit:
        if t0 is not None:
            owner_back(t0, stage)
        if time.time() > deadline:
            reason = f"{stage}负载 {os.getloadavg()[0]:.1f} 在 {wait_s}s 内未降到 {limit} 以下，未测量"
            defer(reason) if defer_on_timeout else sys.exit(reason)
        time.sleep(10)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--max-load", type=float, default=12.0, help="1-min load average required before measuring starts")
    ap.add_argument("--min-user-idle", type=float, default=0.0,
                    help="optional idle gate: seconds without keyboard/mouse input before measuring starts (and stop "
                         "when input resumes); 0 = none, the headless simulator never takes input or focus")
    ap.add_argument("--abort-load", type=float, default=40.0,
                    help="reject the sample if the 1-min load exceeds this during timing/idle (gross host contamination)")
    ap.add_argument("--launch-arg", action="append", default=[],
                    help="launch argument passed to the app (write --launch-arg=-api_base for a leading dash)")
    a = ap.parse_args()
    global WATCH_OWNER
    WATCH_OWNER = a.min_user_idle > 0
    # values after -dev_pw / -token-like flags: scrubbed from the log markers kept as evidence
    secrets = [v for k, v in zip(a.launch_arg, a.launch_arg[1:])
               if k.startswith("-") and re.search(r"(pw|pass|password|token|secret|key|cookie)$", k.lstrip("-"), re.I)]
    idle_s = user_idle_s()
    if idle_s < a.min_user_idle:
        defer(f"用户 {idle_s:.0f}s 前仍有操作，未满 {a.min_user_idle:.0f}s 空闲门，未开模拟器、未测量")
    t0 = time.time()
    settle_gate(a.max_load, "开测前", 900, t0=t0, defer_on_timeout=True)
    load = os.getloadavg()
    before = snapshot()
    started = dt.datetime.now().astimezone()
    work = Path(tempfile.mkdtemp(prefix="wrongbook-sim-measure."))
    udid = None
    measured = False
    try:
        app, build_s, xcode = build(work / "src")
        owner_back(t0, "构建后")
        info = plistlib.loads((app / "Info.plist").read_bytes())
        version = f"{info['CFBundleShortVersionString']} ({info['CFBundleVersion']})"
        zip_path = work / "WrongBook.app.zip"
        subprocess.run(["ditto", "-c", "-k", "--keepParent", str(app), str(zip_path)], check=True)
        installed = sum(f.stat().st_size for f in app.rglob("*") if f.is_file() and not f.is_symlink())
        udid = device()
        session = sim_lane.Session("iphone", udid, label="wrong-book sim_measure (legacy iPhone)", max_load=a.max_load)
        try:
            session.__enter__()          # lock, load gate, headless boot; the finally below shuts down and releases
        except sim_lane.Busy as exc:
            udid = None
            defer(f"模拟器锁或负载门：{exc}")
        # A freshly created iOS 27 simulator spends minutes on first-boot work (load > 300 seen 2026-09-29);
        # timing launches during that window measures the host, not the app.
        settle_gate(a.max_load, "开机后", t0=t0)
        owner_back(t0, "开机后")
        subprocess.run(["xcrun", "simctl", "uninstall", udid, BUNDLE], capture_output=True)
        subprocess.run(["xcrun", "simctl", "install", udid, str(app)], check=True)
        samples = []
        load_mid = os.getloadavg()
        for run in range(a.runs + 1):  # run 0 = first launch after install, discarded
            subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE], capture_output=True)
            time.sleep(3)
            start = dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            out = sh(["xcrun", "simctl", "launch", udid, BUNDLE, *a.launch_arg])
            pid = int(out.strip().split(":")[-1])
            time.sleep(5)
            ready, done, lines = log_markers(udid, start, pid)
            for ln in lines:           # SpringBoard echoes the launch arguments: never keep a password in evidence
                for secret in secrets:
                    ln["message"] = ln["message"].replace(secret, "<redacted>")
            samples.append({"run": run, "pid": pid, "request_to_ready_ms": ready, "request_to_launch_complete_ms": done, "markers": lines})
            owner_back(t0, "启动计时中")
        load_after_launch = os.getloadavg()
        if max(load_after_launch[0], load_mid[0]) > a.abort_load:
            sys.exit(f"启动计时期间负载 {load_mid[0]:.1f}/{load_after_launch[0]:.1f} 超过 {a.abort_load}，样本作废，未写入")
        kept = [s for s in samples[1:] if s["request_to_ready_ms"] and s["request_to_launch_complete_ms"]]
        if len(kept) < a.runs:
            sys.exit(f"启动标记不全：{len(kept)}/{a.runs} 次有效")
        ready_med = round(statistics.median(s["request_to_ready_ms"] for s in kept), 1)
        done_med = round(statistics.median(s["request_to_launch_complete_ms"] for s in kept), 1)
        # idle: fresh launch, settle 45 s, 60 s CPU window via shared measure.py
        subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE], capture_output=True)
        time.sleep(3)
        pid = int(sh(["xcrun", "simctl", "launch", udid, BUNDLE, *a.launch_arg]).strip().split(":")[-1])
        time.sleep(45)
        owner_back(t0, "空闲采样前")
        idle_load = os.getloadavg()
        if idle_load[0] > a.abort_load:
            sys.exit(f"空闲采样前 1 分钟负载 {idle_load[0]:.1f} > {a.abort_load}，样本作废，未写入")
        idle_out = sh([sys.executable, str(MEASURE), "idle", str(pid), "--seconds", "60"])
        idle = json.loads(idle_out[idle_out.index("{"):idle_out.rindex("}") + 1])["idle"]
        owner_back(t0, "空闲采样中")
        subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE], capture_output=True)
        measured = True
    finally:
        if udid:
            session.__exit__(None, None, None)   # shut down, release the simulator lock
        if not measured:  # a stopped or failed run leaves no multi-hundred-MB build copy behind
            shutil.rmtree(work, ignore_errors=True)
    after = snapshot()
    if after["sha256"] != before["sha256"]:
        shutil.rmtree(work, ignore_errors=True)
        sys.exit("测量期间源码输入变化，未写入证据")
    host = sh(["sysctl", "-n", "machdep.cpu.brand_string"]).strip()
    model = sh(["sysctl", "-n", "hw.model"]).strip()
    macos = sh(["sw_vers", "-productVersion"]).strip()
    stamp = started.strftime("%Y%m%d")
    raw_rel = f"perf/raw/simulator-full-{stamp}.json"
    raw = {"schema_version": 1, "app_id": "wrong-book-ios", "environment": "simulator", "mode": "full",
           "measured_at": started.isoformat(), "completed_at": dt.datetime.now().astimezone().isoformat(),
           "version": version, "configuration": "Release", "bundle_id": BUNDLE,
           "binary_sha256": sha(app / "WrongBook") if (app / "WrongBook").exists() else None,
           "build_receipt": {"configuration": "Release", "seconds": build_s, "xcode": xcode, "source_sha256": before["sha256"],
                             "source_file_count": before["file_count"], "source_dirty": before["dirty"], "git_head": before["commit"],
                             "built_from": "working-tree copy (exactly the files app_sop hashes as sop.source)", "source_unchanged": True},
           "simulator_device": "iPhone 17 Pro", "simulator_os": "iOS 27.0", "simulator_udid": udid,
           "host": f"{model} / {host} / macOS {macos}", "load_average_at_start": list(load), "load_average_before_launches": list(load_mid),
           "load_average_after_launches": list(load_after_launch), "load_average_before_idle": list(idle_load),
           "load_gates": {"start_max": a.max_load, "abort_above": a.abort_load},
           "measurement_tool_sha256": sha(MEASURE), "probe_sha256": sha(__file__),
           "scope": "Simulator App process only; excludes CoreSimulator, Simulator GUI, system services and inactive extensions",
           "launch": {"samples": samples, "discarded_runs": 1, "runs": len(kept), "ready_median_ms": ready_med,
                      "launch_complete_median_ms": done_med,
                      "method": "Simulator unified log: CoreSimulatorBridge \"Requesting launch of <bundle>\" -> SpringBoard scene content state \"ready\" / SpringBoard \"Dropping launch assertion\". App terminated 3 s before each run; first run after install discarded."},
           "size": {"download_bytes": zip_path.stat().st_size, "installed_bytes": installed,
                    "kind": "Local simulator Release .app ZIP / .app bytes; not an App Store IPA or device slice"},
           "idle": {**idle, "settle_s": 45}, "source_unchanged_during_measurement": True}
    (REPO / raw_rel).write_text(json.dumps(raw, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    shutil.rmtree(work, ignore_errors=True)

    sim_path = REPO / "perf/simulator.json"
    sim = json.loads(sim_path.read_text())
    method = raw["launch"]["method"] + f" Median of {len(kept)} runs."
    sim.update({"version": version, "configuration": "Release", "measured_at": started.isoformat(),
                "device": f"iPhone 17 Pro / iOS 27.0 Simulator / {model} / {host} / macOS {macos}",
                "input_sha256": before["sha256"], "git_head": before["commit"],
                "data": ("Fictional demo library (scripts/demo/fixture.py: local stdlib server, invented account 小林, five "
                         "demo lessons, pending reviews) with a dev login; first data-bearing screen; no production data"
                         if a.launch_arg else sim.get("data")),
                "size": raw["size"],
                "idle": {"process": str(pid), "footprint_mb": idle["footprint_mb"], "cpu_pct": idle["cpu_pct"],
                         "window_s": idle["window_s"], "settle_s": 45,
                         "method": "Shared measure.py: CPU time delta / 60s wall; 3 phys_footprint samples after CPU window, maximum reported",
                         "scope": raw["scope"]},
                "runtime_measurement": {"environment": "simulator", "device": "iPhone 17 Pro", "os": "iOS 27.0", "version": version,
                                        "evidence": raw_rel, "evidence_sha256": sha(REPO / raw_rel)}})
    for entry in sim.get("speed_gui", []):
        entry.update(runs=len(kept), method=method, evidence=raw_rel, evidence_sha256=sha(REPO / raw_rel))
        if entry.get("key") == "first_screen_ready":
            entry["median_ms"] = ready_med
        elif entry.get("key") == "launch_complete":
            entry["median_ms"] = done_med
    sim_path.write_text(json.dumps(sim, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(json.dumps({"version": version, "input_sha256": before["sha256"], "size": raw["size"], "idle": idle,
                      "ready_median_ms": ready_med, "launch_complete_median_ms": done_med, "evidence": raw_rel}, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
