#!/usr/bin/env python3
"""重生图标：从 Resources/icon-src.png（Seedream 定稿原图，2026-09-01 用户逐版挑选）
按定稿裁切参数派生 icon-1024.png。改图标 = 换 icon-src.png 或调 CROP，再跑本脚本。
旧版逐像素绘制脚本已被本派生版取代（原图标风格 2026-09-01 用户判「不达意」整批换掉）。"""
import subprocess, sys, pathlib, shutil

CROP = 0.7  # 保留中心比例（定稿参数，别顺手调）
HERE = pathlib.Path(__file__).parent
SRC = HERE / "Resources/icon-src.png"
if not SRC.exists():
    sys.exit("icon-src.png 不存在，拒绝生成（fail-closed）")

out = HERE / "Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
w = int(subprocess.check_output(["sips","-g","pixelWidth",str(SRC)]).split()[-1])
h = int(subprocess.check_output(["sips","-g","pixelHeight",str(SRC)]).split()[-1])
side = int(min(w, h) * CROP)
tmp = HERE / ".icon_tmp.png"
shutil.copy(SRC, tmp)
# sips 的 -c 与 -z 同传时按内部固定顺序执行（先缩后裁 → 出 655px，实测踩过），必须分两步
subprocess.check_call(["sips","-c",str(side),str(side),str(tmp)], stdout=subprocess.DEVNULL)
subprocess.check_call(["sips","-z","1024","1024","-s","format","png",
                       str(tmp),"--out",str(out)], stdout=subprocess.DEVNULL)
w2 = int(subprocess.check_output(["sips","-g","pixelWidth",str(out)]).split()[-1])
assert w2 == 1024, f"派生出 {w2}px，拒绝（fail-closed）"
tmp.unlink()
plain = HERE / "Resources/icon-1024.png"
if plain.exists():
    shutil.copy(out, plain)   # 两处副本保持一致，防漂移
print(f"icon-1024.png 已从 icon-src.png 派生 (crop {CROP})")
