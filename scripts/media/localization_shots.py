#!/usr/bin/env python3
"""Capture the main iPhone views in English and Simplified Chinese, without a GUI.

    ~/Dev/.venv/bin/python scripts/media/localization_shots.py --receipt /path/build.json

The caller builds through sim_lane.build. This tool only reuses a source-verified iPhone Debug receipt, starts the
existing fictional fixtures, and captures login/library/import/review through sim_admission and sim_lane.Session.
Each language starts with a fresh simulator installation. Login uses the anonymous fixture, which rejects every
cookie. No real account, phone, Simulator.app window, App Store or TestFlight is used. The strict simulator lock/load
budgets are both zero: busy runs write result.json and return 75 for Chapter's original queue to resume.

Exit 0 means the screenshots were captured, not that a human has reviewed truncation or every translation. If the
existing shared macOS Vision OCR binary is installed, OCR text/boxes are saved for that review without any GUI or
tool compilation. Fictional lesson names, questions, nickname and review topics may intentionally remain Chinese.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import html
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
APP_ID = "wrong-book-ios"
BUNDLE = "cyou.tianli.wrongbook"
LABEL = "wrong-book English UI screenshots"
sys.path.insert(0, str(Path.home() / "Dev/tools/dev/lib/tools/macapp/ios"))
import sim_lane  # noqa: E402
sys.path.insert(0, str(Path.home() / "Apps/chapter/engine"))
import sim_admission  # noqa: E402
import app_sop  # noqa: E402

LANGUAGES = {"en": ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"],
             "zh-Hans": ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]}
SCREENS = [("login", None), ("library", "0"), ("import", "1"), ("review", "2")]
OCR_BINARY = Path.home() / "Dev/tools/dev/lib/tools/ocr/vision_ocr_box"
HAN = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\U00020000-\U0003134f]")


def timestamp() -> str:
    return dt.datetime.now().astimezone().isoformat(timespec="seconds")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def code_binding() -> str:
    """Read Chapter's production input binding, independently of capture scripts."""
    app = next(app for app in app_sop.load_apps(APP_ID)
               if Path(app["repo"]).resolve() == REPO)
    _, business = app_sop.business_code_files(app, {})
    if not business:
        raise sim_lane.LaneError("missing production inputs for localization capture")
    return app_sop.digest_value([business])


def bind_screenshots(report: dict, out: Path, before: str, after: str) -> None:
    """Publish the shared acceptor contract only after unchanged-source capture."""
    if before != after:
        raise sim_lane.LaneError("production inputs changed during localization capture")
    screenshots = {}
    for language in LANGUAGES:
        screenshots[language] = []
        for name, _ in SCREENS:
            shot = report["screens"][language][name]
            path = Path(shot["path"]).resolve()
            if not path.is_relative_to(out.resolve()) or sha(path) != shot["sha256"]:
                raise sim_lane.LaneError("localization screenshot is outside output or changed: " + name)
            screenshots[language].append(str(path.relative_to(out.resolve())))
    report.update(input_sha256=before, screenshots=screenshots)


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def start_fixture(directory: Path, anonymous: bool = False) -> dict:
    command = [sys.executable, str(REPO / "scripts/demo/fixture.py"), "start", "--dir", str(directory)]
    if anonymous:
        command.append("--anonymous")
    result = subprocess.run([*command, "--json"], capture_output=True, text=True, timeout=120)
    if result.returncode:
        raise sim_lane.LaneError("fictional fixture failed: " + (result.stderr or result.stdout)[-500:])
    return json.loads(result.stdout)


def stop_fixture(directory: Path) -> None:
    subprocess.run([sys.executable, str(REPO / "scripts/demo/fixture.py"), "stop", "--dir", str(directory)],
                   capture_output=True, timeout=30)


def stable_shot(session, target: Path) -> dict:
    """Use compact_unchanged's bounded frame-stability check after data-bearing readiness."""
    time.sleep(8)
    previous = target.with_name("." + target.stem + ".previous.png")
    session.shot(previous)
    difference = None
    try:
        for _ in range(10):
            time.sleep(1.2)
            session.shot(target)
            frame = sim_lane.Frame(target, "iphone")
            difference = frame.diff(sim_lane.Frame(previous, "iphone"))
            if not frame.blank() and difference <= 0.0005:
                return {"stable": True, "diff_previous": difference, "size": list(sim_lane.png_size(target))}
            shutil.copyfile(target, previous)
    finally:
        previous.unlink(missing_ok=True)
    raise sim_lane.LaneError(f"screenshot did not settle: {target.name}, difference={difference}")


