#!/usr/bin/env python3
"""mistakes 命令行的回归门：起一个**隔离的本地服务端**（临时数据目录 + 空闲端口），
用真实入口 `cli/mistakes` 走一遍读、上传、派作业、删除、注销与失败退出码。
不碰线上、不碰任何真实账号；本地没有读图工人，所以作业只会停在「进行中」，不调 DeepSeek。
另验随 Mac 版打包：project.yml 只在 macOS build 把命令拷进 Contents/Resources/bin，
cli/install.sh 按 bundle id 在（临时的）Applications 目录找宿主 .app 并链过去。

服务端源码取 $EDU_SERVER_PY，缺省是同一工作区的 ~/Apps/edu/web/points/server.py
（公开仓单独克隆时没有它：本测试直接失败并说明原因，不假装通过）。

    python3 Tests/cli_mistakes_test.py
"""
from __future__ import annotations

import json
import os
import plistlib
import re
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time
import urllib.request
import zlib
from datetime import date, timedelta
from http.cookiejar import CookieJar
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
CLI = REPO / "cli" / "mistakes"
SERVER = Path(os.environ.get("EDU_SERVER_PY") or REPO.parents[2] / "web" / "points" / "server.py")
EMAIL, PW = "cli.mistakes@example.test", "mistakes cli test phrase"  # 后端密码规则：15–128 个字符
FAILS: list[str] = []


def ck(name: str, cond: bool, detail: str = "") -> None:
    print(("  ✅ " if cond else "  ❌ ") + name + ("" if cond else f"　{detail}"))
    if not cond:
        FAILS.append(name)


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def png(w: int = 4, h: int = 3) -> bytes:
    """一张真的小 PNG（服务端从字节认格式、查是否传了一半）。"""
    def chunk(t: bytes, d: bytes) -> bytes:
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + b"\xff\x80\x00" * w for _ in range(h))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def stamp(d: date) -> str:
    return f"{d.year}-{d.month}-{d.day}"          # 同 practice.js：月/日不补零


BUNDLE_ID = "cyou.tianli.wrongbook"
INSTALL = REPO / "cli" / "install.sh"


