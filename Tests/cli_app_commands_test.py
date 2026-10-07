#!/usr/bin/env python3
"""mistakes 的「这台 Mac 上的 App」四组命令（config / update / offline / app）的转调回归。

这四组由 Mac 版 App 的可执行文件执行（Sources/AppCommand.swift，另由 Tests/check-app-command.sh 隔离验证）；
这里只验命令行这一层：帮助不依赖 App、参数原样转过去、输出与退出码原样带回、找不到带命令入口的 App 时
不启动任何东西。用的是临时目录里的替身可执行文件（$MISTAKES_APP_EXECUTABLE），不碰已装的 App 与任何账号。

    python3 Tests/cli_app_commands_test.py
"""
from __future__ import annotations

import json
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
CLI = REPO / "cli" / "mistakes"
FAILS: list[str] = []

# 替身：把收到的参数记进 $FAKE_LOG，按 $FAKE_EXIT 退出，标准输出给一行 JSON、标准错误给一行字。
FAKE = """#!/bin/sh
# cyou.tianli.wrongbook.command
printf '%s\\n' "$@" > "$FAKE_LOG"
if [ "$1 $2 $3 $4" = "config export -o -" ]; then
  [ "${FAKE_EXIT:-0}" = 0 ] || { echo "错题本 没有可迁移的配置" >&2; exit "$FAKE_EXIT"; }
  echo '{"product":"wrong-book-mobile","values":{"defaults.remind_hour":7},"version":1}'; exit 0
fi
if [ "$1 $2 $3" = "config import -" ]; then cat > "$FAKE_LOG.stdin"; printf '%s' "$MISTAKES_IMPORT_PATH" > "$FAKE_LOG.label"; fi
echo '{"ok": true, "from": "fake-app"}'
echo "fake stderr" >&2
exit "${FAKE_EXIT:-0}"
"""


def ck(name: str, cond: bool, detail: str = "") -> None:
    print(("  ✅ " if cond else "  ❌ ") + name + ("" if cond else f"　{detail}"))
    if not cond:
        FAILS.append(name)


