"""实测 UI 纹理的正确九宫格 margin。

比"边缘颜色均匀性"更可靠的判据：
  内腔矩形 (m,W-m)x(m,H-m) 必须整个等于"背景模板"——
  实心底图 = 取中心点颜色；透明底图 = 全透明。

用法:
    py -3.15 tools/fit_9slice_margin.py                 # 扫描所有在用 UI 纹理
    py -3.15 tools/fit_9slice_margin.py a.png b.png     # 只测指定文件
"""
import glob
import os
import sys

from PIL import Image

TARGETS = [
    "assets/ui/dark_ages/frames/*.png",
    "assets/ui/*.png",
]


def probe(path, tol=6):
    im = Image.open(path).convert("RGBA")
    W, H = im.size
    px = im.load()
    center = px[W // 2, H // 2]
    solid = center[3] > 0
    if solid:
        bg = center[:3]

        def is_bg(c):
            return c[3] > 0 and all(abs(c[i] - bg[i]) <= tol for i in range(3))
    else:
        def is_bg(c):
            return c[3] == 0

    # 先量边条厚度（沿中心行/列，从外向内连续非背景的长度）
    t = 0
    while t < W and not is_bg(px[t, H // 2]):
        t += 1
    l = 0
    while l < H and not is_bg(px[W // 2, l]):
        l += 1

    # 从小到大找第一个"内腔全背景"的 m
    good = None
    for m in range(1, min(W, H) // 2):
        if all(is_bg(px[x, y]) for y in range(m, H - m) for x in range(m, W - m)):
            good = m
            break
    # 校验边条是否平移不变（可平铺），否则只能拉伸
    tileable = None
    if good:
        m = good
        tileable = True
        for x in range(m, W - m):
            for y in range(m):
                if px[x, y] != px[m, y]:
                    tileable = False
                    break
            if not tileable:
                break
        if tileable:
            for y in range(m, H - m):
                for x in range(m):
                    if px[x, y] != px[x, m]:
                        tileable = False
                        break
                if not tileable:
                    break
    return W, H, ("solid" if solid else "transparent"), t, l, good, tileable


def main():
    paths = sys.argv[1:]
    if not paths:
        for pat in TARGETS:
            paths += sorted(glob.glob(pat))
    print(f"{'file':46s} {'size':9s} {'kind':12s} {'edge':5s} {'margin':6s} {'tile'}")
    for p in paths:
        try:
            W, H, kind, t, l, m, tile = probe(p)
        except Exception as e:  # noqa: BLE001
            print(f"{os.path.basename(p):46s} ERROR {e}")
            continue
        flag = "" if m else "  <- no clean margin"
        print(
            f"{os.path.basename(p):46s} {W:3d}x{H:<4d} {kind:12s} {t:>2d}/{l:<2d} "
            f"{str(m):6s} {str(tile)}{flag}"
        )


if __name__ == "__main__":
    main()
