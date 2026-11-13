#!/usr/bin/env python3
"""转轮格子用的 32px 武器图标：96 母版 -> 32（3:1 整数 BOX 降采样）+ 元素色描边。

背景（2026-11-13）：斩击类符号（fire_slash 等）被十几把武器共用同一张通用图标，
看不出手上拿的是巨剑还是法杖，改为让格子显示「来源武器」的图标。

但直接换会掉亮度：通用火斩 meanL 108.5，而暗铁武器只有 42–72，转轮会从「在打架」
变成「在展示装备」。实测加 1px 元素色实心描边后武器轮廓被勾亮、火感回来了，
且描边颜色由武器 element 决定（冰系自然变冰蓝）。

为什么必须预生成、不能运行时缩放：
转轮格 38×38，图标层是 STRETCH_KEEP_CENTERED（不缩放）。给 96 会溢出，给 48 是
1.5:1 会糊；96 -> 32 是 3:1 整数降采样，与符号图标（96 -> 32）完全同一口径。

用法：
  py -3.15 tools/make_weapon_cell_icons.py            # 全量重建
  py -3.15 tools/make_weapon_cell_icons.py --only=forge_greatsword,fire_wand
  py -3.15 tools/make_weapon_cell_icons.py --no-outline
"""
import argparse
import os
import re

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets/icons/weapons/_source")
DST = os.path.join(ROOT, "assets/icons/weapons/cell")
TRES = os.path.join(ROOT, "resources/weapon_templates")
SIDE = 32

# 与 scripts/ui/weapon_icons.gd 的 ELEMENT_COLORS 保持一致
ELEMENT_COLORS = {
    "fire": (232, 118, 42),
    "ice": (111, 183, 201),
    "poison": (127, 163, 58),
    "light": (232, 216, 154),
    "dark": (108, 78, 134),
    "none": (142, 138, 130),
}


def read_element(weapon_id: str) -> str:
    p = os.path.join(TRES, weapon_id + ".tres")
    if not os.path.exists(p):
        return "none"
    with open(p, encoding="utf-8") as f:
        m = re.search(r'^element\s*=\s*"([a-z]+)"', f.read(), re.M)
    return m.group(1) if m else "none"


def add_outline(im: Image.Image, color, dilate: int = 1, alpha: int = 255) -> Image.Image:
    """在图标非透明区外侧描一圈元素色（1px），让暗色武器在深色格子底上跳出来。"""
    a = im.getchannel("A")
    w, h = im.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(out)
    filled = color + (alpha,)
    for y in range(h):
        for x in range(w):
            if a.getpixel((x, y)) > 100:
                continue
            hit = False
            for dy in range(-dilate, dilate + 1):
                if hit:
                    break
                for dx in range(-dilate, dilate + 1):
                    if dx == 0 and dy == 0:
                        continue
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and a.getpixel((nx, ny)) > 100:
                        hit = True
                        break
            if hit:
                d.point((x, y), fill=filled)
    out.alpha_composite(im)
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="逗号分隔的武器 id；留空 = 全量")
    ap.add_argument("--no-outline", action="store_true", help="不描元素色（纯降采样）")
    ap.add_argument("--outline-alpha", type=int, default=255, help="描边不透明度，150 更柔和")
    args = ap.parse_args()
    only = {s.strip() for s in args.only.split(",") if s.strip()}

    os.makedirs(DST, exist_ok=True)
    names = sorted(f for f in os.listdir(SRC) if f.startswith("icon_") and f.endswith("_96.png"))
    made = skipped = 0
    for fn in names:
        wid = fn[len("icon_"):-len("_96.png")]
        if only and wid not in only:
            continue
        im = Image.open(os.path.join(SRC, fn)).convert("RGBA")
        if im.size != (96, 96):
            print(f"SKIP {wid}: 母版不是 96x96（{im.size[0]}x{im.size[1]}）")
            skipped += 1
            continue
        small = im.resize((SIDE, SIDE), Image.BOX)
        if not args.no_outline:
            elem = read_element(wid)
            small = add_outline(small, ELEMENT_COLORS.get(elem, ELEMENT_COLORS["none"]),
                                dilate=1, alpha=args.outline_alpha)
        small.save(os.path.join(DST, f"icon_{wid}_{SIDE}.png"))
        made += 1
    print(f"生成 {made} 个 {SIDE}px 格子图标 -> {DST}"
          + ("（无描边）" if args.no_outline else "（含元素色描边）")
          + (f"（跳过 {skipped}）" if skipped else ""))
    if only:
        missing = only - {f[len('icon_'):-len('_96.png')] for f in names}
        if missing:
            print(f"⚠ --only 里有找不到母版的 id：{sorted(missing)}")


if __name__ == "__main__":
    main()
