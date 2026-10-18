#!/usr/bin/env python3
"""WrongBook real product acceptance. Default: installed Mac/simulator packages.

--build --platform mac|iphone produces a source-bound sim_lane candidate/receipt.
--app/--receipt and --ios-app/--ios-receipt accept explicit candidates, without Mac installation.
Only the private acceptance simulator receives --ios-app. No device/user data or synthetic input.
"""
from __future__ import annotations
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import threading
import time
import uuid
import zipfile

SCRIPT_ROOT = Path(__file__).resolve().parents[2]
# Chapter keeps evidence and build receipts in the registered repository while
# executing the frozen script from a disposable worktree.
ROOT = Path(os.environ.get("SOP_SOURCE_REPO") or SCRIPT_ROOT).expanduser().resolve()
sys.path.insert(0, str(Path.home() / "Dev/tools/dev/lib/tools/macapp/ios"))
sys.path.insert(0, str(Path.home() / "Apps/chapter/engine"))
import sim_lane
import app_sop
import product_basics
APP_ID = "wrong-book-ios"

def production_files(app):
    _, files = app_sop.business_code_files(app, {})
    base = app_sop.source_base(app)
    return {str(Path(path).relative_to(base)) if Path(path).is_relative_to(base) else path: digest
            for path, digest in files.items()}

def verify_source():
    if ROOT == SCRIPT_ROOT:
        return
    registered = app_sop.load_apps(APP_ID)[0]
    if (Path(registered["repo"]).resolve() != ROOT
            or Path(os.environ.get("SOP_REPO") or "/").resolve() != SCRIPT_ROOT
            or os.environ.get("SOP_APP_ID") != APP_ID):
        raise sim_lane.LaneError("Chapter 工作树/产品源目录身份不匹配")
    frozen = {**registered, "repo": SCRIPT_ROOT,
              "sop": json.loads(os.environ.get("SOP_CONFIG") or json.dumps(registered["sop"]))}
    current, copied = production_files(registered), production_files(frozen)
    if not current or current != copied:
        raise sim_lane.Busy("冻结的生产输入已变化，交原队列重新绑定")

def output_directory():
    out = Path(os.environ.get("SOP_OUT_DIR", ROOT / "perf/acceptance")).resolve()
    if not out.is_relative_to(ROOT / "perf/acceptance"):
        raise sim_lane.LaneError("验收输出必须位于产品源目录 perf/acceptance 下")
    return out

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def alive(pid):
    try: os.kill(pid, 0); return True
    except ProcessLookupError: return False

def write(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n")

def artifacts(app):
    return {str(p.relative_to(app)): sha(p) for p in sorted(app.rglob("*")) if p.is_file() and not p.is_symlink()}

def owner_snapshot():
    # Only hashes leave this read-only sample; no production preferences or account values enter evidence.
    home = Path.home()
    paths = [home / 'Library/Preferences/cyou.tianli.wrongbook.plist',
             home / 'Library/Containers/cyou.tianli.wrongbook/Data/Library/Preferences/cyou.tianli.wrongbook.plist']
    installed = Path('/Applications/错题本.app')
    return {'preferences': {str(p): sha(p) if p.is_file() else None for p in paths},
            'installed_artifacts': artifacts(installed) if installed.is_dir() else None}

class StoreFixture(BaseHTTPRequestHandler):
    mode = "new"
    requests = []
    def do_GET(self):
        if self.path.startswith("/mode/"):
            type(self).mode = self.path.split("/mode/", 1)[1]; data, code = b"{}", 200
        elif self.path.startswith("/lookup?"):
            mode = type(self).mode; type(self).requests.append({"path": self.path, "mode": mode})
            if mode == "unavailable": data, code = b"unavailable", 503
            elif mode == "corrupt": data, code = b"{broken", 200
            else:
                data, code = json.dumps({"results": [{"trackId": 6806626967, "bundleId": "cyou.tianli.wrongbook", "version": "99.0", "trackViewUrl": "https://apps.apple.com/app/id6806626967"}]}).encode(), 200
        else: data, code = b"{}", 404
        self.send_response(code); self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
    def log_message(self, *_): pass

def verified(receipt, platform, selected):
    if platform == "mac" and selected is None:
        # Installed delivery is bound by Chapter's production-input/installed-artifact
        # verifier, not an old sim_lane temporary source copy (which may be pruned).
        app = Path("/Applications/错题本.app")
        registered = app_sop.load_apps(APP_ID)[0]
        binding = {key: os.environ.get(key) for key in ("SOP_CODE_BINDING_SHA256", "SOP_BUILD_CURRENT")}
        if not any(value is not None for value in binding.values()):
            binding = app_sop.acceptance_code_environment(registered, bundle=app)
        _, business = app_sop.business_code_files(registered, {})
        if (not business or binding["SOP_BUILD_CURRENT"] != "1"
                or binding["SOP_CODE_BINDING_SHA256"] != app_sop.digest_value([business])):
            raise sim_lane.LaneError("装机生产输入绑定未通过（SOP_BUILD_CURRENT / SOP_CODE_BINDING_SHA256）")
        info = sim_lane.bundle_info(app)
        if not info["mac"] or info["bundle_id"] != "cyou.tianli.wrongbook":
            raise sim_lane.LaneError("装机平台或 bundle id 不匹配")
        signed = subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)],
                                capture_output=True, text=True, timeout=30)
        if signed.returncode:
            raise sim_lane.LaneError("装机签名核验失败：" + (signed.stderr or signed.stdout)[-300:])
        return {**info, "executable_sha256": sha(info["executable"]),
                "product_artifacts": artifacts(app), "code_binding": binding}, app
    built = sim_lane.reuse_build(receipt, APP_ID, ROOT, platform, "WrongBook", "Debug")
    app = selected.resolve() if selected else (Path("/Applications/错题本.app") if platform == "mac" else None)
    expected = built.get("product_artifacts")
    if not expected:
        raise sim_lane.LaneError("receipt 缺少完整包 SHA；请先 --build")
    if selected and selected.resolve() != Path(built["app_path"]).resolve():
        raise sim_lane.LaneError("候选 --app 与 receipt 绑定路径不同")
    if app and artifacts(app) != expected:
        raise sim_lane.LaneError("所验 App 与当前源码 receipt 的完整包 SHA 不同；默认验已装版，候选须显式 --app")
    return built, app

