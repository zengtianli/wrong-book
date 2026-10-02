#!/usr/bin/env python3
"""Fictional demo library for screenshots, platform launch smoke tests and the compact-layout proof.

    python3 scripts/demo/fixture.py start --dir <scratch dir> [--json]
    python3 scripts/demo/fixture.py stop  --dir <scratch dir>
    python3 scripts/demo/fixture.py serve [--port N]          # foreground, for manual runs

start launches this file's own stdlib server on a free 127.0.0.1 port (state and log inside --dir) and prints one
JSON object: url, port, pid, user, pw, dir. Point a Debug build at it with
    -api_base <url> -dev_user <user> -dev_pw <pw>
and every screen has data: a signed-in account (nickname 小林), five personal lessons in three subjects (one is a
photo import), a review list with pending items, today's progress and a streak, and an AI quota.

Everything is invented here: the account, the questions, the progress. It never contacts edu.tianli.cyou, never
reads ~/Apps/edu/web data, ~/.personal_env or any real child's record, and accepts only its own demo password.
The lesson pages are tiny stand-ins for the practice engine (they list the questions and answer
__PRACTICE__.review so the native review entry does not complain); the real engine is out of scope here.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import secrets
import signal
import socket
import subprocess
import sys
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

USER, NICK = "demo-xiaolin", "小林"
# The demo password is random per start (passed to the server child through PW_ENV), so no fixed password lives in
# this public repo or in any evidence file; launch.sh / measure scripts read it from start's JSON.
PW_ENV = "WRONGBOOK_DEMO_PW"
PW = os.environ.get(PW_ENV) or "demo-" + secrets.token_hex(6)
SCOPE = "demo-library-v1"
COOKIE = "edu_sess"
TOKEN = "demo-session-token"

# (slug, title, subject, subject name, unit, date, private, [(uid, gid, question)])
LESSONS = [
    ("demo-fraction", "分数的初步认识", "math", "数学", "三年级上 · 第八单元", "2026-09-28", False, [
        ("f1", "frac-part", "把一个蛋糕平均分成 8 份，小林吃了 3 份，吃了这个蛋糕的几分之几？"),
        ("f2", "frac-compare", "比较大小：3/8 ○ 5/8"),
        ("f3", "frac-sub", "1 − 3/7 = ？"),
        ("f4", "frac-word", "一根绳子长 1 米，用去 2/5 米，还剩几分之几米？"),
    ]),
    ("demo-multiply", "两位数乘两位数", "math", "数学", "三年级下 · 第四单元", "2026-09-25", False, [
        ("m1", "mul-2x2", "23 × 14 = ？"),
        ("m2", "mul-estimate", "估算：39 × 21 大约是多少？"),
        ("m3", "mul-word", "每箱苹果 24 个，12 箱一共多少个？"),
    ]),
    ("demo-poems", "古诗二首", "chinese", "语文", "三年级上 · 第六单元", "2026-09-24", False, [
        ("p1", "poem-fill", "默写：两岸青山相对出，________。"),
        ("p2", "word-meaning", "“水光潋滟晴方好”中“潋滟”的意思是？"),
        ("p3", "poem-author", "《望天门山》的作者是谁？"),
    ]),
    ("demo-past-tense", "Unit 3 · Last weekend", "english", "英语", "三年级下 · Unit 3", "2026-09-22", False, [
        ("e1", "past-irregular", "Yesterday I ___ (go) to the park with my dad."),
        ("e2", "past-did", "Choose: She ___ her homework last night. (do / did)"),
        ("e3", "past-question", "___ you watch TV last weekend? —Yes, I did."),
    ]),
    ("demo-photo-0927", "导入 · 9月27日 数学小测", "math", "数学", "导入的错题", "2026-09-27", True, [
        ("q7", "", "小数 0.6 读作______，表示______分之六。"),
        ("q9", "", "一个长方形长 8 厘米、宽 5 厘米，周长是多少厘米？"),
    ]),
]

# Pending review entries per lesson: (gid, name, wrong, ok, days ago). Private items use gid "photo:<uid>".
WRONG = {
    "demo-fraction": [("frac-compare", "分数比较大小", 3, 1, 0), ("frac-sub", "1 减几分之几", 2, 0, 1),
                      ("frac-word", "分数应用题", 1, 0, 3)],
    "demo-multiply": [("mul-estimate", "乘法估算", 2, 1, 2)],
    "demo-poems": [("poem-fill", "古诗默写", 2, 0, 0), ("word-meaning", "词语意思", 1, 0, 4)],
    "demo-past-tense": [("past-irregular", "不规则动词过去式", 3, 0, 1)],
    "demo-photo-0927": [("photo:q9", "长方形周长", 1, 0, 5)],
}
QUESTION = {(slug, gid or f"photo:{uid}"): q for slug, *_, items in LESSONS for uid, gid, q in items}


def today_stamp(d: dt.date | None = None) -> str:
    d = d or dt.date.today()
    return f"{d.year}-{d.month}-{d.day}"          # 与 practice.js 的 today() 相同：月/日不补零


def page(title: str, items: list[dict], private: bool) -> bytes:
    """A stand-in lesson page: same PRACTICE.init({items}) shape the native question index parses."""
    rows = json.dumps(items, ensure_ascii=False)
    cards = "".join(f'<div class="card" data-gid="{i["gid"]}"><div class="no">第 {n} 题</div>'
                    f'<div class="qbody">{i["q"]}</div><div class="ans"></div></div>'
                    for n, i in enumerate(items, 1))
    html = f"""<!doctype html><html lang="zh"><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>body{{font:17px/1.6 -apple-system,system-ui;margin:0;color:#24332e;background:#f7f8f5}}
main{{max-width:760px;margin:auto;padding:18px}}h1{{font-size:21px;margin:4px 0 2px}}.sub{{color:#7a847e;font-size:13px;margin-bottom:14px}}
.card{{background:#fff;border:1px solid #e3e8e1;border-radius:8px;padding:14px 16px;margin:10px 0}}
.card.focus{{border-color:#2b6653;box-shadow:0 0 0 2px #edf3ed}}.no{{font-size:12px;color:#2b6653;margin-bottom:4px}}
.ans{{margin-top:10px;height:36px;border:1px dashed #dce6f0;border-radius:6px}}</style>
<main><h1>{title}</h1><div class="sub">演示资料 · 本机合成，不含任何真实学生信息</div>{cards}</main>
<script>
window.PRACTICE = {{ init: function (o) {{ window.__ITEMS__ = o.items; }} }};
window.__PRACTICE__ = {{ review: function (gid) {{
  var hit = gid && document.querySelector('[data-gid="' + gid + '"]');
  if (hit) {{ hit.classList.add('focus'); hit.scrollIntoView({{block: 'center'}}); return 'drill'; }}
  return gid === null ? 'wrong' : 'mix';
}} }};
PRACTICE.init({{ title: {json.dumps(title, ensure_ascii=False)}, items: {rows}{', privateItems: true' if private else ''} }});
</script></html>"""
    return html.encode()


def build_library() -> tuple[list[dict], dict[str, bytes]]:
    manifest, files = [], {}
    for slug, title, subject, sname, unit, date, private, items in LESSONS:
        rows = [{"uid": u, "q": q, "gid": g, "own": 1} for u, g, q in items]
        data = page(title, rows, private)
        rel = f"demo/{slug}.html"
        files[rel] = data
        manifest.append({"kind": "practice", "slug": slug, "title": title, "desc": "演示资料", "file": rel,
                         "subject": subject, "subject_name": sname, "unit": unit, "icon": "", "date": date,
                         "source": "demo", "tag": "", "sha256": hashlib.sha256(data).hexdigest()})
    return manifest, files


def archive() -> dict[str, str]:
    today = dt.date.today()
    out = {}
    for slug, entries in WRONG.items():
        wrong = []
        for gid, name, n_wrong, n_ok, ago in entries:
            at = f"{(today - dt.timedelta(days=ago)).isoformat()} 19:30"      # 同一天内多次取数逐字相同
            q = QUESTION.get((slug, gid), "")
            wrong.append({"gid": gid, "gname": name, "q": q, "at": at, "wrong": n_wrong, "ok": n_ok, "manual": 0,
                          "hits": [{"q": q, "at": at, "no": "", "src": "demo"}]})
        out[f"edu:{slug}"] = json.dumps({"wrong": wrong}, ensure_ascii=False)
    out["edu:@profile"] = json.dumps({"xp": 460, "goal": 12, "day": {"d": today_stamp(), "n": 7},
                                      "days": {"streak": 6}}, ensure_ascii=False)
    return out


MANIFEST, FILES = build_library()


class Handler(BaseHTTPRequestHandler):
    server_version = "wrongbook-demo/1"

    def log_message(self, fmt, *args):          # one line per request on stderr (captured into the log file)
        sys.stderr.write("%s %s\n" % (self.command, self.path.split("?")[0]))

    def _json(self, code: int, obj: dict, cookie: str | None = None) -> None:
        data = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        if cookie is not None:
            self.send_header("Set-Cookie", cookie)
        self.end_headers()
        self.wfile.write(data)

    def _authed(self) -> bool:
        return f"{COOKIE}={TOKEN}" in (self.headers.get("Cookie") or "")

    def _body(self) -> dict:
        n = int(self.headers.get("Content-Length") or 0)
        try:
            return json.loads(self.rfile.read(n) or b"{}")
        except ValueError:
            return {}

    def do_GET(self):  # noqa: N802
        u = urlsplit(self.path)
        p = u.path
        if p == "/api/health":
            return self._json(200, {"ok": True, "demo": True})
        if not self._authed():
            return self._json(401, {"ok": False, "err": "请先登录"})
        if p == "/api/state":
            return self._json(200, {"ok": True, "u": USER, "nick": NICK, "balance": 1280, "practice_left": 30})
        if p == "/api/lessons":
            return self._json(200, {"ok": True, "owner": USER, "scope": SCOPE, "daily_goal": 12, "lessons": MANIFEST})
        if p == "/api/lesson":
            rel = (parse_qs(u.query).get("file") or [""])[0]
            data = FILES.get(rel)
            if data is None:
                return self._json(404, {"ok": False, "err": "没有这份学习资料"})
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "private, no-store")
            self.end_headers()
            self.wfile.write(data)
            return
        if p == "/api/archive":
            return self._json(200, {"ok": True, "data": archive(), "ts": int(time.time())})
        if p == "/api/ai_access":
            return self._json(200, {"ok": True, "enabled": True, "remaining": 7, "subscribed": False})
        if p == "/api/account_delete_request":
            return self._json(200, {"ok": True, "status": "none"})
        return self._json(404, {"ok": False, "err": "演示服务没有这个接口"})

    def do_POST(self):  # noqa: N802
        p = urlsplit(self.path).path
        b = self._body()
        if p == "/api/login":
            if b.get("u") == USER and b.get("p") == PW:
                return self._json(200, {"ok": True}, cookie=f"{COOKIE}={TOKEN}; Path=/; HttpOnly; Max-Age=86400")
            return self._json(403, {"ok": False, "err": "用户名或密码不对"})
        if p == "/api/logout":
            return self._json(200, {"ok": True}, cookie=f"{COOKIE}=; Path=/; Max-Age=0")
        if not self._authed():
            return self._json(401, {"ok": False, "err": "请先登录"})
        if p == "/api/archive":
            return self._json(200, {"ok": True, "ts": int(time.time())})      # 演示数据不落盘
        return self._json(403, {"ok": False, "err": "演示服务不接受写操作"})


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def serve(port: int) -> None:
    httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    signal.signal(signal.SIGTERM, lambda *_: (httpd.server_close(), sys.exit(0)))
    httpd.serve_forever()


def start(work: Path) -> dict:
    work.mkdir(parents=True, exist_ok=True)
    stop(work)
    port = free_port()
    log = open(work / "fixture.log", "w")
    pw = "demo-" + secrets.token_hex(6)
    proc = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "serve", "--port", str(port)],
                            stdout=log, stderr=log, start_new_session=True, env={**os.environ, PW_ENV: pw})
    url = f"http://127.0.0.1:{port}"
    for _ in range(50):
        try:
            with urllib.request.urlopen(url + "/api/health", timeout=1) as r:
                if json.load(r).get("ok"):
                    break
        except OSError:
            time.sleep(0.1)
    else:
        proc.kill()
        raise SystemExit(f"演示服务没起来；日志 {work / 'fixture.log'}")
    info = {"url": url, "port": port, "pid": proc.pid, "user": USER, "pw": pw, "dir": str(work)}
    (work / "fixture.json").write_text(json.dumps(info), encoding="utf-8")
    return info


def stop(work: Path) -> bool:
    f = work / "fixture.json"
    if not f.is_file():
        return False
    try:
        os.kill(json.loads(f.read_text())["pid"], signal.SIGTERM)
    except (OSError, ValueError, KeyError):
        pass
    f.unlink(missing_ok=True)
    return True


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=("start", "stop", "serve"))
    ap.add_argument("--dir", type=Path, help="scratch directory for state and log (outside the repo)")
    ap.add_argument("--port", type=int, default=18881)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    if a.cmd == "serve":
        if not os.environ.get(PW_ENV):
            print(f"演示账号 {USER} / {PW}", file=sys.stderr)
        serve(a.port)
        return 0
    if not a.dir:
        ap.error("--dir is required for start/stop")
    if a.cmd == "stop":
        stop(a.dir.expanduser().resolve())
        return 0
    info = start(a.dir.expanduser().resolve())
    print(json.dumps(info) if a.json else "\n".join(f"{k}: {v}" for k, v in info.items()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
