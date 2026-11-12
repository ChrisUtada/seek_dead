#!/usr/bin/env python3
"""六元素图标切分：AI 出的 3×2 拼图 → 6 个独立图标（48 + 96 母版）。

用法：python tools/split_elements.py <拼图.png>

输出：assets/icons/elements/<elem>.png (48) 与 _source/<elem>_96.png (96)
处理链与武器图标一致：去纯色底 → 清水印 → 按单元格裁切 → 归一 → BOX 降采样 + 量化。
"""
import sys
from collections import deque

from PIL import Image, ImageEnhance

SRC = sys.argv[1]
OUT = "assets/icons/elements"
SRCDIR = f"{OUT}/_source"
NAMES = ["fire", "ice", "poison", "light", "dark", "none"]   # 3 列 × 2 行，从左到右、从上到下


def cut_bg(im: Image.Image) -> Image.Image:
    im = im.convert("RGB")
    w, h = im.size
    px = im.load()
    bg = px[5, 5]

    def close(c) -> bool:
        return all(abs(c[i] - bg[i]) <= 20 for i in range(3))

    out = im.convert("RGBA"); op = out.load()
    seen, q = set(), deque()
    for x in range(w):
        for y in (0, h - 1):
            q.append((x, y)); seen.add((x, y))
    for y in range(h):
        for x in (0, w - 1):
            q.append((x, y)); seen.add((x, y))
    while q:
        x, y = q.popleft()
        if not close(px[x, y]):
            continue
        op[x, y] = (0, 0, 0, 0)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen:
                seen.add((nx, ny)); q.append((nx, ny))
    for y in range(890, h):          # 水印区
        for x in range(840, w):
            op[x, y] = (0, 0, 0, 0)
    return out


def normalize(im: Image.Image, side: int) -> Image.Image:
    bb = im.getbbox()
    if bb is None:
        return Image.new("RGBA", (side, side), (0, 0, 0, 0))
    im = im.crop(bb)
    w, h = im.size
    pad = int(max(w, h) * 0.06)
    canvas = Image.new("RGBA", (max(w, h) + pad * 2,) * 2, (0, 0, 0, 0))
    canvas.alpha_composite(im, ((canvas.width - w) // 2, (canvas.height - h) // 2))
    return canvas.resize((side, side), Image.LANCZOS)


def main() -> None:
    sheet = cut_bg(Image.open(SRC))
    W, H = sheet.size
    cw, ch = W // 3, H // 2
    for idx, name in enumerate(NAMES):
        col, row = idx % 3, idx // 3
        cell = sheet.crop((col * cw, row * ch, (col + 1) * cw, (row + 1) * ch))
        i96 = normalize(cell, 96)
        i96.save(f"{SRCDIR}/{name}_96.png")

        a = i96.resize((48, 48), Image.BOX)
        rgb = a.convert("RGB").quantize(colors=26, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")
        rgb = ImageEnhance.Contrast(rgb).enhance(1.10)
        i48 = rgb.convert("RGBA")
        i48.putalpha(a.split()[3])
        i48.save(f"{OUT}/{name}.png")
        print(f"{name}: 48 + 96 ok")


if __name__ == "__main__":
    main()
