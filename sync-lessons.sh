#!/bin/bash
# 把 ~/Edu 的练习页组装进 app bundle（构建前跑）。
#
# 为什么不把页面提交进本仓：页面的 SSOT 在 ~/Edu（那边有 curriculum.yaml、题库、
# 渲染门、PII 门）。这边只是**取一份装进 bundle**，加了课重跑一次即可。
# 仓里存一份副本就是第二份，改了课两边会漂。
#
# 为什么必须挂在构建前：漏同步的表现是**编译通过、装上能跑、只是那一课点不开**，
# 或者更坏——做的是上一版的题。这种缺陷不报错，只会被当成「设计就这样」。
#
# 组装/剥离/PII 全在 ~/Edu/engine/app_pack.py（与上线共用同一道 PII 门）：
# 包发到设备上和发到公网，对 archive/ 里的姓名、成绩、试卷原图是同一种暴露。
set -euo pipefail

EDU="${EDU_HOME:-$HOME/Edu}"
DST="$(cd "$(dirname "$0")" && pwd)/Resources/Lessons"
PACK="$EDU/engine/app_pack.py"

[ -f "$PACK" ] || { echo "❌ 找不到组装器 $PACK —— ~/Edu 不在？" >&2; exit 1; }

python3 "$PACK" "$DST"

# 组装器会先 rmtree 目标目录 —— 连这个 README 一起清掉。
# 它必须在：clone 之后 Resources/Lessons/ 若不存在，xcodegen 会因
# 「missing source directory」直接拒绝生成工程，**而那时 preBuildScripts 还没轮到跑**，
# 于是「跑一下构建就好了」这条自救路是断的。所以每次组装完补回来。
cat > "$DST/README.md" <<'MD'
# Resources/Lessons

**除了这个文件，目录是空的才正常。** 练习页由 `sync-lessons.sh` 在每次构建前
从 `~/Edu` 组装进来（`~/Edu/engine/app_pack.py`：剥会话 chrome → 过与上线同一道
PII 门 → 写 manifest.json）。

SSOT 在 `~/Edu`（`curriculum.yaml` + 各 `.practice.md` + 题库），不在这个仓。
这里存一份副本就是第二份，加了课两边会漂。对账门：
`python3 ~/Edu/engine/app_pack.py <这个目录> --check`（已挂进 `~/Edu` 的 check_all）。

这个 README 进仓只为让目录存在。组装器每次都会清空目录再重建，
所以它由 `sync-lessons.sh` 在组装之后写回 —— 别手改，改了下次构建就没了。
MD

# 组装器自己是 fail-closed 的，这里再钉一次「产物真的在」——
# 空集不报绿：manifest 没了或一课都没有却 exit 0，就是那种哑掉的守卫。
[ -f "$DST/manifest.json" ] || { echo "❌ 没产出 manifest.json" >&2; exit 1; }
n=$(python3 -c "import json;print(len(json.load(open('$DST/manifest.json'))['lessons']))")
[ "$n" -ge 1 ] || { echo "❌ manifest 里一课都没有" >&2; exit 1; }

# ── 页面里的 JS 契约门（app 这一侧的要求，所以门在这儿，不在 ~/Edu）──
#
# app 用两个页面自己导出的入口，两个都是**没有就静默失灵**的那种：
#   __PRACTICE__.review(gid)   错题本点「复习」→ 引擎出同类新题
#   __EDU_POINTS__.flush(true) 切后台前把学习存档落一次
# 少了任何一个，表现都是「点了没反应 / 进度没了」，**一句报错都没有**。
# 页面是 ~/Edu 渲染时把 practice.js / points_client.js 内联进去的 ——
# 只要那边改完忘了全量重渲，这里就该红。
# ⚠ 只查 kind=practice 的页。精讲页（kind: teach）不带练习引擎，本来就没有这两个入口 ——
# 拿它去要 review/flush 就是让门在正确的包上报红，那种门用两天就会被绕过去。
# 清单里哪几页要查，由 manifest 说了算，不在这儿再写一份判据。
files=$(python3 - "$DST/manifest.json" <<'PYEOF'
import json, sys
m = json.load(open(sys.argv[1]))
ps = [L["file"] for L in m["lessons"] if (L.get("kind") or "practice") == "practice"]
if not ps:
    sys.exit("✘ manifest 里一个 practice 页都没有 —— 拒绝在空集上报绿")
print("\n".join(ps))
PYEOF
) || exit 1

missing=""; scanned=0; want=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  want=$((want + 1))
  f="$DST/$rel"
  [ -e "$f" ] || { missing="$missing\n   $rel 清单里有,磁盘上没有"; continue; }
  scanned=$((scanned + 1))
  grep -q 'review: openReview' "$f" || missing="$missing\n   $rel 缺 __PRACTICE__.review"
  grep -q '__EDU_POINTS__' "$f"     || missing="$missing\n   $rel 缺 __EDU_POINTS__.flush"
done <<< "$files"

# 扫到的页数必须等于清单说的 practice 页数 —— 否则「一个 html 都没落盘」会让上面那个
# 循环一次都不进，missing 空着，门报绿。哑掉的守卫和它要防的 bug 同类。
if [ "$want" -lt 1 ] || [ "$scanned" -ne "$want" ]; then
  echo "❌ 清单里 $want 个出题页，磁盘上只扫到 $scanned 个 —— 拒绝在缺页的包上报绿" >&2
  printf "%b\n" "$missing" >&2
  exit 1
fi
if [ -n "$missing" ]; then
  printf "❌ 包里的页面缺 app 依赖的 JS 入口(~/Edu 改了引擎没全量重渲?):%b\n" "$missing" >&2
  echo "   修: cd ~/Edu && for f in primary-*/*.practice.md; do python3 engine/practice_render.py \$f; done" >&2
  exit 1
fi

echo "   → bundle 里 $n 课"
du -sh "$DST" | sed 's/^/   /'