def run(args: list[str], env: dict[str, str]) -> tuple[int, str, str]:
    r = subprocess.run([sys.executable, str(CLI), *args], capture_output=True, text=True, timeout=60,
                       env={"PATH": "/usr/bin:/bin", "HOME": env["HOME"], **env})
    return r.returncode, r.stdout, r.stderr


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="mistakes-app-") as tmp:
        root = Path(tmp)
        fake, old, log = root / "FakeApp", root / "OldApp", root / "args.log"
        fake.write_text(FAKE)
        old.write_text("#!/bin/sh\ntouch \"$FAKE_LOG.launched\"\n")       # 没有命令入口的旧版：绝不能被启动
        for f in (fake, old):
            f.chmod(f.stat().st_mode | stat.S_IXUSR)
        base = {"HOME": str(root), "FAKE_LOG": str(log)}
        env = {**base, "MISTAKES_APP_EXECUTABLE": str(fake)}

        print("【帮助：不需要 App，四组都列全】")
        for verb in ("config", "update", "offline", "app"):
            code, out, _ = run([verb, "--help"], base)
            ck(f"mistakes {verb} --help → 0（没有 App 也给）", code == 0, out[:200])
            for word in ("config status", "config export -o", "config import <file> --yes", "config sync on|off --yes",
                         "update check", "update install --yes", "offline sync", "offline reset --yes", "app logout --yes",
                         "--json", "退出码", "confirmation_required", "remind_enabled", "remind_hour", "manual_install"):
                ck(f"  {verb} --help 有「{word}」", word in out)
        ck("帮助没有启动替身", not log.exists())
        for verb in ("update", "offline", "app"):
            code, out, _ = run([verb], env)
            ck(f"mistakes {verb}（缺子命令）→ 2，给用法，不启动 App", code == 2 and "usage: mistakes config" in out and not log.exists())

        print("【转调：参数、输出、退出码原样】")
        cases = (["config", "status", "--json"], ["config"], ["config", "import", "-", "--yes"],
                 ["config", "sync", "on", "--yes", "--dry-run", "--json"],
                 ["update", "check", "--json"], ["update", "install", "--yes", "--dry-run", "--json"],
                 ["offline", "sync", "--json"], ["offline", "reset", "--yes", "--json"], ["app", "logout", "--yes", "--json"])
        for args in cases:
            log.unlink(missing_ok=True)
            code, out, err = run(args, env)
            got = log.read_text().splitlines() if log.exists() else None
            ck(f"mistakes {' '.join(args)} → 原样转给 App", code == 0 and got == args and json.loads(out) == {"ok": True, "from": "fake-app"}
               and "fake stderr" in err, f"{code} {got} {out!r} {err!r}")
        for want in (1, 2):
            code, out, _ = run(["offline", "reset", "--json"], {**env, "FAKE_EXIT": str(want)})
            ck(f"App 退出 {want} → 命令退出 {want}，输出照带", code == want and '"fake-app"' in out)
        log.unlink(missing_ok=True)
        code, out, _ = run(["--timeout", "5", "offline", "sync", "--json"], env)
        ck("全局选项写在前面也转（全局选项不传给 App）", code == 0 and log.read_text().splitlines() == ["offline", "sync", "--json"], out)

        print("【导出、导入：文件由命令读写，内容经标准输出 / 标准输入交给 App】")
        config = '{"product":"wrong-book-mobile","values":{"defaults.remind_hour":7},"version":1}'
        target = root / "out dir" / "配置.json"
        target.parent.mkdir()
        log.unlink(missing_ok=True)
        code, out, _ = run(["config", "export", "-o", str(target), "--json"], env)
        body = json.loads(out) if code == 0 else {}
        ck("config export -o <文件> → App 只收到 -o -，文件由命令写成同一份内容",
           code == 0 and log.read_text().splitlines() == ["config", "export", "-o", "-"] and target.read_text() == config
           and body == {"ok": True, "command": "config export", "path": str(target), "bytes": len(config.encode()),
                        "keys": ["defaults.remind_hour"]}, f"{code} {out!r}")
        log.unlink(missing_ok=True)
        target.write_text("old")
        code, out, _ = run(["config", "export", "-o", str(target), "--json"], env)
        ck("目标已存在、没给 --force → 2 file_exists，不启动 App、不动文件", code == 2 and json.loads(out)["error"]["code"] == "file_exists"
           and not log.exists() and target.read_text() == "old", out)
        code, out, _ = run(["config", "export", "--output=" + str(target), "--force"], env)
        ck("--force 覆盖；不带 --json 给一句话", code == 0 and target.read_text() == config and "配置已导出" in out, out)
        code, out, _ = run(["config", "export", "-o", str(root / "x.json"), "--json"], {**env, "FAKE_EXIT": "1"})
        ck("App 导出失败 → 原退出码、失败形状，不留文件", code == 1 and json.loads(out)["error"]["code"] == "no_settings"
           and not (root / "x.json").exists(), out)
        log.unlink(missing_ok=True)
        code, out, _ = run(["config", "export", "-o", "-"], env)
        ck("config export -o - 原样转调，内容到标准输出", code == 0 and log.read_text().splitlines() == ["config", "export", "-o", "-"]
           and out.strip() == config, out)
        source = root / "in dir" / "导入.json"
        source.parent.mkdir()
        source.write_text(config)
        log.unlink(missing_ok=True)
        code, out, _ = run(["config", "import", str(source), "--yes", "--json"], env)
        ck("config import <文件> → App 收到 config import - 与原参数，内容走标准输入，文件名另递",
           code == 0 and log.read_text().splitlines() == ["config", "import", "-", "--yes", "--json"]
           and Path(str(log) + ".stdin").read_text() == config and Path(str(log) + ".label").read_text() == str(source), out)
        code, out, _ = run(["config", "import", str(source), "--json"], {**env, "FAKE_EXIT": "2"})
        ck("App 要 --yes 而退出 2 → 命令退出 2", code == 2, out)
        log.unlink(missing_ok=True)
        code, out, _ = run(["config", "import", str(root / "nope.json"), "--yes", "--json"], env)
        ck("要导入的文件不存在 → 1 not_found，不启动 App", code == 1 and json.loads(out)["error"]["code"] == "not_found" and not log.exists(), out)

        print("【找不到带命令入口的 App：退出 1，什么都不启动】")
        log.unlink(missing_ok=True)
        code, out, _ = run(["app", "logout", "--yes", "--json"], base)
        body = json.loads(out)
        ck("仓内入口（不在 .app 里）→ 1，ok:false，带 command", code == 1 and body["ok"] is False and body["command"] == "app logout"
           and body["error"]["code"] == "failed", out)
        code, out, err = run(["offline", "reset", "--yes"], base)
        ck("不带 --json 时原因写到标准错误", code == 1 and out == "" and "Mac 版" in err, err)
        code, out, _ = run(["app", "logout", "--yes", "--json"], {**base, "MISTAKES_APP_EXECUTABLE": str(old)})
        ck("没有命令入口的旧版可执行文件 → 1，且没有被启动", code == 1 and json.loads(out)["ok"] is False
           and not Path(str(log) + ".launched").exists() and not log.exists(), out)
        code, out, _ = run(["config", "status", "--json"], {**base, "MISTAKES_APP_EXECUTABLE": str(root / "nope")})
        ck("可执行文件不存在 → 1", code == 1 and json.loads(out)["ok"] is False, out)

    print(f"\n{'PASS' if not FAILS else 'FAIL'}: mistakes app commands（{len(FAILS)} 项未过）" if FAILS else "\nPASS: mistakes app commands")
    return 1 if FAILS else 0


if __name__ == "__main__":
    raise SystemExit(main())
