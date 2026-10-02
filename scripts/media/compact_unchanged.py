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

--record keeps the report as perf/media/compact-unchanged.json and appends the result to the media provenance
(sop.media_meta) under ui_reviews, bound to the sop.ui source snapshot Chapter computes (app_sop.app_source_snapshot),
so the existing iPhone media stay valid only while that review binds the current UI source (same as the Growth
Treasury pilot). The base for the 2026-10-02 five-platform change is 89c699a, the last commit before it. Exit 0
unchanged, 1 changed or failed, 75 simulator lock held / machine loaded (run again later).
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
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

# (screen, launch args, extra seconds before the stability check). The opened question is a WKWebView page that
# paints after the native frame is already still: without the extra wait one side can be shot blank (2026-10-02).
SCREENS = [("login", None, 0), ("library", ["-tab", "0"], 0), ("import", ["-tab", "1"], 0), ("review", ["-tab", "2"], 0),
           ("question", ["-tab", "0", "-library.openQuestion", "f2"], 10)]
MAX_DIFF = 2          # of 255 per channel: perceptually identical; any layout / colour change is far above it


def sha(path: Path) -> str:
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def ui_snapshot() -> dict:
    sys.path.insert(0, str(Path.home() / "Apps/chapter/engine"))
    import app_sop  # noqa: E402  (the snapshot Chapter's media check reads sop.ui through)
    app = app_sop.load_apps(APP_ID)[0]
    snap = app_sop.app_source_snapshot(app, app["sop"]["ui"])
    return {"globs": app["sop"]["ui"], "sha256": snap["sha256"], "file_count": snap["file_count"]}


def shots(udid: str, s, app: Path, args: list[str], out: Path) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    sim_lane.simctl("uninstall", udid, BUNDLE, check=False)
    s.install(app)
    hashes = {}
    for name, extra, more in SCREENS:
        launch = args[:2] if extra is None else [*args, *extra]   # login: library address only, no dev login
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
    a = ap.parse_args(argv)
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
        built = {"base": sim_lane.build(src_base, "WrongBook", "iphone", "Debug", work / "base"),
                 "current": sim_lane.build(REPO, "WrongBook", "iphone", "Debug", work / "current")}
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
        dev = sim_lane.ensure_device("iphone", "iPhone-17-Pro")
        hashes = {}
        try:
            with sim_lane.Session("iphone", dev["udid"], label="wrong-book compact_unchanged") as s:
                sim_lane.simctl("status_bar", dev["udid"], "override", "--time", "9:41", "--dataNetwork", "wifi",
                                "--wifiMode", "active", "--wifiBars", "3", "--cellularMode", "active",
                                "--cellularBars", "4", "--batteryState", "charged", "--batteryLevel", "100",
                                check=False)
                for side in ("base", "current"):
                    hashes[side] = shots(dev["udid"], s, Path(built[side]["app_path"]), args, out / side)
        finally:
            subprocess.run([*fixture, "stop", "--dir", str(work / "fixture")], capture_output=True)
    except sim_lane.Busy as exc:
        print(f"推迟：{exc}", file=sys.stderr)
        return 75
    after_ui = ui_snapshot()
    (out / "diff").mkdir(parents=True, exist_ok=True)
    screens = {name: {**compare(out / "base" / f"{name}.png", out / "current" / f"{name}.png",
                                out / "diff" / f"{name}.png"),
                      "base_sha256": hashes["base"][name], "current_sha256": hashes["current"][name]}
               for name, *_ in SCREENS}
    unchanged = all(v["ok"] for v in screens.values()) and before_ui["sha256"] == after_ui["sha256"]
    report = {"schema_version": 1, "app": APP_ID, "checked_at": started.isoformat(timespec="seconds"),
              "base_commit": base, "ui_source": before_ui, "ui_source_unchanged_during_check": before_ui == after_ui,
              "device": f"{dev['name']} ({dev['device_type']}) / {dev['runtime'].rsplit('.', 1)[-1]} simulator",
              "builds": {k: {x: v.get(x) for x in ("configuration", "version", "build", "executable_sha256", "code_sha256",
                                                   "embeds_watch_app", "sdk")}
                         for k, v in built.items()},
              "data": "fictional demo library (scripts/demo/fixture.py), same fixture for both builds, status bar 9:41",
              "rule": f"identical, or no pixel differs by more than {MAX_DIFF}/255 in any channel "
                      "(system glass dither / scroll indicator / clock; layout changes are far above it)",
              "screens": screens, "unchanged": unchanged}
    (out / "summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    if a.record:
        record(report, out / "summary.json")
    shutil.rmtree(work / "base", ignore_errors=True)
    shutil.rmtree(work / "current", ignore_errors=True)
    print(json.dumps({"unchanged": unchanged, "out": str(out),
                      "screens": {k: ("identical" if v.get("identical") else "ok" if v["ok"] else v.get("why"))
                                  for k, v in screens.items()}}, ensure_ascii=False))
    return 0 if unchanged else 1


def record(report: dict, summary: Path) -> None:
    import yaml
    kept = REPO / "perf/media/compact-unchanged.json"
    kept.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(summary, kept)
    sop = (yaml.safe_load((REPO / "project.yaml").read_text(encoding="utf-8")) or {}).get("sop") or {}
    meta = (REPO / sop["media_meta"]).resolve()
    doc = json.loads(meta.read_text(encoding="utf-8"))
    doc.setdefault("ui_reviews", []).append({
        "checked_at": report["checked_at"], "base_commit": report["base_commit"],
        "ui_source_sha256": report["ui_source"]["sha256"], "ui_source_globs": report["ui_source"]["globs"],
        "unchanged": report["unchanged"], "device": report["device"], "rule": report["rule"],
        "screens": {k: ("identical" if v.get("identical") else
                        f"{v.get('diff_pixels')} px differ, max {v.get('max_channel_diff')}/255 ({v.get('diff_band')})"
                        if v["ok"] else v.get("why"))
                    for k, v in report["screens"].items()},
        "current_sha256": {k: v["current_sha256"] for k, v in report["screens"].items()},
        "report": "01-源程序/perf/media/compact-unchanged.json", "report_sha256": sha(kept),
        "tool": "01-源程序/scripts/media/compact_unchanged.py",
        "note": ("iPhone 窄屏（预览视频与 iPhone 商店截图所示布局）在当前工作树与五平台改动前的 base 之间逐屏比对：宽屏布局、"
                 "Watch、Vision、Mac 等改动没有碰到 iPhone 画面。录像仍是 1.0 (18) 真机原片，不因此变成新录制；"
                 "界面源码再改就重跑本工具。")})
    meta.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    sys.exit(main())
