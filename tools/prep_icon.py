#!/usr/bin/env python3
"""武器图标后处理：AI 原图 → 48×48 游戏图标 + 96×96 母版。

用法：
    python tools/prep_icon.py <AI原图.png> <资源id> [--tint]

做的事：
 1. 从四边泛洪去掉纯色底（AI 出图固定灰底 #7A7A7A）
 2. 清掉右下角水印区（x>=850, y>=890）
 3. 按内容 bbox 裁切，居中放进正方形画布（四周留 6% 安全边）
 4. 生成 96×96 母版 → assets/icons/weapons/_source/icon_<id>_96.png
 5. 96 母版用 BOX 降采样 + 26 色量化 + 对比 1.12 → 48×48 游戏图
    （LANCZOS 会把轮廓平均掉，48px 下必须用 BOX+量化才够硬）
 6. 输出 assets/icons/weapons/icon_<id>.png
"""
import sys
from collections import deque

from PIL import Image, ImageEnhance

SRC = sys.argv[1]
WID = sys.argv[2]
OUT_DIR = "assets/icons/weapons"
SRC_DIR = f"{OUT_DIR}/_source"


def cut_background(im: Image.Image) -> Image.Image:
    im = im.convert("RGB")
    w, h = im.size
    px = im.load()
    bg = px[5, 5]
    tol = 20

    def close(c) -> bool:
        return all(abs(c[i] - bg[i]) <= tol for i in range(3))

    seen, q = set(), deque()
    for x in range(w):
        for y in (0, h - 1):
            q.append((x, y)); seen.add((x, y))
    for y in range(h):
        for x in (0, w - 1):
            q.append((x, y)); seen.add((x, y))

    out = im.convert("RGBA")
    op = out.load()
    while q:
        x, y = q.popleft()
        if not close(px[x, y]):
            continue
        op[x, y] = (0, 0, 0, 0)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen:
                seen.add((nx, ny)); q.append((nx, ny))

    # 水印：右下角固定区域直接置透明
    for y in range(890, h):
        for x in range(850, w):
            op[x, y] = (0, 0, 0, 0)
    return out


def main() -> None:
    im = cut_background(Image.open(SRC))
    bb = im.getbbox()
    if bb is None:
        raise SystemExit("全部透明：底色阈值可能不对")
    im = im.crop(bb)

    w, h = im.size
    side = max(w, h)
    pad = int(side * 0.06)
    canvas = Image.new("RGBA", (side + pad * 2, side + pad * 2), (0, 0, 0, 0))
    canvas.alpha_composite(im, ((canvas.width - w) // 2, (canvas.height - h) // 2))

    i96 = canvas.resize((96, 96), Image.LANCZOS)
    i96.save(f"{SRC_DIR}/icon_{WID}_96.png")

    a = i96.resize((48, 48), Image.BOX)
    rgb = a.convert("RGB").quantize(colors=26, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")
    rgb = ImageEnhance.Contrast(rgb).enhance(1.12)
    i48 = rgb.convert("RGBA")
    i48.putalpha(a.split()[3])
    i48.save(f"{OUT_DIR}/icon_{WID}.png")
    print(f"ok: {OUT_DIR}/icon_{WID}.png (48)  +  {SRC_DIR}/icon_{WID}_96.png (96)  bbox={bb}")


if __name__ == "__main__":
    main()
