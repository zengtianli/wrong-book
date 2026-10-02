#!/bin/bash
# Platform-lane launch smoke for Chapter app_sop: `scripts/accept/launch.sh <iphone|ipad|mac|watch|vision>`
# (sop.accept.launch_<lane>). Starts the fictional demo library (scripts/demo/fixture.py: stdlib server on a random
# 127.0.0.1 port, invented account 小林, five demo lessons, pending reviews and today's progress), then hands over
# to Chapter's builtin platform_launch ($SOP_PLATFORM_LAUNCH) with the library and a dev login as launch arguments,
# so the lane is judged on the first data-bearing screen (the app logs "lane-ready": the wrong-book list, or the
# Watch home). platform_launch builds outside the repo through the shared sim_lane, boots the lane's simulator
# headless (the Mac lane launches quietly: hidden, no Dock icon, offscreen render), screenshots and shuts down;
# it redacts the password from the evidence. Never touches edu.tianli.cyou or any real account.
# Exit codes pass through: 0 passed, 75 deferred (simulator lock held or machine loaded), 78 no acceptor/fixture,
# anything else failed.
set -uo pipefail
lane="${1:?usage: launch.sh <iphone|ipad|mac|watch|vision>}"
case "$lane" in iphone|ipad|mac|watch|vision) ;; *) echo "unknown lane $lane"; exit 2;; esac
cd "$(dirname "$0")/../.."
[ -n "${SOP_PLATFORM_LAUNCH:-}" ] || { echo "SOP_PLATFORM_LAUNCH 未设置：只能由 Chapter 的 launch_$lane 验收调用"; exit 78; }
py="$HOME/Dev/.venv/bin/python"
[ -x "$py" ] || py=python3

scratch="$(mktemp -d "${TMPDIR:-/tmp}/wrongbook-launch-$lane.XXXXXX")"
cleanup() { "$py" scripts/demo/fixture.py stop --dir "$scratch" >/dev/null 2>&1; rm -rf "$scratch"; }
trap cleanup EXIT

info="$("$py" scripts/demo/fixture.py start --dir "$scratch" --json)"
code=$?
[ "$code" = 0 ] || { echo "演示学习库没起来（退出码 ${code}）"; exit "$code"; }
read -r url user pw < <(printf '%s' "$info" | "$py" -c 'import json,sys; d=json.load(sys.stdin); print(d["url"], d["user"], d["pw"])')
echo "演示学习库 ${url}（${user}，本机合成数据）"

"$py" "$SOP_PLATFORM_LAUNCH" --arg=-api_base --arg="$url" --arg=-dev_user --arg="$user" --arg=-dev_pw --arg="$pw"
exit $?
