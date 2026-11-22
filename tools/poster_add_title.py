#!/usr/bin/env python3
"""给 AI 生成的横版海报叠加中文主标题「赦罪者」+ 英文副标题，并覆盖右下角 AI 水印。"""
from __future__ import annotations
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "generated-images/Wide_epic_cinematic_key_art_fo_2026-11-22T09-18-14.png"
OUT = ROOT / "docs/poster_lone_warrior_wide.png"

def centered(draw, text, font, y, fill, W, outline=None, oy=0):
    bb = draw.textbbox((0, 0), text, font=font)
    tw = bb[2] - bb[0]
    x = (W - tw) // 2
    if outline:
        draw.text((x + oy, y + oy), text, font=font, fill=outline)
    draw.text((x, y), text, font=font, fill=fill)

def main():
    im = Image.open(SRC).convert("RGBA")
    W, H = im.size
    d = ImageDraw.Draw(im)

    # 覆盖右下角水印：取左侧相邻石板色块平移覆盖（水印约在 x>W-220, y>H-100）
    patch = im.crop((W - 420, H - 120, W - 210, H - 10))
    im.alpha_composite(patch, (W - 215, H - 120))

    font_cn = ImageFont.truetype(str(ROOT / "assets/fonts/zpix.ttf"), 118)
    font_en = ImageFont.truetype(str(ROOT / "assets/fonts/zpix.ttf"), 40)

    # 顶部暗化渐变，保证标题可读
    grad = Image.new("RGBA", (W, 300), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    for y in range(300):
        gd.line([(0, y), (W, y)], fill=(5, 8, 14, int(185 * (1 - y / 300))))
    im.alpha_composite(grad, (0, 0))
    d = ImageDraw.Draw(im)

    centered(d, "赦 罪 者", font_cn, 40, (225, 232, 240, 255), W, outline=(0, 0, 0, 255), oy=4)
    centered(d, "S E E K   D E A D", font_en, 178, (150, 175, 200, 255), W)

    # 底部不再加 ONE AGAINST ALL
    out = OUT
    im.convert("RGB").save(out, "PNG")
    print("saved:", out.relative_to(ROOT), im.size)

if __name__ == "__main__":
    main()
