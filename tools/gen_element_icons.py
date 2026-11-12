#!/usr/bin/env python3
"""六元素图标生成器：32×32 手绘式像素图标（再降一半出 16×16）。

风格对齐项目：暗褐描边 #241C18、左上受光、每材质 3–4 阶、不用抗锯齿。
用法：python tools/gen_element_icons.py
输出：assets/icons/elements/icon_<el>_32.png / _16.png  + _source 4x 预览
"""
import math
import os

from PIL import Image

OUT = "assets/icons/elements"
SRC = f"{OUT}/_source"
S = 32
C = 16  # 中心

OUTLINE = (36, 28, 24, 255)
NONE = (0, 0, 0, 0)

# 元素配色（与 docs/武器图标绘制清单.md 一致）
PAL = {
    "fire":   [(96, 34, 14), (168, 66, 22), (236, 132, 44), (255, 206, 92), (255, 246, 214)],
    "ice":    [(28, 52, 62), (58, 104, 120), (111, 183, 201), (203, 239, 245), (245, 253, 255)],
    "poison": [(32, 48, 20), (72, 96, 32), (127, 163, 58), (199, 224, 106), (235, 248, 176)],
    "light":  [(96, 78, 32), (168, 142, 74), (232, 216, 154), (255, 243, 208), (255, 255, 250)],
    "dark":   [(22, 14, 30), (52, 34, 74), (108, 78, 134), (169, 139, 192), (216, 198, 232)],
    "none":   [(40, 38, 34), (84, 80, 74), (142, 138, 130), (201, 196, 184), (232, 228, 218)],
}


def blank():
    return Image.new("RGBA", (S, S), NONE)


def put(px, x, y, col):
    if 0 <= x < S and 0 <= y < S:
        px[x, y] = col


def outline_pass(im):
    """给不透明区域外圈补 1px 暗描边（只描外向，保留内部亮部）。"""
    px = im.load()
    add = []
    for y in range(S):
        for x in range(S):
            if px[x, y][3] != 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < S and 0 <= ny < S and px[nx, ny][3] != 0:
                    add.append((x, y))
                    break
    for (x, y) in add:
        px[x, y] = OUTLINE
    return im


def shades(pal, v):
    """v=0..1 明度 → 从暗到亮取阶。"""
    i = int(round(v * (len(pal) - 1)))
    return tuple(pal[max(0, min(len(pal) - 1, i))]) + (255,)


def make_fire(px, pal):
    # 三条舌：主焰 + 左小焰 + 右小焰，底部聚拢
    for y in range(6, 28):
        t = (y - 6) / 21.0                     # 0=顶 1=底
        half = 1.2 + 9.5 * (t ** 1.35)
        wob = 1.6 * math.sin(t * 3.4)
        left, right = C - half + wob, C + half * 0.9 + wob
        for x in range(int(left), int(right) + 1):
            d = abs((x - (left + right) / 2) / max(1.0, (right - left) / 2))
            v = (1 - d ** 1.7) * (0.35 + 0.65 * (t ** 0.55))
            px[x, y] = shades(pal, v)
    # 内焰（更亮的核心）
    for y in range(14, 27):
        t = (y - 14) / 12.0
        half = 0.8 + 4.2 * (t ** 1.3)
        for x in range(int(C - half), int(C + half) + 1):
            d = abs(x - C) / max(1.0, half)
            v = 0.72 + 0.28 * (1 - d) * (1 - t * 0.4)
            px[x, y] = shades(pal, v)
    # 零星火星
    for (x, y) in ((C - 5, 8), (C + 4, 6), (C + 1, 4)):
        px[x, y] = shades(pal, 0.85)


def make_ice(px, pal):
    # 六向雪晶：主枝 + 短副枝
    def line(x0, y0, x1, y1, v):
        steps = int(max(abs(x1 - x0), abs(y1 - y0))) or 1
        for i in range(steps + 1):
            x = round(x0 + (x1 - x0) * i / steps)
            y = round(y0 + (y1 - y0) * i / steps)
            px[x, y] = shades(pal, v)
    for k in range(6):
        a = math.radians(60 * k - 90)
        ex, ey = C + 12 * math.cos(a), C + 12 * math.sin(a)
        line(C, C, ex, ey, 0.62)
        # 副枝
        for f in (0.55, 0.78):
            bx, by = C + 12 * f * math.cos(a), C + 12 * f * math.sin(a)
            for s in (-1, 1):
                a2 = a + s * math.radians(48)
                line(bx, by, bx + 4.2 * math.cos(a2), by + 4.2 * math.sin(a2), 0.5)
    # 中心高光
    for (x, y) in ((C, C), (C - 1, C), (C, C - 1), (C + 1, C), (C, C + 1)):
        px[x, y] = shades(pal, 1.0)
    for (x, y) in ((C - 1, C - 1), (C + 1, C - 1), (C + 1, C + 1), (C - 1, C + 1)):
        px[x, y] = shades(pal, 0.78)