def capture_language(session, app: Path, executable: str, language: str, fixture: dict,
                     anonymous: dict, out: Path) -> dict:
    language_args = LANGUAGES[language]
    sim_lane.simctl("uninstall", session.udid, BUNDLE, check=False)
    session.install(app)
    screens = {}
    try:
        for name, tab in SCREENS:
            target = out / language / f"{name}.png"
            target.parent.mkdir(parents=True, exist_ok=True)
            readiness = None
            if tab is None:
                args = ["-api_base", anonymous["url"], *language_args]
                sim_lane.simctl("launch", "--terminate-running-process", session.udid, BUNDLE, *args, timeout=120)
            else:
                args = ["-api_base", fixture["url"], "-dev_user", fixture["user"], "-dev_pw", fixture["pw"],
                        "-tab", tab, *language_args]
                ready = session.launch(BUNDLE, args, "log", 120, None, executable, functional_thin=True)
                if ready.get("errors") or ready.get("ready_signal") != "os_log":
                    raise sim_lane.LaneError(f"{language}/{name} did not become ready: {ready.get('errors')}")
                readiness = {key: ready.get(key) for key in ("ready_seconds", "ready_signal", "notes")}
            frame = stable_shot(session, target)
            screens[name] = {"path": str(target), "sha256": sha(target), "captured_at": timestamp(),
                             "language": language, "locale": language_args[-1], "language_arguments": language_args,
                             "fresh_install_for_language": True,
                             "anonymous_fixture": tab is None, "readiness": readiness, **frame}
            session.terminate(BUNDLE)
    finally:
        session.terminate(BUNDLE)
        sim_lane.simctl("uninstall", session.udid, BUNDLE, check=False)
    return screens


def ocr_shot(image: Path) -> dict:
    if not OCR_BINARY.is_file() or not os.access(OCR_BINARY, os.X_OK):
        return {"status": "unavailable", "reason": "existing shared Vision OCR binary is not installed"}
    try:
        result = subprocess.run([str(OCR_BINARY), str(image)], capture_output=True, text=True, timeout=90)
        line = next((line for line in result.stdout.splitlines() if line.startswith("{")), None)
        if result.returncode or line is None:
            return {"status": "unavailable", "reason": "shared Vision OCR did not return a result"}
        value = json.loads(line)
        lines = value.get("lines", [])
        return {"status": "captured", "engine": "macOS Vision (shared vision_ocr_box)", "lines": lines,
                "han_lines_for_review": [row for row in lines if HAN.search(str(row.get("t", "")))]}
    except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
        return {"status": "unavailable", "reason": type(exc).__name__}