def fake_app(apps: Path, name: str, bundle_id: str, with_cli: bool) -> Path:
    """一个只有 Info.plist（+ 可选 Resources/bin/mistakes）的假 .app：install.sh 只按 bundle id 认宿主。"""
    app = apps / f"{name}.app"
    (app / "Contents").mkdir(parents=True)
    (app / "Contents" / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": bundle_id}))
    if with_cli:
        b = app / "Contents" / "Resources" / "bin"
        b.mkdir(parents=True)
        shutil.copy2(CLI, b / "mistakes")
        (b / "mistakes").chmod(0o755)
    return app


def install(bin_dir: Path, apps: Path, *args: str) -> tuple[int, str]:
    env = {**os.environ, "EDU_CLI_BIN_DIR": str(bin_dir), "EDU_APPLICATIONS_DIR": str(apps)}
    r = subprocess.run(["sh", str(INSTALL), *args], env=env, capture_output=True, text=True, timeout=60,
                       stdin=subprocess.DEVNULL)
    return r.returncode, r.stdout + r.stderr


def check_bundle_packaging() -> None:
    print("【随 Mac 版打包】")
    spec = (REPO / "project.yml").read_text(encoding="utf-8")
    block = spec.split("postBuildScripts:", 1)[1].split("    sources:", 1)[0] if "postBuildScripts:" in spec else ""
    ck("project.yml 构建阶段把 cli/mistakes 拷进 Resources/bin",
       '"$PROJECT_DIR/cli/mistakes"' in block and "$UNLOCALIZED_RESOURCES_FOLDER_PATH/bin" in block, block[:200])
    ck("只在 macOS 的 build 动作拷（iOS 包与归档 ACTION=install 不带）",
       '"$PLATFORM_NAME" != "macosx"' in block and '"$ACTION" = "install"' in block)
    ck("不声明 outputFiles（否则 iOS 包里会多一个空 bin/）",
       not any(ln.strip().startswith("outputFiles:") for ln in block.splitlines()))

    tmp = Path(tempfile.mkdtemp(prefix="mistakes-install-"))
    try:
        apps, none, bin_dir = tmp / "Applications", tmp / "empty", tmp / "bin"
        apps.mkdir(); none.mkdir()
        link = bin_dir / "mistakes"
        code, out = install(bin_dir, none)
        ck("没装 Mac 版 → 链到本仓入口", code == 0 and os.path.realpath(link) == str(CLI.resolve()), out)
        fake_app(apps, "旧版错题本", BUNDLE_ID, with_cli=False)
        code, out = install(bin_dir, apps)
        ck("装了旧 Mac 版（包里没命令）→ 拒绝、退出 1、原链接不动",
           code == 1 and os.path.realpath(link) == str(CLI.resolve()), out)
        code, out = install(bin_dir, apps, "--check")
        ck("--check 同样判不过", code == 1, out)
        shutil.rmtree(apps / "旧版错题本.app")
        fake_app(apps, "别的应用", "com.example.other", with_cli=True)
        app = fake_app(apps, "错题本", BUNDLE_ID, with_cli=True)
        code, out = install(bin_dir, apps)
        want = os.path.realpath(app / "Contents" / "Resources" / "bin" / "mistakes")
        ck("按 bundle id 找到宿主 .app，本仓旧链接换成包内命令", code == 0 and os.path.realpath(link) == want, out)
        code, out = install(bin_dir, apps, "--check")
        ck("--check 通过（链接落在 .app 内且 --help 退出 0）", code == 0, out)
        ck("重复安装幂等", install(bin_dir, apps)[0] == 0 and os.path.realpath(link) == want)
        link.unlink()
        link.symlink_to("/usr/bin/true")
        code, out = install(bin_dir, apps)
        ck("指向别处的同名链接拒绝覆盖", code == 1 and os.readlink(link) == "/usr/bin/true", out)
        install(bin_dir, apps, "--uninstall")
        ck("--uninstall 不删别人的链接", os.path.lexists(link) and os.readlink(link) == "/usr/bin/true")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main() -> int:
    check_bundle_packaging()
    if not SERVER.is_file():
        print(f"❌ 找不到服务端源码 {SERVER}（设 EDU_SERVER_PY 指向 edu/web/points/server.py）")
        return 2
    home = Path(tempfile.mkdtemp(prefix="mistakes-cli-"))
    port = free_port()
    base = f"http://127.0.0.1:{port}"
    env = {**os.environ, "EDU_POINTS_HOME": str(home), "EDU_POINTS_PORT": str(port),
           "EDU_POINTS_STATIC": str(home / "site"), "EDU_KID_PW": "kidpass1", "EDU_PARENT_PW": "parentpass1"}
    (home / "site").mkdir()
    imgs = home / "imgs"
    imgs.mkdir()
    for i in (1, 2, 3):
        (imgs / f"p{i}.png").write_bytes(png(4 + i, 3))
    srv = None
    try:
        r = subprocess.run([sys.executable, str(SERVER), "init"], env=env, capture_output=True, text=True, timeout=60)
        if r.returncode:
            print(r.stdout, r.stderr)
            return 2
        # 注册要先过邮箱验证码（后端 2026-10-04 起）。隔离服务端经后端自带的 test_mail_service.py 启动：只把发信换成
        # 写进本次临时目录的 test-outbox.json，验证码接口照常执行；生产没有这个入口。
        mail_fixture = SERVER.with_name("test_mail_service.py")
        srv = subprocess.Popen([sys.executable, str(mail_fixture if mail_fixture.is_file() else SERVER), "serve"], env=env,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(60):
            time.sleep(0.1)
            try:
                urllib.request.urlopen(base + "/api/health", timeout=2)
                break
            except OSError:
                continue
        else:
            print("❌ 隔离服务端没起来")
            return 2

        clean = {k: v for k, v in os.environ.items() if not k.startswith("EDU_")}
        op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(CookieJar()))

        def http(path, body):
            req = urllib.request.Request(base + path, data=json.dumps(body).encode(),
                                         headers={"Content-Type": "application/json"})
            with op.open(req, timeout=10) as resp:
                return json.loads(resp.read())

        def run(args, user=EMAIL, pw=PW, stdin="", extra=None, cwd=None):
            e = {**clean, "EDU_API_BASE": base, **({"EDU_USER": user} if user else {}),
                 **({"EDU_PASSWORD": pw} if pw else {}), **(extra or {})}
            p = subprocess.run([str(CLI), *args], env=e, input=stdin, capture_output=True, text=True,
                               timeout=90, cwd=cwd)
            try:
                out = json.loads(p.stdout) if "--json" in args else None
            except ValueError:
                out = None
            return p.returncode, out, p.stdout + p.stderr

        # 同 App 注册页：邮箱账号（公开注册的新账号，前 10 张免费识别）
        sent = http("/api/email_send", {"email": EMAIL, "purpose": "register"})
        mail = json.loads((home / "test-outbox.json").read_text())[-1]
        code = re.search(r"验证码：(\d{6})", mail[2]).group(1)
        grant = http("/api/email_verify", {"challenge": sent["challenge"], "code": code})["grant"]
        reg = http("/api/register", {"email": EMAIL, "p": PW, "grant": grant})
        ck("隔离服务端里注册一次性邮箱账号", reg.get("ok") is True, str(reg))
        uname = reg.get("u", "")

        print("【帮助与用法】")
        for sub in ([], ["status"], ["wrongs"], ["import"], ["recognize"], ["delete"], ["account", "delete"]):
            code, _, _ = run([*sub, "--help"], user=None, pw=None)
            ck(f"mistakes {' '.join(sub)} --help → 0", code == 0)
        code, out, _ = run(["status", "--json"], user=None, pw=None)
        ck("缺凭据 → 2 且 ok:false", code == 2 and out["ok"] is False, str(out))
        code, out, _ = run(["status", "--json"], pw="wrong-pass")
        ck("账号密码错 → 1 且带 401", code == 1 and out["ok"] is False and out.get("status") == 401, str(out))
        code, out, _ = run(["status", "--json"], extra={"EDU_API_BASE": "http://127.0.0.1:9"})
        ck("连不上服务端 → 1", code == 1 and out["ok"] is False, str(out))

        print("【给 Agent 的约定：顶层帮助四样、version 读回、失败形状】")
        _, _, top = run(["--help"], user=None, pw=None)
        for word in ("读命令", "写命令", "这台 Mac 上的 App", "--json 输出形状", "退出码", "仅在窗口中", "只在那台设备本机"):
            ck(f"顶层帮助有「{word}」", word in top)
        ck("顶层帮助不再有「暂无命令」", "暂无命令" not in top)
        window = top[top.index("仅在窗口中"):top.index("只在那台设备本机")]
        ck("「仅在窗口中」不再列 import 做得到的相册选择与调页序，列了 Mac 的 iCloud Drive 更新目录",
           "相册" not in window and "调页序" not in window and "iCloud Drive 更新目录" in window, window)
        mac = top[top.index("这台 Mac 上的 App"):top.index("--json 输出形状")]
        ck("退出登录、同步错题、停用副本、配置与更新列在「这台 Mac 上的 App」的命令里",
           "退出登录" not in window and all(w in mac for w in ("app logout --yes", "offline sync", "offline reset --yes", "config status",
                                                             "config export", "import <file> --yes", "sync on|off --yes",
                                                             "update check", "update install --yes", "每日提醒")), mac)
        ck("顶层帮助的退出码表列了 0 / 1 / 2 / 130", all(re.search(rf"(?m)^\s+{n}\s", top) for n in (0, 1, 2, 130)), top[-900:])
        for name in ("version", "status", "questions", "wrongs", "progress", "lessons", "lesson", "uploads", "papers", "image", "job",
                     "upload", "import", "recognize", "delete", "account", "config", "update", "offline", "app"):
            ck(f"顶层帮助把 {name} 列为命令", re.search(rf"(?m)^\s+(?:mistakes\s+)?{name}(?![\w-])", top) is not None
               or re.search(rf"\|\s*{name}(?![\w-])", top) is not None)
        code, out, _ = run(["version", "--json"], user=None, pw=None)
        ck("version 不登录 → 0，报版本、服务端可达、凭据未给",
           code == 0 and out["ok"] is True and out["cli"] and out["server"]["reachable"] is True
           and out["api"] == base and out["credentials"] == {"user": False, "password": False}, str(out))
        code, out, _ = run(["version", "--json"])
        ck("version 给了凭据也不登录，只报「已给」", code == 0 and out["credentials"] == {"user": True, "password": True}, str(out))
        code, out, _ = run(["version", "--json"], user=None, pw=None, extra={"EDU_API_BASE": "http://127.0.0.1:9"})
        ck("version 连不上服务端 → 仍 0，reachable:false 带原因",
           code == 0 and out["server"]["reachable"] is False and out["server"]["err"], str(out))
        code, out, _ = run(["wrongs", "--no-such-flag", "--json"])
        ck("参数写错带 --json → 2，输出 ok:false 与 error.code=usage",
           code == 2 and out is not None and out["ok"] is False and out["error"]["code"] == "usage" and out["err"], str(out))
        code, out, text = run(["wrongs", "--no-such-flag"])
        ck("参数写错不带 --json → 2，照 argparse 原样写 stderr", code == 2 and "unrecognized arguments" in text, text[-200:])
        code, out, _ = run(["status", "--json"], pw="wrong-pass")
        ck("服务端拒绝 → error.code=rejected，原有 err / status 不变",
           code == 1 and out["error"] == {"code": "rejected", "message": out["err"]} and out["status"] == 401, str(out))
        code, out, _ = run(["status", "--json"], extra={"EDU_API_BASE": "http://127.0.0.1:9"})
        ck("网络失败 → error.code=failed", code == 1 and out["error"]["code"] == "failed", str(out))
        code, out, _ = run(["--password-stdin", "status", "--json"], pw=None, stdin=PW + "\n")
        ck("--password-stdin 也能登录", code == 0 and out["ok"] is True, str(out))

        print("【读】概况 / 课程包 / 错题本 / 今日进度")
        code, st, _ = run(["status", "--json"])
        ck("status：新账号 10 张免费、没有上传、未注销",
           code == 0 and st["ai"]["remaining"] == 10 and st["ai"]["trial_pages"] == 10
           and st["uploads"]["total"] == 0 and st["papers"]["total"] == 0
           and st["deletion"].get("status") in (None, "none"), str(st))
        code, ls, _ = run(["lessons", "--json"])
        ck("lessons：新账号个人课程包为空", code == 0 and ls["count"] == 0, str(ls))
        code, pg, _ = run(["progress", "--json"])
        ck("progress：还没有存档", code == 0 and pg["has_profile"] is False and pg["done_today"] == 0, str(pg))
        code, wr, _ = run(["wrongs", "--json"])
        ck("wrongs：还没有错题", code == 0 and wr["types"] == 0 and wr["source"] == "server_archive_snapshot", str(wr))

        # 课程包夹具：同 private_lessons.commit 落盘的形状（lessons/<user>/<account_instance>/）
        inst = json.loads((home / "users.json").read_text())["users"][uname]["account_instance"]
        root = home / "lessons" / uname / inst
        root.mkdir(parents=True)
        # 练习页夹具带 PRACTICE.init(… items: [...])：同 App 的 QuestionIndex 读的那一段（题面里放了标签、实体和方括号）
        (root / "scan-a.html").write_text(
            "<!doctype html><title>scan</title><p>cli fixture</p><script>PRACTICE.init({slug: \"scan-a\", items: ["
            + json.dumps({"uid": "u1", "gid": "carry-add", "q": "38+47=<b>?</b>", "ask": "列竖式 [进位]", "own": 1,
                          "ans": "85"}, ensure_ascii=False) + ","
            + json.dumps({"uid": "u2", "gid": "other", "q": "9&lt;10 对吗", "own": 1}, ensure_ascii=False) + ","
            + json.dumps({"uid": "u3", "gid": "shared", "q": "不是自己的题", "own": 0}, ensure_ascii=False)
            + "], privateItems: false});</script>", encoding="utf-8")
        (root / "manifest.json").write_text(json.dumps({"lessons": [
            {"slug": "scan-a", "title": "拍照错题 · 进位加法", "subject": "math", "file": "scan-a.html"}]}),
            encoding="utf-8")
        today, yday = date.today(), date.today() - timedelta(days=1)
        wrong = {"wrong": [{"gid": "carry-add", "gname": "进位加法", "q": "38+47=?", "at": "2026-09-30",
                            "wrong": 2, "ok": 1, "manual": 0, "ans": "85", "options": ["85"],
                            "hits": [{"q": "38+47", "at": "2026-09-30", "no": 3, "src": "paper"}]},
                           {"gid": "borrow-sub", "gname": "退位减法", "q": "52-19=?", "at": "2026-09-29",
                            "wrong": 1, "ok": 0, "manual": 0}]}
        http("/api/login", {"u": EMAIL, "p": PW})
        http("/api/archive", {"data": {
            "edu:scan-a": json.dumps(wrong),
            "edu:gone-lesson": json.dumps({"wrong": [{"gid": "old", "gname": "旧题型", "wrong": 1}]}),
            "edu:@profile": json.dumps({"day": {"d": stamp(today), "n": 5}, "goal": 12, "xp": 40,
                                        "days": {"streak": 3}})}})
        code, ls, _ = run(["lessons", "--json"])
        ck("lessons：读到夹具那一课", code == 0 and ls["count"] == 1 and ls["lessons"][0]["slug"] == "scan-a", str(ls))
        code, out, _ = run(["lesson", "scan-a", "--out", str(home / "dl.html"), "--json"])
        ck("lesson 下载 = 服务端那份字节", code == 0 and (home / "dl.html").read_bytes() == (root / "scan-a.html").read_bytes(),
           str(out))
        code, out, _ = run(["lesson", "nope", "--json"])
        ck("lesson 不存在 → 1", code == 1 and out["ok"] is False, str(out))
        code, wr, _ = run(["wrongs", "--json"])
        g = next((x for x in wr.get("groups") or [] if x["slug"] == "scan-a"), {})
        ck("wrongs：两课三类题，课程包外那课标 orphan", code == 0 and wr["types"] == 3 and wr["orphan_slugs"] == ["gone-lesson"]
           and g.get("title") == "拍照错题 · 进位加法", str(wr)[:300])
        ck("wrongs：不带出答案/选项（同 WrongBook.parse）",
           all("ans" not in e and "options" not in e for x in wr["groups"] for e in x["entries"]))
        code, wr, _ = run(["wrongs", "--search", "退位", "--json"])
        ck("wrongs --search 退位 → 1 类（按题型名/题面）", code == 0 and wr["types"] == 1, str(wr)[:200])
        code, wr, _ = run(["wrongs", "--search", "拍照错题", "--json"])
        ck("wrongs --search 课名 → 这一课全部两类（同 App：课名也参与搜索）", code == 0 and wr["types"] == 2, str(wr)[:200])
        code, wr, _ = run(["wrongs", "--subject", "math", "--json"])
        ck("wrongs --subject math → 只剩课程包里的数学课", code == 0 and [x["slug"] for x in wr["groups"]] == ["scan-a"])
        code, qs, _ = run(["questions", "--json"])
        q1 = next((x for x in qs.get("items") or [] if x["uid"] == "u1"), {})
        ck("questions：课程包里自己的两道原题（同 App 错题本列表），不带答案",
           code == 0 and qs["count"] == 2 and qs["source"] == "lesson_pack" and [x["uid"] for x in qs["items"]] == ["u1", "u2"]
           and all("ans" not in x for x in qs["items"]), str(qs)[:300])
        ck("questions：题面去标签、还原实体；存档里同 gid 的标待巩固",
           q1.get("text") == "38+47= ? 列竖式 [进位]" and q1.get("pending") is True and qs["pending"] == 1
           and qs["items"][1]["text"] == "9<10 对吗" and qs["items"][1]["pending"] is False, str(qs)[:300])
        code, qs, _ = run(["questions", "--pending", "--json"])
        ck("questions --pending → 只剩待巩固那一道（同复习页）", code == 0 and [x["uid"] for x in qs["items"]] == ["u1"], str(qs)[:200])
        code, qs, _ = run(["questions", "--search", "竖式", "--json"])
        ck("questions --search 题面 → 1 道", code == 0 and qs["count"] == 1, str(qs)[:200])
        code, qs, _ = run(["questions", "--search", "拍照错题", "--json"])
        ck("questions --search 课名 → 这一课两道", code == 0 and qs["count"] == 2, str(qs)[:200])
        code, qs, _ = run(["questions", "--subject", "chinese", "--json"])
        ck("questions --subject chinese → 0 道，仍退出 0", code == 0 and qs["count"] == 0 and qs["ok"] is True, str(qs)[:200])
        code, pg, _ = run(["progress", "--json"])
        ck("progress：今天 5/12、经验 40、连续 3 天", code == 0 and pg["done_today"] == 5 and pg["goal"] == 12
           and pg["xp"] == 40 and pg["streak_days"] == 3 and pg["remaining"] == 7, str(pg))
        http("/api/archive", {"data": {"edu:@profile": json.dumps({"day": {"d": stamp(yday), "n": 9}, "goal": 12})}})
        code, pg, _ = run(["progress", "--json"])
        ck("progress：昨天的计数跨天归零（同 App）", code == 0 and pg["done_today"] == 0, str(pg))

        print("【上传 / 派作业 / 查作业】（隔离服务端，无读图工人）")
        code, out, _ = run(["upload", str(imgs / "p1.png"), "--json"])
        ck("upload 默认要读图但没 --consent-ai → 2，且没传", code == 2 and out["ok"] is False
           and run(["uploads", "--json"])[1]["total"] == 0, str(out))
        code, up, _ = run(["upload", str(imgs / "p1.png"), "--subject", "math", "--note", "cli", "--no-auto", "--json"])
        wid = (up or {}).get("items", [{}])[0].get("id", "")
        ck("upload --no-auto → 拿到照片 id", code == 0 and up["count"] == 1 and bool(wid), str(up))
        code, out, _ = run(["image", "upload", wid, "--out", str(home / "got.png"), "--json"])
        ck("image upload：取回的原图 = 上传的字节", code == 0 and (home / "got.png").read_bytes() == (imgs / "p1.png").read_bytes(),
           str(out))
        code, out, _ = run(["image", "upload", "20260101-000000-abcdef", "--json"])
        ck("image 不存在 → 1", code == 1 and out["ok"] is False, str(out))
        code, us, _ = run(["uploads", "--json"])
        ck("uploads：1 张待录入", code == 0 and us["total"] == 1 and us["pending"] == 1 and us["items"][0]["id"] == wid, str(us))
        code, out, _ = run(["recognize", wid, "--kind", "draft", "--json"])
        ck("recognize draft 没 --consent-ai → 2", code == 2)
        code, out, _ = run(["recognize", wid, "--kind", "commit", "--json"])
        ck("recognize commit 没 --topic → 2", code == 2)
        code, rj, _ = run(["recognize", wid, "--kind", "auto", "--consent-ai", "--json"])
        jid = (rj or {}).get("job", "")
        ck("recognize auto --consent-ai → 作业号，已入队", code == 0 and jid.startswith("auto-" + wid)
           and (home / "jobs" / (jid + ".json")).is_file(), str(rj))
        code, js, _ = run(["job", jid, "--json"])
        ck("job：没有工人 → 如实报进行中", code == 0 and js["state"] == "running", str(js))
        code, st, _ = run(["status", "--json"])
        ck("status：占掉 1 张免费额度、1 件识别中", code == 0 and st["ai"]["remaining"] == 9
           and st["uploads"]["running_jobs"] == 1, str(st))
        code, out, _ = run(["job", "auto-20260101-000000-abcdef-1-abcdef", "--json"])
        ck("job 不存在 → 1", code == 1 and out["ok"] is False, str(out))
        (home / "jobs" / (jid + ".done.json")).write_text(json.dumps(
            {"ok": False, "user": uname, "log": "读图失败：图片太糊"}), encoding="utf-8")
        (home / "jobs" / (jid + ".json")).unlink()
        code, out, _ = run(["job", jid, "--json"])
        ck("job 完成但失败 → 1 且带原因", code == 1 and "图片太糊" in out["err"], str(out))

        print("【整卷导入 / 删除】")
        code, out, _ = run(["import", str(imgs / "p2.png"), "--slug", "2026s1-g3-math-bad_slug", "--no-auto", "--json"])
        ck("import 卷子编号不对 → 2", code == 2)
        code, out, _ = run(["import", str(imgs / "p2.png"), "--year", "2026", "--term", "1", "--grade", "3",
                            "--subject", "math", "--kind", "final", "--json"])
        ck("import 默认要读图但没 --consent-ai → 2", code == 2)
        code, im, _ = run(["import", str(imgs / "p2.png"), str(imgs / "p3.png"), "--year", "2026", "--term", "1",
                           "--grade", "3", "--subject", "math", "--kind", "final", "--no-auto", "--json"])
        ck("import 两页 --no-auto → 2026s1-g3-math-final", code == 0 and im["slug"] == "2026s1-g3-math-final"
           and [p["page"] for p in im["pages"]] == [1, 2] and not any(p.get("job") for p in im["pages"]), str(im))
        code, out, _ = run(["image", "paper", "2026s1-g3-math-final", "--page", "2", "--out", str(home / "pg2.png"), "--json"])
        ck("image paper --page 2：取回第 2 页原图", code == 0 and (home / "pg2.png").read_bytes() == (imgs / "p3.png").read_bytes(),
           str(out))
        code, out, _ = run(["image", "paper", "2026s1-g3-math-final", "--json"])
        ck("image paper 缺 --page → 2", code == 2)
        code, pp, _ = run(["papers", "--json"])
        ck("papers：一份两页", code == 0 and pp["total"] == 1 and pp["items"][0]["pages"] == ["1", "2"], str(pp))
        code, out, _ = run(["delete", "paper", "2026s1-g3-math-final", "--json"])
        ck("delete 不带 --yes → 2 且没删", code == 2 and run(["papers", "--json"])[1]["total"] == 1)
        code, out, _ = run(["delete", "paper", "2026s1-g3-math-final", "--page", "2", "--yes", "--json"])
        ck("delete paper --page 2 → 只剩第 1 页", code == 0 and run(["papers", "--json"])[1]["items"][0]["pages"] == ["1"], str(out))
        code, out, _ = run(["delete", "paper", "2026s1-g3-math-final", "--yes", "--json"])
        ck("delete paper → 整份没了", code == 0 and run(["papers", "--json"])[1]["total"] == 0, str(out))
        code, up2, _ = run(["upload", str(imgs / "p3.png"), "--no-auto", "--json"])
        wid2 = (up2 or {}).get("items", [{}])[0].get("id", "")
        code, out, _ = run(["delete", "upload", wid2, "--yes", "--json"])
        ck("delete upload → 那张没了", code == 0 and wid2 not in [x["id"] for x in run(["uploads", "--json"])[1]["items"]], str(out))
        code, out, _ = run(["delete", "upload", "20260101-000000-abcdef", "--yes", "--json"])
        ck("delete 不存在的照片 → 1", code == 1 and out["ok"] is False, str(out))

        print("【账号注销】（隔离服务端里的一次性账号）")
        code, ds, _ = run(["account", "deletion-status", "--json"])
        ck("deletion-status：未申请", code == 0 and ds.get("status") in (None, "none"), str(ds))
        code, out, _ = run(["account", "delete", "--json"])
        ck("account delete 不带 --yes → 2", code == 2)
        code, dl, _ = run(["account", "delete", "--yes", "--json"])
        ck("有扫描历史 → 即时注销 409，转为注销申请（同 App 顺序）", code == 0 and dl.get("status") == "pending"
           and bool(dl.get("receipt_id")), str(dl))
        code, ds, _ = run(["account", "deletion-status", "--json"])
        ck("deletion-status：处理中", code == 0 and ds.get("status") == "pending", str(ds))
        code, ds2, _ = run(["account", "deletion-status", "--receipt", dl.get("receipt_id", ""), "--json"])
        ck("按回执查也是处理中", code == 0 and ds2.get("status") == "pending", str(ds2))
        code, out, _ = run(["upload", str(imgs / "p1.png"), "--no-auto", "--json"])
        ck("注销处理中 → 新上传被拒（409）", code == 1 and out.get("status") == 409, str(out))
    finally:
        if srv:
            srv.terminate()
            srv.wait(timeout=10)
        shutil.rmtree(home, ignore_errors=True)

    print()
    if FAILS:
        print(f"❌ mistakes 命令行门：{len(FAILS)} 条没过")
        return 2
    print("✅ mistakes 命令行门全过（随 Mac 版打包与安装 / 帮助 / 退出码 / 读 / 上传派作业 / 整卷 / 删除 / 注销）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