def make_poison(px, pal):
    # 液滴：上尖下圆
    for y in range(6, 28):
        t = (y - 6) / 21.0
        half = 1.0 + 8.5 * (t ** 0.75)
        if t > 0.86:
            half *= 0.9
        for x in range(int(C - half), int(C + half) + 1):
            d = abs(x - C) / max(1.0, half)
            if d > 1.0:
                continue
            v = (1 - d ** 1.6) * (0.42 + 0.58 * (1 - abs(t - 0.55) * 1.4))
            px[x, y] = shades(pal, max(0.0, v))
    # 高光与气泡
    for (x, y) in ((C - 3, 17), (C - 4, 18), (C - 3, 19), (C - 2, 18)):
        px[x, y] = shades(pal, 0.95)
    for (x, y) in ((C + 2, 12), (C + 3, 12), (C + 2, 11)):
        px[x, y] = shades(pal, 0.86)


def make_light(px, pal):
    # 八芒星：4 长 + 4 短
    def ray(a_deg, ln, v):
        a = math.radians(a_deg)
        for i in range(int(ln)):
            x = round(C + i * math.cos(a))
            y = round(C + i * math.sin(a))
            px[x, y] = shades(pal, v)
    for k in range(4):
        ray(45 + 90 * k, 13.5, 0.55)
    for k in range(4):
        ray(0 + 90 * k, 9.5, 0.68)
    # 核心
    for y in range(C - 3, C + 4):
        for x in range(C - 3, C + 4):
            d = math.hypot(x - C, y - C)
            if d <= 3.2:
                px[x, y] = shades(pal, 1.0 - d * 0.12)
    for (x, y) in ((C, C - 1), (C, C), (C - 1, C), (C + 1, C), (C, C + 1)):
        px[x, y] = shades(pal, 1.0)


def make_dark(px, pal):
    # 弯月：大圆减偏移圆
    R, r_off = 12.0, 5.0
    for y in range(S):
        for x in range(S):
            d1 = math.hypot(x - C, y - C)
            d2 = math.hypot(x - C - r_off, y - C - r_off * 0.35)
            if d1 <= R and d2 > R - 0.5:
                v = 0.30 + 0.55 * (1 - d1 / R)
                px[x, y] = shades(pal, v)
    # 内部虚空紫点点
    for (x, y) in ((C - 6, C - 3), (C - 5, C + 2), (C - 3, C - 5), (C - 7, C + 1)):
        px[x, y] = shades(pal, 0.9)
    # 缺口处的辉光
    for (x, y) in ((C + 4, C - 2), (C + 5, C + 1), (C + 3, C + 2)):
        px[x, y] = shades(pal, 0.72)


def make_none(px, pal):
    # 六边形符文环 + 中心点：中性/无属性
    r = 10.5
    pts = []
    for k in range(6):
        a = math.radians(60 * k - 90)
        pts.append((C + r * math.cos(a), C + r * math.sin(a)))
    def line(x0, y0, x1, y1):
        steps = int(max(abs(x1 - x0), abs(y1 - y0)))
        for i in range(steps + 1):
            x = round(x0 + (x1 - x0) * i / max(1, steps))
            y = round(y0 + (y1 - y0) * i / max(1, steps))
            px[x, y] = shades(pal, 0.60)
    for k in range(6):
        x0, y0 = pts[k]
        x1, y1 = pts[(k + 1) % 6]
        line(x0, y0, x1, y1)
    for (x, y) in ((C, C), (C - 1, C), (C + 1, C), (C, C - 1), (C, C + 1)):
        px[x, y] = shades(pal, 0.95)


BUILDERS = {
    "fire": make_fire, "ice": make_ice, "poison": make_poison,
    "light": make_light, "dark": make_dark, "none": make_none,
}


def main() -> None:
    os.makedirs(SRC, exist_ok=True)
    made = []
    for el, fn in BUILDERS.items():
        im = blank()
        fn(im.load(), PAL[el])
        im = outline_pass(im)
        im.save(f"{OUT}/icon_{el}_32.png")
        im.resize((16, 16), Image.BOX).save(f"{OUT}/icon_{el}_16.png")
        im.resize((128, 128), Image.NEAREST).save(f"{SRC}/icon_{el}_128.png")
        made.append(el)
        print("ok", el)

    # 预览：32 与 16 并排
    sheet = Image.new("RGBA", (6 * 40 + 8, 76), (29, 18, 25, 255))
    for i, el in enumerate(made):
        big = Image.open(f"{OUT}/icon_{el}_32.png")
        sml = Image.open(f"{OUT}/icon_{el}_16.png")
        sheet.alpha_composite(big, (6 + i * 40, 6))
        sheet.alpha_composite(sml, (6 + i * 40 + 8, 48))
    sheet.resize((sheet.width * 6, sheet.height * 6), Image.NEAREST).save(
        f"{SRC}/elements_preview.png")


if __name__ == "__main__":
    main()