def write_gallery(out: Path, report: dict) -> None:
    rows = []
    for screen, _ in SCREENS:
        cells = []
        for language in LANGUAGES:
            shot = report["screens"][language][screen]
            source = html.escape(f"{language}/{screen}.png", quote=True)
            cells.append(f'<figure><a href="{source}"><img src="{source}" alt="{language} {screen}"></a>'
                         f'<figcaption>{html.escape(language)} · {html.escape(screen)} · '
                         f'{html.escape(shot["sha256"][:12])}</figcaption></figure>')
        rows.append('<section><h2>' + html.escape(screen) + '</h2><div class="pair">' + ''.join(cells) + '</div></section>')
    document = '''<!doctype html><html lang="zh-Hans"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Mistake Notebook · English UI review</title>
<style>body{margin:0;padding:28px;font:16px/1.6 system-ui;color:#24332e;background:#f7f8f5}main{max-width:1100px;margin:auto}
h1{font-size:26px}h2{font-size:20px}.pair{display:grid;grid-template-columns:1fr 1fr;gap:24px}figure{margin:0;padding:16px;
background:white;border:1px solid #e3e8e1;border-radius:14px}img{display:block;max-width:100%;max-height:850px;margin:auto}
figcaption{font-size:13px;color:#69756f;margin-top:12px;text-align:center}section{margin:28px 0}a{color:#2b6653}
@media(max-width:650px){body{padding:16px}.pair{gap:12px}figure{padding:8px}}</style><main>
<h1>Mistake Notebook · 中英文界面对照</h1><p>iPhone 无窗口模拟器；虚构演示资料。请逐屏核对翻译、截断和布局。
课名、题目、昵称及题型属于演示用户内容，可能保留中文。截图完成不代表已通过目视复核。</p>
<p><a href="result.json">构建、语言、时间与截图 SHA-256 记录</a></p>'''
    (out / "index.html").write_text(document + ''.join(rows) + '</main></html>\n', encoding="utf-8")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--receipt", type=Path, required=True, help="existing source-verified sim_lane iPhone Debug receipt")
    parser.add_argument("--out", type=Path, default=REPO / "perf/acceptance/l10n")
    args = parser.parse_args(argv)
    receipt = args.receipt.expanduser().resolve()
    out = args.out.expanduser().resolve()
    if out == REPO or out in REPO.parents:
        parser.error("--out must be a dedicated evidence directory")
    out.mkdir(parents=True, exist_ok=True)
    report = {"schema_version": 1, "app": APP_ID, "started_at": timestamp(), "status": "running",
              "screens": {}, "language_arguments": LANGUAGES, "lock_wait": 0, "load_wait": 0,
              "capture_method": "headless simctl screenshot via sim_lane.Session; no Simulator.app",
              "fixture_source_sha256": sha(REPO / "scripts/demo/fixture.py"),
              "data": "fictional scripts/demo/fixture.py library; anonymous login rejects all cookies",
              "manual_review": "required: translation completeness and text truncation; user content is excluded"}
    work = Path(tempfile.mkdtemp(prefix="wrongbook-l10n."))
    code = 1
    try:
        before = code_binding()
        built = sim_lane.reuse_build(receipt, APP_ID, REPO, "iphone", "WrongBook", "Debug")
        app = Path(built["app_path"])
        info = sim_lane.bundle_info(app)
        executable = Path(info["executable"])
        dylib = executable.with_name(executable.name + ".debug.dylib")
        report["build"] = {key: built.get(key) for key in
                           ("app_path", "scheme", "platform", "configuration", "version", "build", "sdk", "xcode")}
        report["build"].update(receipt=str(receipt), receipt_sha256=sha(receipt),
                               source_sha256=built["reuse"]["input_sha256"],
                               source_file_count=built["reuse"]["source_file_count"],
                               executable_sha256=sha(executable), code_sha256=sha(dylib if dylib.is_file() else executable))
        if sim_lane.simulator_app_pids():
            raise sim_lane.Busy("Simulator.app is already running; keep the user's windows unchanged")
        admission = sim_admission.admit(sim_lane, reuse=False, label=LABEL)
        report["admission"] = admission
        if admission.get("deferred"):
            raise sim_lane.Busy(admission["note"])
        device = sim_lane.ensure_device("iphone", "iPhone-17-Pro", name="WrongBook Media QA")
        report["device"] = device
        with sim_admission.hooked(sim_lane, run_record=str(out / "simulator-run.json"), label=LABEL), \
                sim_lane.Session("iphone", device["udid"], label=LABEL, lock_wait=0, load_wait=0) as session:
            sim_lane.simctl("status_bar", device["udid"], "override", "--time", "9:41", "--dataNetwork", "wifi",
                            "--wifiMode", "active", "--wifiBars", "3", "--cellularMode", "active", "--cellularBars", "4",
                            "--batteryState", "charged", "--batteryLevel", "100", check=False)
            fixture = start_fixture(work / "fixture")
            anonymous = start_fixture(work / "anonymous", anonymous=True)
            for language in LANGUAGES:
                report["screens"][language] = capture_language(session, app, str(executable), language,
                                                              fixture, anonymous, out)
                write_json(out / "result.json", report)
        # All OCR happens after releasing the simulator's strict quiet-window resources.
        for screens in report["screens"].values():
            for shot in screens.values():
                shot["ocr"] = ocr_shot(Path(shot["path"]))
        verified = sim_lane.reuse_build(receipt, APP_ID, REPO, "iphone", "WrongBook", "Debug")
        report["source_unchanged_during_capture"] = (
            verified["reuse"]["input_sha256"] == report["build"]["source_sha256"])
        if not report["source_unchanged_during_capture"]:
            raise sim_lane.LaneError("source changed while the screenshots were being captured")
        bind_screenshots(report, out, before, code_binding())
        report.update(status="captured", ok=True)
        write_gallery(out, report)
        report["gallery"] = str(out / "index.html")
        code = 0
    except sim_lane.Busy as exc:
        report.update(status="deferred", ok=False, auto=True, resource="simulator", state="waiting_resource", detail=str(exc))
        code = 75
    except (sim_lane.LaneError, OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        report.update(status="failed", ok=False, detail=str(exc))
    finally:
        for name in ("fixture", "anonymous"):
            try:
                stop_fixture(work / name)
            except (OSError, subprocess.SubprocessError):
                pass
        shutil.rmtree(work, ignore_errors=True)
        report.update(finished_at=timestamp(), exit_code=code)
        write_json(out / "result.json", report)
    print(json.dumps({"status": report["status"], "exit_code": code, "out": str(out),
                      "result": str(out / "result.json"), "detail": report.get("detail")}, ensure_ascii=False))
    return code


if __name__ == "__main__":
    sys.exit(main())
