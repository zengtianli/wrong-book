#!/usr/bin/env python3
"""Does the iPhone (compact) UI still render exactly as before? Same data, two builds, pixel diff.

    ~/Dev/.venv/bin/python scripts/media/compact_unchanged.py [--base HEAD] [--out DIR] [--record]

The App Store screenshots and preview video show the compact layout. Since 2026-10-02 the same target also draws the
wide layout (iPad / Mac / Vision Pro) and ships a Watch app, so every UI change has to show that the iPhone screens
did not move. This builds the --base commit (default HEAD) and the current working tree through the shared sim_lane
(copies outside the repo, unsigned Debug simulator builds — Debug because the open-a-question launch channel is
DEBUG-only; both sides use the same configuration), starts the fictional demo library (scripts/demo/fixture.py),
and on one iPhone 17 Pro simulator (shared lock, load gate, headless, status bar pinned to 9:41) renders five
screens for each build from a fresh install: login, wrong book, import, review and an opened question. Screens are
compared pixel by pixel; a screen passes when it is identical, or when no pixel differs by more than 2 of 255 in any
channel. That threshold is below anything the app's layout can produce (a 1-pt shift or a colour change moves whole
glyph edges by 100+ levels); what does land under it is system-drawn noise that is not stable between two launches of
the same build: the iOS 26+ glass tab bar's refraction dither, the scroll indicator fading out, the status-bar clock.
The report keeps the count, bounding box and peak of every difference so a reviewer can see where it was.

Four screens decide the verdict: the ones the published iPhone media show (store screenshots: wrong book, question,
review, login; preview video: an opened question). The import tab is still rendered and reported, but does not decide
it (REPORT_ONLY): no published asset shows that screen, and opened directly it is not stable between two launches.

--record keeps the report as perf/media/compact-unchanged.json and appends the result to the media provenance
(sop.media_meta) under ui_reviews, bound to the sop.ui source snapshot Chapter computes (app_sop.app_source_snapshot),
so the existing iPhone media stay valid only while that review binds the current UI source (same as the Growth
Treasury pilot). The base is the commit the existing iPhone media correspond to: 89c699a (the last commit before the
2026-10-02 five-platform change) until 2026-10-05, 86f3afa since the login store screenshot was retaken for the
配置与更新 entry that commit added. Exit 0
unchanged, 1 changed or failed, 75 simulator lock held / machine loaded (run again later).
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import math
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
APP_ID = "wrong-book-ios"
BUNDLE = "cyou.tianli.wrongbook"
sys.path.insert(0, str(Path.home() / "Dev/tools/dev/lib/tools/macapp/ios"))
import sim_lane  # noqa: E402
sys.path.insert(0, str(Path.home() / "Apps/chapter/engine"))
import sim_admission  # noqa: E402

# (screen, launch args, extra seconds before the stability check). The opened question is a WKWebView page that
# paints after the native frame is already still: without the extra wait one side can be shot blank (2026-10-02).
SCREENS = [("login", None, 0), ("library", ["-tab", "0"], 0), ("import", ["-tab", "1"], 0), ("review", ["-tab", "2"], 0),
           ("question", ["-tab", "0", "-library.openQuestion", "f2"], 10)]
MAX_DIFF = 2          # of 255 per channel: perceptually identical; any layout / colour change is far above it
# Rendered and reported, but not part of the verdict. The verdict keeps the existing iPhone media valid, so it follows
# the screens those media show; perf/media/store-shots-current.json leaves import out of the store screenshots for the
# same reason given here, and the preview video does not show it.
REPORT_ONLY = {"import": "no published asset shows it; opened directly with -tab 1 it fetches the recognition quota "
                         "before the lesson sync finishes, so two launches of the same build can render differently"}


def sha(path: Path) -> str:
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def build_candidate(source: Path, work: Path) -> dict:
    # Original shared adapter retains sim_lane.build and its parallel SDK slot.
    result = subprocess.run([sys.executable, str(Path(sim_admission.__file__)), "build", str(Path(sim_lane.__file__)),
        "build", "--project-dir", str(source), "--scheme", "WrongBook", "--platform", "iphone",
        "--configuration", "Debug", "--work-dir", str(work), "--json"], capture_output=True, text=True, timeout=660)
    if result.returncode == 75:
        raise sim_lane.Busy(result.stdout.strip())
    if result.returncode:
        raise sim_lane.LaneError("shared compact build failed: " + result.stderr[-500:])
    return json.loads(result.stdout)


def ui_snapshot() -> dict:
    sys.path.insert(0, str(Path.home() / "Apps/chapter/engine"))
    import app_sop  # noqa: E402  (the snapshot Chapter's media check reads sop.ui through)
    app = app_sop.load_apps(APP_ID)[0]
    snap = app_sop.app_source_snapshot(app, app["sop"]["ui"])
    return {"globs": app["sop"]["ui"], "sha256": snap["sha256"], "file_count": snap["file_count"]}


def shots(udid: str, s, app: Path, args: list[str], out: Path, login_url: str, *, require_ready=False) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    sim_lane.simctl("uninstall", udid, BUNDLE, check=False)
    s.install(app)
    hashes = {}
    for name, extra, more in SCREENS:
        # A different port alone cannot isolate localhost cookies. Login uses a
        # separate fixture that rejects every cookie, including this run's.
        launch = ["-api_base", login_url] if extra is None else [*args, *extra]
        # The current data-bearing home must really finish loading. An identical
        # spinner in two builds is not proof that published screens are unchanged.
        if require_ready and name == "library":
            result = s.launch(BUNDLE, launch, "log", 120, None,
                              sim_lane.bundle_info(app)["executable"], functional_thin=True)
            if result.get("errors") or result.get("ready_signal") != "os_log":
                raise sim_lane.LaneError("current library never reached real lane-ready: " + str(result.get("errors")))
        else:
            sim_lane.simctl("launch", "--terminate-running-process", udid, BUNDLE, *launch, timeout=120)
        time.sleep(10 + more)    # the base build predates the lane-ready log; the same fixed wait for both sides
        a, b = out / f".{name}.a.png", out / f"{name}.png"
        s.shot(a)
        for _ in range(10):
            time.sleep(1.2)
            s.shot(b)
            if sim_lane.Frame(b, "iphone").diff(sim_lane.Frame(a, "iphone")) <= 0.0005:
                break
            shutil.copyfile(b, a)
        a.unlink(missing_ok=True)
        hashes[name] = sha(b)
        s.terminate(BUNDLE)
    sim_lane.simctl("uninstall", udid, BUNDLE, check=False)
    return hashes


def compare(a: Path, b: Path, diff_out: Path | None = None) -> dict:
    from PIL import Image, ImageChops
    ia, ib = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
    if ia.size != ib.size:
        return {"identical": False, "ok": False, "why": f"size {ia.size} vs {ib.size}"}
    diff = ImageChops.difference(ia, ib)
    bbox = diff.getbbox()
    if bbox is None:
        return {"identical": True, "ok": True, "diff_pixels": 0, "size": list(ia.size)}
    mask = diff.point(lambda v: 255 if v else 0).convert("L").point(lambda v: 255 if v else 0)
    pixels = sum(mask.histogram()[1:])
    peak = max(hi for _, hi in diff.getextrema())
    ok = peak <= MAX_DIFF
    if diff_out:
        mask.save(diff_out)
    h = ia.size[1]
    return {"identical": False, "ok": ok, "diff_pixels": pixels, "diff_bbox": list(bbox), "max_channel_diff": peak,
            "diff_band": f"y {bbox[1] / h:.1%}–{bbox[3] / h:.1%}, x {bbox[0] / ia.size[0]:.1%}–{bbox[2] / ia.size[0]:.1%}",
            "size": list(ia.size), "why": None if ok else f"pixels differ by up to {peak} of 255"}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", default="HEAD", help="git revision the existing media were last reviewed against")
    ap.add_argument("--out", type=Path, help="keep screenshots and report here (outside the repo); default a temp dir")
    ap.add_argument("--record", action="store_true", help="keep the report as perf/media/compact-unchanged.json")
    ap.add_argument("--current-receipt", type=Path, help="reuse a source-verified current iPhone Debug candidate")
    ap.add_argument("--lock-wait", type=float, default=0, help="bounded original simulator queue wait")
    ap.add_argument("--load-wait", type=float, default=0, help="bounded original quiet-window wait")
    a = ap.parse_args(argv)
    if any(not math.isfinite(v) or v < 0 for v in (a.lock_wait, a.load_wait)):
        ap.error("wait budgets must be finite and nonnegative")
    base = subprocess.run(["git", "-C", str(REPO), "rev-parse", a.base], capture_output=True, text=True,
                          check=True).stdout.strip()
    work = Path(tempfile.mkdtemp(prefix="wrongbook-compact."))
    out = (a.out or work / "out").expanduser().resolve()
    if out == REPO or out.is_relative_to(REPO):
        print("--out 必须在仓外", file=sys.stderr)
        return 2
    before_ui = ui_snapshot()
    started = dt.datetime.now().astimezone()
    fixture = [sys.executable, str(REPO / "scripts/demo/fixture.py")]
    try:
        src_base = work / "base-src"
        src_base.mkdir()
        tar = subprocess.run(["git", "-C", str(REPO), "archive", base], capture_output=True, check=True).stdout
        subprocess.run(["tar", "-x", "-C", str(src_base)], input=tar, check=True)
        built = {"base": build_candidate(src_base, work / "base"),
                 "current": (sim_lane.reuse_build(a.current_receipt, APP_ID, REPO, "iphone", "WrongBook", "Debug")
                             if a.current_receipt else build_candidate(REPO, work / "current"))}
        for b in built.values():
            app = Path(b["app_path"])
            dylib = app / "WrongBook.debug.dylib"      # Debug: the code lives here, the executable is a launcher stub
            b["code_sha256"] = sha(dylib) if dylib.is_file() else b["executable_sha256"]
            b["embeds_watch_app"] = (app / "Watch").is_dir()
        r = subprocess.run([*fixture, "start", "--dir", str(work / "fixture"), "--json"],
                           capture_output=True, text=True, timeout=120)
        if r.returncode:
            raise SystemExit(f"演示服务没起来：{(r.stderr or r.stdout)[-300:]}")
        lib = json.loads(r.stdout)
        args = ["-api_base", lib["url"], "-dev_user", lib["user"], "-dev_pw", lib["pw"]]
        hashes = {}
        try:
            anonymous = subprocess.run([*fixture, "start", "--dir", str(work / "anonymous"), "--anonymous", "--json"],
                                       capture_output=True, text=True, timeout=120)
            if anonymous.returncode:
                raise SystemExit("匿名登录界面夹具没起来")
            login_url = json.loads(anonymous.stdout)["url"]
            sim_admission.admit(sim_lane, reuse=False, label="wrong-book compact_unchanged")
            dev = sim_lane.ensure_device("iphone", "iPhone-17-Pro", name="WrongBook Media QA")
            with sim_admission.hooked(sim_lane, run_record=str(out / "simulator-run.json"), label="wrong-book compact_unchanged"), \
                    sim_lane.Session("iphone", dev["udid"], label="wrong-book compact_unchanged",
                                     lock_wait=a.lock_wait, load_wait=a.load_wait) as s:
                sim_lane.simctl("status_bar", dev["udid"], "override", "--time", "9:41", "--dataNetwork", "wifi",
                                "--wifiMode", "active", "--wifiBars", "3", "--cellularMode", "active",
                                "--cellularBars", "4", "--batteryState", "charged", "--batteryLevel", "100",
                                check=False)
                for side in ("base", "current"):
                    hashes[side] = shots(dev["udid"], s, Path(built[side]["app_path"]), args, out / side, login_url,
                                         require_ready=side == "current")
        finally:
            subprocess.run([*fixture, "stop", "--dir", str(work / "fixture")], capture_output=True)
            subprocess.run([*fixture, "stop", "--dir", str(work / "anonymous")], capture_output=True)
    except sim_lane.Busy as exc:
        print(f"推迟：{exc}", file=sys.stderr)
        return 75
    after_ui = ui_snapshot()
    (out / "diff").mkdir(parents=True, exist_ok=True)
    screens = {name: {**compare(out / "base" / f"{name}.png", out / "current" / f"{name}.png",
                                out / "diff" / f"{name}.png"),
                      "base_sha256": hashes["base"][name], "current_sha256": hashes["current"][name],
                      **({"report_only": REPORT_ONLY[name]} if name in REPORT_ONLY else {})}
               for name, *_ in SCREENS}
    unchanged = (all(v["ok"] for k, v in screens.items() if k not in REPORT_ONLY)
                 and before_ui["sha256"] == after_ui["sha256"])
    report = {"schema_version": 1, "app": APP_ID, "checked_at": started.isoformat(timespec="seconds"),
              "base_commit": base, "ui_source": before_ui, "ui_source_unchanged_during_check": before_ui == after_ui,
              "device": f"{dev['name']} ({dev['device_type']}) / {dev['runtime'].rsplit('.', 1)[-1]} simulator",
              "builds": {k: {x: v.get(x) for x in ("configuration", "version", "build", "executable_sha256", "code_sha256",
                                                   "embeds_watch_app", "sdk")}
                         for k, v in built.items()},
              "data": "fictional demo library (scripts/demo/fixture.py), same fixture for both builds, status bar 9:41; login uses anonymous fixture rejecting every cookie and account write",
              "rule": f"identical, or no pixel differs by more than {MAX_DIFF}/255 in any channel "
                      "(system glass dither / scroll indicator / clock; layout changes are far above it)",
              "verdict_screens": [name for name, *_ in SCREENS if name not in REPORT_ONLY],
              "screens": screens, "unchanged": unchanged}
    (out / "summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    if a.record:
        record(report, out / "summary.json")
    shutil.rmtree(work / "base", ignore_errors=True)
    shutil.rmtree(work / "current", ignore_errors=True)
    print(json.dumps({"unchanged": unchanged, "out": str(out),
                      "screens": {k: ("report only: " if k in REPORT_ONLY else "")
                                  + ("identical" if v.get("identical") else "ok" if v["ok"] else str(v.get("why")))
                                  for k, v in screens.items()}}, ensure_ascii=False))
    return 0 if unchanged else 1


def record(report: dict, summary: Path) -> None:
    import yaml
    sop = (yaml.safe_load((REPO / "project.yaml").read_text(encoding="utf-8")) or {}).get("sop") or {}
    meta = (REPO / sop["media_meta"]).resolve()
    if not meta.is_relative_to(REPO.resolve()):
        raise ValueError("media_meta 必须是本仓派生复核索引；原始审核登记保持只读")
    doc = json.loads(meta.read_text(encoding="utf-8"))
    kept = REPO / "perf/media/compact-unchanged.json"
    kept.parent.mkdir(parents=True, exist_ok=True)
    if kept.exists():
        archive = kept.parent / "previous-reviews" / (sha(kept) + ".json")
        archive.parent.mkdir(exist_ok=True)
        if not archive.exists(): shutil.copyfile(kept, archive)
    shutil.copyfile(summary, kept)
    doc.setdefault("ui_reviews", []).append({
        "checked_at": report["checked_at"], "base_commit": report["base_commit"],
        "ui_source_sha256": report["ui_source"]["sha256"], "ui_source_globs": report["ui_source"]["globs"],
        "unchanged": report["unchanged"], "device": report["device"], "rule": report["rule"],
        "verdict_screens": report["verdict_screens"],
        "screens": {k: ("report only: " if k in REPORT_ONLY else "")
                    + ("identical" if v.get("identical") else
                       f"{v.get('diff_pixels')} px differ, max {v.get('max_channel_diff')}/255 ({v.get('diff_band')})"
                       if v["ok"] else
                       f"{v.get('why')}; {v.get('diff_pixels')} px ({v.get('diff_band')})" if v.get("diff_pixels") else
                       str(v.get("why")))
                    for k, v in report["screens"].items()},
        "current_sha256": {k: v["current_sha256"] for k, v in report["screens"].items()},
        "report": "01-源程序/perf/media/compact-unchanged.json", "report_sha256": sha(kept),
        "tool": "01-源程序/scripts/media/compact_unchanged.py",
        # The note must follow the verdict: a changed result once carried the "nothing moved" sentence (2026-10-05).
        "note": ("iPhone 窄屏在当前工作树与 base 之间逐屏比对：预览视频与 iPhone 商店截图所示的画面（verdict_screens）"
                 "与 base 相同，base 之后的改动没有碰到它们。录像仍是 1.0 (18) 真机原片，不因此变成新录制；"
                 "界面源码再改就重跑本工具。" if report["unchanged"] else
                 "iPhone 窄屏在当前工作树与 base 之间逐屏比对，有画面与 base 不同（见 screens）：现有 iPhone 素材不能凭本条沿用，"
                 "需按变化的画面重录或重截。")})
    meta.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    sys.exit(main())
