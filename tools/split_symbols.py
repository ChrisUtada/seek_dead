#!/usr/bin/env python3
"""符号图标切分：AI 出的 3×2 拼图 → 独立符号图标（16 / 32 / 96 三档）。

用法：python tools/split_symbols.py <拼图.png> fire_slash,frost_slash,...

输出：
  assets/icons/symbols/<name>.png        32×32（卡片 / 悬停窗）
  assets/icons/symbols/16/<name>.png     16×16（转轮 —— 实际显示尺寸）
  assets/icons/symbols/_source/<name>_96.png
16px 用 BOX 降采样 + 14 色量化 + 对比 1.18：转轮只有 16px，必须把颜色砍到最少。
"""
import sys

from PIL import Image, ImageEnhance

NAMES_FALLBACK = ["fire_slash", "frost_slash", "poison_slash",
                  "holy_slash", "shadow_slash", "iron_slash"]
SRC = sys.argv[1]
NAMES = sys.argv[2].split(",") if len(sys.argv) > 2 else NAMES_FALLBACK

OUT = "assets/icons/symbols"


def cut_bg(im: Image.Image) -> Image.Image:
    im = im.convert("RGB")
    w, h = im.size
    px = im.load()
    bg = px[5, 5]

    def close(c) -> bool:
        return all(abs(c[i] - bg[i]) <= 20 for i in range(3))

    out = im.convert("RGBA"); op = out.load()
    seen, q = set(), []
    stack = []
    for x in range(0, w, 2):
        for y in (0, h - 1):
            if (x, y) not in seen:
                seen.add((x, y)); stack.append((x, y))
    for y in range(0, h, 2):
        for x in (0, w - 1):
            if (x, y) not in seen:
                seen.add((x, y)); stack.append((x, y))
    while stack:
        x, y = stack.pop()
        if not close(px[x, y]):
            continue
        op[x, y] = (0, 0, 0, 0)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen:
                seen.add((nx, ny)); stack.append((nx, ny))
    for y in range(880, h):        # 水印区
        for x in range(830, w):
            op[x, y] = (0, 0, 0, 0)
    return out


def normalize(im: Image.Image, side: int) -> Image.Image:
    bb = im.getbbox()
    if bb is None:
        return Image.new("RGBA", (side, side), (0, 0, 0, 0))
    im = im.crop(bb)
    w, h = im.size
    pad = int(max(w, h) * 0.05)
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
        i96.save(f"{OUT}/_source/{name}_96.png")
        for side, colors, contrast, sub in ((32, 22, 1.12, ""), (16, 14, 1.18, "16/")):
            a = i96.resize((side, side), Image.BOX)
            rgb = a.convert("RGB").quantize(colors=colors, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")
            rgb = ImageEnhance.Contrast(rgb).enhance(contrast)
            o = rgb.convert("RGBA"); o.putalpha(a.split()[3])
            o.save(f"{OUT}/{sub}{name}.png")
        print(f"{name}: 96 / 32 / 16 ok")


if __name__ == "__main__":
    main()
