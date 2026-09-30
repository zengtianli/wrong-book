#!/bin/sh
# 把 mistakes 命令装到 ~/.local/bin。
#
# 本机装了 Mac 版（按 bundle id 找，不猜 App 名）时，命令在 .app 里：
#   <App>/Contents/Resources/bin/mistakes —— 本机 Mac 构建时由 project.yml 的构建阶段拷进去、封进签名；
#   链接指向那里（Chapter cli_entry 的判据：Mac App 的命令随 .app 走）。
# 没装 Mac 版时链到本仓 cli/mistakes（改源码立即生效）。
# 装了 Mac 版、但那个 .app 是旧构建、里面还没有命令：拒绝（退出 1），先重装 Mac 版，不回落到仓库。
#
#   sh cli/install.sh              安装/修正链接
#   sh cli/install.sh --check      只核对，不改（未装、指错或 --help 不退出 0 时退出 1）
#   sh cli/install.sh --uninstall  只删指向本产品入口（.app 内或本仓）的链接
#
# 已存在同名普通文件或指向别处的链接时拒绝覆盖（退出 1），不动别人的命令。
# 测试可用 EDU_CLI_BIN_DIR 换链接目录、EDU_APPLICATIONS_DIR 换查找 .app 的目录（空格分隔）。
set -eu
CMD=mistakes
BUNDLE_ID=cyou.tianli.wrongbook
HERE=$(cd "$(dirname "$0")" && pwd -P)
REPO_ENTRY="${HERE}/${CMD}"
BIN="${EDU_CLI_BIN_DIR:-$HOME/.local/bin}"
LINK="${BIN}/${CMD}"
APPS_DIRS="${EDU_APPLICATIONS_DIR:-/Applications $HOME/Applications}"

realpath_of() { python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
current() { if [ -L "${LINK}" ]; then realpath_of "${LINK}"; fi; }

# 已装的、CFBundleIdentifier 等于本产品的 .app（第一个；/Applications 优先）
host_app() {
  # shellcheck disable=SC2086
  python3 - "${BUNDLE_ID}" ${APPS_DIRS} <<'PY'
import glob, os, plistlib, sys
want, dirs = sys.argv[1], sys.argv[2:]
for d in dirs:
    for plist in sorted(glob.glob(os.path.join(d, "*.app", "Contents", "Info.plist"))):
        try:
            with open(plist, "rb") as f:
                if plistlib.load(f).get("CFBundleIdentifier") == want:
                    print(os.path.realpath(os.path.dirname(os.path.dirname(plist))))
                    raise SystemExit(0)
        except (OSError, ValueError, plistlib.InvalidFileException):
            continue
PY
}

APP=$(host_app)
if [ -n "${APP}" ]; then
  ENTRY="${APP}/Contents/Resources/bin/${CMD}"
  WHERE="Mac App ${APP}"
else
  ENTRY="${REPO_ENTRY}"
  WHERE="本仓（本机没装 Mac 版）"
fi

# 本产品自己的入口：本仓那份，或任一 .app 里 Contents/Resources/bin/<命令>（含已删掉的旧 .app 留下的悬空链接）
ours() {
  case "$1" in
    "${REPO_ENTRY}") return 0 ;;
    *.app/Contents/Resources/bin/"${CMD}") return 0 ;;
  esac
  return 1
}

missing_in_app() {
  echo "✘ 已装的 Mac 版 ${APP} 里没有 Contents/Resources/bin/${CMD}（旧构建）。" >&2
  echo "  先重装 Mac 版（bash install-to-mac.sh --no-launch），再跑 sh cli/install.sh；现有链接未动。" >&2
}

case "${1:-}" in
  --check)
    cur=$(current)
    if [ -n "${APP}" ] && [ ! -x "${ENTRY}" ]; then missing_in_app; echo "✗ ${LINK} 现为：${cur:-（不存在）}"; exit 1; fi
    if [ "${cur}" = "${ENTRY}" ] && [ -x "${ENTRY}" ] && "${LINK}" --help >/dev/null 2>&1 </dev/null; then
      echo "✓ ${LINK} → ${ENTRY}（${WHERE}）"; exit 0
    fi
    echo "✗ ${LINK} 未指向 ${ENTRY}（${WHERE}；现为：${cur:-（不存在）}）"; exit 1 ;;
  --uninstall)
    cur=$(current)
    if [ -n "${cur}" ] && ours "${cur}"; then rm "${LINK}"; echo "已移除 ${LINK}"; else echo "${LINK} 不是本产品入口的链接，未动"; fi
    exit 0 ;;
  "") ;;
  *) echo "用法: sh cli/install.sh [--check|--uninstall]" >&2; exit 64 ;;
esac

if [ -n "${APP}" ] && [ ! -x "${ENTRY}" ]; then missing_in_app; exit 1; fi
[ -n "${APP}" ] || chmod +x "${ENTRY}"
mkdir -p "${BIN}"
if [ -e "${LINK}" ] || [ -L "${LINK}" ]; then
  cur=$(current)
  if [ "${cur}" = "${ENTRY}" ]; then echo "✓ 已安装 ${LINK} → ${ENTRY}（${WHERE}）"; exit 0; fi
  if [ ! -L "${LINK}" ]; then echo "✘ ${LINK} 是普通文件，拒绝覆盖" >&2; exit 1; fi
  if ! ours "${cur}"; then echo "✘ ${LINK} 指向 ${cur}，不是本产品入口；确认后手动删除再装" >&2; exit 1; fi
  rm "${LINK}"                                   # 本产品的旧入口（仓库 ↔ .app 切换）
fi
ln -s "${ENTRY}" "${LINK}"
"${LINK}" --help >/dev/null </dev/null
echo "✓ 已安装 ${LINK} → ${ENTRY}（${WHERE}；${CMD} --help 退出 0）"
