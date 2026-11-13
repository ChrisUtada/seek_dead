#!/usr/bin/env python3
"""灰阶母版拼图切分：AI 出的 3×2 拼图 → 96px RGBA 母版。

与 tools/split_symbols.py 的区别：这批母版刻意让 AI 只画灰阶、背景用洋红。
实测背景是渐变洋红 (213,5,174)~(221,6,176)，固定底色 / 欧氏色距法都失效，
改用洋红度判据 min(R,B)-G：背景约 170，灰阶物件约 0，分界极干净。
切完后交 tools/recolor_symbols.py 统一注入元素色并派生 32 / 16 两档。

用法：
  py -3.15 tools/split_symbol_sheet.py <拼图.png> name1,name2,name3,name4,name5,name6
  py -3.15 tools/split_symbol_sheet.py <拼图.png> a,b,c,d          # 只用前 4 格
  py -3.15 tools/split_symbol_sheet.py <拼图.png> names --preview   # 样图写到 .workbuddy/art_trials/
  py -3.15 tools/split_symbol_sheet.py <拼图.png> a,b,c,d --grid=2x2 --preview   # 2 列 2 行拼图

输出：assets/icons/symbols/_source/<name>_96.png
"""
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets/icons/symbols/_source")
PREVIEW = os.path.join(ROOT, ".workbuddy/art_trials/symbol_sheets")

MAG_BG = 40           # 洋红度高于此值判为背景
WATERMARK_X = 870     # 1024 图右下角「AI生成 WORKBUDDY」水印区
WATERMARK_Y = 915


def magenta(c):
    r, g, b = c[0], c[1], c[2]
    return min(r, b) - g


def cut_bg(im: Image.Image) -> Image.Image:
    """洋红度硬阈值 + 水印区直清；主体是灰阶，不需要 floodfill。"""
    im = im.convert("RGB")
    w, h = im.size
    src = im.load()
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dst = out.load()
    removed = 0
    for y in range(h):
        for x in range(w):
            c = src[x, y]
            if magenta(c) > MAG_BG:
                removed += 1
                continue
            if x >= WATERMARK_X and y >= WATERMARK_Y and w == 1024 and h == 1024:
                continue
            dst[x, y] = (c[0], c[1], c[2], 255)
    print(f"  抠底：清除 {removed} px 背景 / 水印区已置透明")
    return out


def normalize(im: Image.Image, side: int) -> Image.Image:
    """与 tools/split_symbols.py 完全一致：裁透明边 → 5% 留白 → 居中归一。"""
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
    sheet_path = sys.argv[1]
    names = [n for n in sys.argv[2].split(",") if n]
    preview = "--preview" in sys.argv
    grid = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--grid=")), "3x2")
    assert grid in ("3x2", "2x2"), f"不支持的布局 {grid}"
    cols, rows = (3, 2) if grid == "3x2" else (2, 2)
    assert 1 <= len(names) <= cols * rows, f"一次最多 {cols * rows} 格"
    sheet = cut_bg(Image.open(sheet_path))
    W, H = sheet.size
    cw, ch = W // cols, H // rows
    os.makedirs(PREVIEW if preview else OUT, exist_ok=True)
    tiles = []
    for idx, name in enumerate(names):
        col, row = idx % cols, idx // cols
        cell = sheet.crop((col * cw, row * ch, (col + 1) * cw, (row + 1) * ch))
        i96 = normalize(cell, 96)
        target = os.path.join(PREVIEW if preview else OUT,
                              f"{name}_preview.png" if preview else f"{name}_96.png")
        i96.save(target)
        opaque = sum(1 for p in i96.get_flattened_data() if p[3] > 128)
        print(f"  [{col},{row}] {name:28s} 母版不透明 {opaque:5d} px -> {os.path.basename(target)}")
        tiles.append((name, i96))
    if preview:
        # 拼一张 4x 预览，便于人工核对造型与抠底
        S, cellw = 3, 96 * 3 + 16
        from PIL import ImageDraw
        canvas = Image.new("RGBA", (16 + cellw * len(tiles), 16 + 96 * S + 24), (29, 18, 25, 255))
        d = ImageDraw.Draw(canvas)
        for i, (name, im) in enumerate(tiles):
            x = 16 + i * cellw
            d.text((x, 4), name, fill=(225, 220, 210, 255))
            canvas.alpha_composite(im.resize((96 * S, 96 * S), Image.NEAREST), (x, 20))
        canvas.convert("RGB").save(os.path.join(PREVIEW, "sheet_preview.png"))
        print(f"  预览：{PREVIEW}/sheet_preview.png")


if __name__ == "__main__":
    main()
