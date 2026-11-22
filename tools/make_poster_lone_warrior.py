#!/usr/bin/env python3
"""孤军奋战主题海报：利用现有角色/怪物/背景素材合成。

输出：docs/poster_lone_warrior.png（1200x1600 竖版）
风格：像素画，最近邻放大，暗色地下城 + 冷色敌群 + 孤身骑士 + 一道暖光。
"""
from __future__ import annotations
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
W, H = 1200, 1600

def load(p):
    return Image.open(ROOT / p).convert("RGBA")

def scale_nn(img, size):
    return img.resize(size, Image.Resampling.NEAREST)

def tint(img, color, strength):
    """给 RGB 通道叠加色相，保留 alpha。"""
    r, g, b, a = img.split()
    col = Image.new("RGBA", img.size, color)
    out = Image.blend(img, col, strength)
    out.putalpha(a)
    return out

def main():
    # 1) 背景：放大铺满，暗化
    bg = load("assets/bg/act1_bg.png")
    bg = scale_nn(bg, (W, H))
    bg = ImageEnhance.Brightness(bg).enhance(0.55)
    bg = ImageEnhance.Color(bg).enhance(0.75)
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    canvas.alpha_composite(bg)

    # 冷色雾罩 + 顶部/底部暗角
    fog = Image.new("RGBA", (W, H), (10, 16, 28, 0))
    d = ImageDraw.Draw(fog)
    for y in range(H):
        top = max(0, 1 - y / (H * 0.55))
        bot = max(0, (y - H * 0.55) / (H * 0.45))
        alpha = int(60 * top + 90 * bot)
        d.line([(0, y), (W, y)], fill=(8, 12, 22, alpha))
    canvas.alpha_composite(fog)

    # 2) 敌群：层层排列在画面中上部，纵深感靠尺寸与明度
    enemies = [
        # (path, center_x, bottom_y, height, tint, strength)
        ("assets/characters/brittle_gargoyle/idle_01_hd.png", 250, 760, 300, (40, 120, 160), 0.10),
        ("assets/characters/frozen_urn/boss_96_hd.png",        600, 720, 340, (40, 110, 170), 0.10),
        ("assets/characters/cocoon_sentinel/open_hd.png",      950, 780, 300, (60, 130, 150), 0.12),
        ("assets/characters/shattered_king/idle_01.png",       430, 860, 230, (30, 90, 130),  0.18),
        ("assets/characters/hero_shadow/idle_01.png",          770, 870, 240, (25, 70, 120),   0.22),
        ("assets/characters/acid_ghoul/idle_01_hd.png",        140, 930, 190, (50, 110, 70),   0.20),
        ("assets/characters/ember_golem/idle_01_hd.png",      1060, 930, 190, (120, 70, 40),   0.22),
        ("assets/characters/grand_inquisitor/boss_96.png",     600, 980, 180, (90, 40, 50),    0.25),
        ("assets/characters/frost_bat/idle_01_hd.png",         320, 620, 120, (60, 130, 170),  0.15),
        ("assets/characters/void_whisperer/idle_01_hd.png",    900, 650, 120, (60, 60, 120),   0.20),
    ]
    # 远处敌人先画（在上方/更小），近处后画
    enemies.sort(key=lambda e: e[2])
    for path, cx, by, h, tc, strength in enemies:
        im = load(path)
        w = int(im.width * h / im.height)
        im = scale_nn(im, (w, h))
        im = tint(im, tc, strength)
        # 远处敌人更暗、更淡，制造纵深
        fade = max(0.45, min(1.0, by / 1000.0))
        im = ImageEnhance.Brightness(im).enhance(fade)
        x = cx - w // 2
        y = by - h
        canvas.alpha_composite(im, (x, y))

    # 3) 一道暖光：从骑士身后投向敌群（视觉引导 + 孤身感）
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.polygon([(560, 1180), (640, 1180), (840, 700), (360, 700)], fill=(255, 170, 70, 40))
    glow = glow.filter(ImageFilter.GaussianBlur(60))
    canvas.alpha_composite(glow)

    # 4) 骑士：孤身立于下方，放大，冷色暗调，背对光源
    hero = load("assets/characters/knight_v1/hero_hd_80.png")
    hero_h = 420
    hero = scale_nn(hero, (int(hero.width * hero_h / hero.height), hero_h))
    hero = ImageEnhance.Brightness(hero).enhance(0.82)
    hero = tint(hero, (30, 40, 60), 0.10)
    hx, hy = W // 2 - hero.width // 2 - 40, H - hero.height - 150
    # 骑士脚下阴影
    sh = Image.new("RGBA", (hero.width, 40), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse((10, 5, hero.width - 10, 38), fill=(0, 0, 0, 150))
    sh = sh.filter(ImageFilter.GaussianBlur(12))
    canvas.alpha_composite(sh, (hx, hy + hero.height - 20))
    canvas.alpha_composite(hero, (hx, hy))

    # 5) 文字
    d = ImageDraw.Draw(canvas)
    font_zh = ImageFont.truetype(str(ROOT / "assets/fonts/zpix.ttf"), 96)
    font_en = ImageFont.truetype(str(ROOT / "assets/fonts/zpix.ttf"), 150)
    font_sm = ImageFont.truetype(str(ROOT / "assets/fonts/zpix.ttf"), 34)
    font_sm2 = ImageFont.truetype(str(ROOT / "assets/fonts/VonwaonBitmap-12px.ttf"), 26)

    # 顶部渐暗条，保证标题可读
    d.rectangle((0, 0, W, 340), fill=(6, 9, 16, 210))
    title = "SEEK DEAD"
    bb = d.textbbox((0, 0), title, font=font_en)
    tw = bb[2] - bb[0]
    d.text(((W - tw) / 2 + 4, 78 + 4), title, font=font_en, fill=(0, 0, 0, 255))
    d.text(((W - tw) / 2, 78), title, font=font_en, fill=(210, 220, 235, 255))
    # 副标题
    sub = "孤 军 奋 战"
    bb2 = d.textbbox((0, 0), sub, font=font_zh)
    d.text(((W - (bb2[2]-bb2[0])) / 2, 250), sub, font=font_zh, fill=(150, 175, 200, 255))

    # 底部标语
    bottom = "ONE  AGAINST  ALL"
    bb3 = d.textbbox((0, 0), bottom, font=font_sm)
    d.rectangle((0, H - 100, W, H), fill=(6, 9, 16, 200))
    d.text(((W - (bb3[2]-bb3[0])) / 2, H - 72), bottom, font=font_sm, fill=(170, 185, 205, 255))

    out = ROOT / "docs/poster_lone_warrior.png"
    out.parent.mkdir(exist_ok=True)
    canvas.convert("RGB").save(out, "PNG")
    print("saved:", out.relative_to(ROOT), canvas.size)

if __name__ == "__main__":
    main()
