#!/usr/bin/env python3
"""生成 app 图标 —— 作业本 + 老师的红勾。

    python3 make_icon.py          # 逐像素可复现（无随机、不联网、不依赖任何外部图）

为什么是这个图形：这个 app 干的事就一件 —— **把打叉的那类题练成打勾**。
所以图标只画那个结果：横格本上一个红勾。

为什么不画得更"丰富"：桌面上它是 60×60。points-deck 那边踩过的教训写在
它的 make_icon.py 顶部 —— 硬边几何图形缩到 60×60 只剩一条线。这里的对策是
①只放一个主体 ②4 倍超采样再 LANCZOS 缩，边缘才有抗锯齿 ③满幅构图，几乎不留白。

配色跟着它包着的那些练习页走（亮色、纸感），不跟 points-deck 的绘本插画走 ——
那是另一个 app 的视觉语言，两个图标在桌面上必须一眼能分开。
"""
import pathlib
import sys

from PIL import Image, ImageDraw

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "Resources" / "icon-1024.png"
OUT_ASSET = HERE / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024.png"

S = 1024
SS = 4                      # 超采样倍数：先画 4096 再缩，边缘才不是锯齿
N = S * SS

PAPER_TOP = (255, 251, 242)
PAPER_BOT = (247, 238, 221)
RULE = (176, 200, 224)
MARGIN_RED = (226, 170, 170)
INK_RED = (214, 45, 42)

img = Image.new("RGB", (N, N), PAPER_TOP)
d = ImageDraw.Draw(img)

# 纸：自上而下极轻的暖色渐变（纯色会显得像塑料）
for y in range(N):
    t = y / (N - 1)
    d.line([(0, y), (N, y)],
           fill=tuple(int(a + (b - a) * t) for a, b in zip(PAPER_TOP, PAPER_BOT)))

# 横格线：5 条，间距按黄金比留白，最上和最下不贴边
for i in range(5):
    y = int(N * (0.215 + i * 0.145))
    d.line([(int(N * 0.10), y), (int(N * 0.94), y)], fill=RULE, width=int(N * 0.007))
# 左侧红色页边线 —— 作业本的标志性一笔
xm = int(N * 0.165)
d.line([(xm, int(N * 0.06)), (xm, int(N * 0.94))], fill=MARGIN_RED, width=int(N * 0.008))

# 红勾：两笔，短笔细、长笔粗（老师批改就是这个笔势）。
# 用 line + 圆角端点，不用多边形 —— 多边形的尖角缩小后会崩成锯齿。
p0 = (int(N * 0.255), int(N * 0.560))
p1 = (int(N * 0.435), int(N * 0.745))
p2 = (int(N * 0.815), int(N * 0.240))
# ⚠ 一笔画完，**单色等宽**。第一版是两笔两种红、两种宽度，转折处必然出现
# 一道接缝和一个球形凸起 —— 那是「拿两个图元拼一个形状」的老毛病，
# 放大好看，缩到 60×60 就是一坨。真要笔锋变化得走矢量描边，不是叠图元。
W = int(N * 0.098)
d.line([p0, p1, p2], fill=INK_RED, width=W, joint="curve")
for p in (p0, p1, p2):                      # 圆端点：PIL 的 line 没有 round cap
    rr = W // 2
    d.ellipse([p[0] - rr, p[1] - rr, p[0] + rr, p[1] + rr], fill=INK_RED)

icon = img.resize((S, S), Image.LANCZOS)

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT_ASSET.parent.mkdir(parents=True, exist_ok=True)
icon.save(OUT)
icon.save(OUT_ASSET)

# fail-closed：产物必须真的在、真的是 1024（缺图标的表现是桌面白板，编译不报错）
for p in (OUT, OUT_ASSET):
    if not p.is_file() or Image.open(p).size != (S, S):
        sys.exit(f"✘ 图标没产出或尺寸不对：{p}")
print(f"✅ 图标 {S}×{S} → {OUT.relative_to(HERE)} 与 asset catalog 各一份")