def exercise(platform, executable, run, digest, env, udid=None, bundle=None):
    suite = "wrongbook.basics." + uuid.uuid4().hex
    product_run = run
    if platform != 'mac':
        # The actual iOS process writes inside its own sandbox, then the host reads those originals.
        container = Path(sim_lane.simctl('get_app_container', udid, bundle, 'data').stdout.strip())
        product_run = container / 'tmp' / suite
        product_run.mkdir(parents=True)
    package = run / 'check-only.zip'
    if platform == 'mac':
        with zipfile.ZipFile(package, 'w', zipfile.ZIP_DEFLATED) as archive:
            archive.writestr('README.txt', 'Isolated WrongBook update-check fixture. No application or installer.\n')
    result = {}
    for phase in ("exercise", "readback"):
        output = product_run / f"{phase}.json"
        settings = {"APP_LIFECYCLE_SUPPORT_DIR": str(product_run / "support"), "APP_LIFECYCLE_CLOUD_DIR": str(product_run / "cloud"),
                    "WRONGBOOK_BASICS_DEFAULTS": suite, "WRONGBOOK_BASICS_OUTPUT": str(output),
                    "WRONGBOOK_BASICS_DIGEST": digest, "WRONGBOOK_BASICS_PHASE": phase}
        if platform == 'mac': settings['WRONGBOOK_BASICS_PACKAGE'] = str(package)
        if platform == "mac":
            cmd = [str(executable), "--ui-self-test"]
            child_env = dict(env, **settings)
        else:
            cmd = ["xcrun", "simctl", "launch", "--console", "--terminate-running-process", udid, bundle, "--ui-self-test"]
            child_env = dict(env, **{"SIMCTL_CHILD_" + k: v for k, v in settings.items()})
        done = sim_lane.run(cmd, timeout=100, check=False, env=child_env, sdk="macosx" if platform == "mac" else "iphonesimulator")
        (run / f"{phase}.log").write_text(done.stdout + done.stderr)
        if platform != 'mac':
            # simctl may return the launch PID before UIApplicationDelegate has run. Observe the
            # product's atomic output, not the launcher return code, before shutting down the device.
            deadline = time.monotonic() + 60
            match = re.search(r': (\d+)\s*(?:\n|$)', done.stdout)
            while not output.is_file() and time.monotonic() < deadline:
                if match and not alive(int(match[1])): break
                time.sleep(0.1)
        if not output.is_file():
            raise sim_lane.LaneError(f"{platform}/{phase} 无原始记录，退出 {done.returncode}：{(done.stderr or done.stdout)[-700:]}")
        raw = json.loads(output.read_text())
        if platform == 'mac': raw['process_exit'] = done.returncode
        else:
            raw['launch_exit'] = done.returncode
            deadline = time.monotonic() + 5
            while alive(raw['pid']) and time.monotonic() < deadline: time.sleep(0.05)
            raw['process_finished'] = not alive(raw['pid'])
        result[phase] = raw
        if product_run != run:
            shutil.copy2(output, run / output.name)
            screenshot = product_run / f'settings-{phase}.png'
            if screenshot.is_file(): shutil.copy2(screenshot, run / screenshot.name)
    if platform == "mac":
        subprocess.run(["/usr/bin/defaults", "delete", suite], capture_output=True, timeout=15)
    checks = {**result["exercise"]["checks"], **result["readback"]["checks"]}
    checks["settings.fresh_process"] = result["exercise"]["pid"] != result["readback"]["pid"] and result["readback"]["checks"].get("settings.persisted_readback") is True
    checks["settings.process_completed"] = all(r['process_exit'] == 0 for r in result.values()) if platform == 'mac' else all(r['launch_exit'] == 0 and r['process_finished'] for r in result.values())
    return checks, result

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--build", action="store_true"); p.add_argument("--platform", choices=("mac", "iphone"), default="mac")
    p.add_argument("--app", type=Path, default=os.environ.get("WRONGBOOK_BASICS_APP"))
    p.add_argument("--receipt", type=Path, default=os.environ.get("WRONGBOOK_BASICS_RECEIPT"))
    p.add_argument("--ios-app", type=Path, default=os.environ.get("WRONGBOOK_BASICS_IOS_APP"))
    p.add_argument("--ios-receipt", type=Path, default=os.environ.get("WRONGBOOK_BASICS_IOS_RECEIPT") or ROOT / "perf/product-basics-iphone-build.json")
    p.add_argument("--ui-only", action="store_true")
    args = p.parse_args()
    verify_source()
    receipt = args.receipt or ROOT / f"perf/product-basics-{args.platform}-build.json"
    if args.build:
        built = sim_lane.build(ROOT, "WrongBook", args.platform, "Debug", timeout=600)
        built["product_artifacts"] = artifacts(Path(built["app_path"])); write(receipt, built)
        print(json.dumps(built, ensure_ascii=False)); return 0
    spec = json.loads(os.environ["SOP_PRODUCT_BASICS_SPEC"]) if "SOP_PRODUCT_BASICS_SPEC" in os.environ else product_basics.spec(app_sop.load_apps(APP_ID)[0])
    assert spec["app_id"] == APP_ID
    out = output_directory()
    run = out / ("product-basics-" + uuid.uuid4().hex); run.mkdir(parents=True)
    owner_before = owner_snapshot()
    checks, originals, bindings = {}, {}, {}
    env = {k: v for k, v in os.environ.items() if not k.startswith(("APP_LIFECYCLE_", "SIMCTL_CHILD_", "WRONGBOOK_BASICS_"))}
    mac, app = verified(receipt, "mac", args.app)
    clone = run / "fixture/错题本.app"; clone.parent.mkdir(); shutil.copytree(app, clone, symlinks=True)
    if artifacts(clone) != mac["product_artifacts"]:
        raise sim_lane.LaneError("离屏副本与已核验的完整包 SHA 不同")
    info_path = clone / "Contents/Info.plist"; info = plistlib.loads(info_path.read_bytes())
    info.update(CFBundleIdentifier="wrongbook.basics.bundle." + uuid.uuid4().hex, LSUIElement=True)
    info_path.write_bytes(plistlib.dumps(info)); subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(clone)], check=True, capture_output=True, timeout=60)
    mac_run = run / "mac"; mac_run.mkdir()
    mac_checks, mac_raw = exercise("mac", clone / "Contents/MacOS/WrongBook", mac_run, spec["digest"], env)
    checks.update(mac_checks)
    bindings["mac"] = {"candidate": bool(args.app), "installed": not bool(args.app), "version": mac["version"], "build": mac["build"], "executable_sha256": mac["executable_sha256"], "product_artifacts": mac["product_artifacts"]}
    if args.app:
        bindings["mac"].update(receipt=str(receipt), receipt_sha256=sha(receipt))
    else:
        bindings["mac"]["code_binding"] = mac["code_binding"]
    originals["mac"] = mac_raw
    if not args.ui_only:
        ios, candidate = verified(args.ios_receipt, "iphone", args.ios_app)
        device = sim_lane.ensure_device("iphone", device_type="iPhone-17-Pro", name="wrongbook-basics-iPhone-17-Pro")
        udid = device["udid"] if isinstance(device, dict) else device
        server = ThreadingHTTPServer(("127.0.0.1", 0), StoreFixture); thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        try:
            with sim_lane.Session("iphone", udid, label="wrong-book product_basics", lock_wait=0, load_wait=0, boot_timeout=240) as session:
                if args.ios_app: session.install(candidate)
                location = Path(sim_lane.simctl("get_app_container", udid, ios["bundle_id"], "app").stdout.strip())
                if artifacts(location) != ios["product_artifacts"]: raise sim_lane.LaneError("模拟器已装包（含 Debug 动态库）与 receipt 不同")
                ios_run = run / "iphone"; ios_run.mkdir()
                ios_env = dict(env, SIMCTL_CHILD_WRONGBOOK_BASICS_SERVER=f"http://127.0.0.1:{server.server_port}")
                ios_checks, ios_raw = exercise("iphone", None, ios_run, spec["digest"], ios_env, udid=udid, bundle=ios["bundle_id"])
                for key, value in ios_checks.items(): checks[key] = checks.get(key, True) and value
                modes = {r["mode"] for r in StoreFixture.requests}
                checks["updates.real_http_fixture"] = {"new", "unavailable", "corrupt"} <= modes and all("id=6806626967" in r["path"] for r in StoreFixture.requests)
                originals["iphone"] = ios_raw
                bindings["iphone"] = {"candidate": bool(args.ios_app), "simulator_installed": True, "phone_installed": False, "udid": udid, "receipt": str(args.ios_receipt), "receipt_sha256": sha(args.ios_receipt), "version": ios["version"], "build": ios["build"], "executable_sha256": ios["executable_sha256"]}
            checks["settings.simulator_shutdown"] = udid not in sim_lane.booted_udids()
        finally:
            server.shutdown(); server.server_close(); thread.join(timeout=2)
    for row in spec["features"].values():
        for key in row["required_checks"]: checks.setdefault(key, False)
    owner_after = owner_snapshot()
    checks['settings.owner_configuration_unchanged'] = owner_before['preferences'] == owner_after['preferences']
    checks['updates.installed_bundle_unchanged'] = owner_before['installed_artifacts'] == owner_after['installed_artifacts']
    upstream = {str(path.relative_to(ROOT)): sha(path) for path in run.rglob("*") if path.is_file() and path.suffix in (".json", ".png", ".log")}
    raw = {"schema_version": 1, "app_id": APP_ID, "spec_digest": spec["digest"], "checks": checks,
           "binding": bindings, "originals": originals, "original_sha256": upstream, 'owner_before': owner_before, 'owner_after': owner_after,
           "scope": ("Mac 离屏原生设置、菜单动作；" + ("本次仅 Mac 界面自检；" if args.ui_only else "iOS 私有模拟器内真实产品控件与 HTTP；") + "仅本机隔离云链路，未验苹果跨设备传输；候选与已装版逐平台标记，未执行 Mac 装机或发布。")}
    raw_path = run / "raw.json"; write(raw_path, raw)
    features = {}
    for feature in spec["features"]:
        keys = [k for k in checks if k.startswith(feature + ".")]
        features[feature] = {"result": "passed" if keys and all(checks[k] is True for k in keys) else "failed", "method": "ui_automation" if feature == "settings" else "real_product", "evidence": str(raw_path.relative_to(ROOT)), "evidence_sha256": sha(raw_path), "checks": keys}
    passed = all(checks.values())
    target_note = 'Mac 候选未装机' if args.app else 'Mac 已装版'
    summary = f"{'通过' if passed else '失败'}：{len(checks)} 项真实产品断言；iCloud 为本机隔离链路，苹果跨设备未验；{target_note}"
    write(out / "product_basics.detail.json", {"schema_version": 1, "app_id": APP_ID, "spec_digest": spec["digest"], "features": features, "summary": summary, "scope": raw["scope"]})
    if args.ui_only:
        write(out / "native_ui.detail.json", {"summary": summary, "checks": checks, "original": str(raw_path.relative_to(ROOT)), "sha256": sha(raw_path)})
    print(summary); print(json.dumps({k: v for k, v in checks.items() if v is not True}, ensure_ascii=False))
    return 0 if passed else 1

if __name__ == "__main__":
    try: raise SystemExit(main())
    except sim_lane.Busy as exc: print(f"推迟：{exc}", file=sys.stderr); raise SystemExit(75)
    except (sim_lane.LaneError, OSError, ValueError, KeyError) as exc: print(f"验收未完成：{exc}", file=sys.stderr); raise SystemExit(1)
