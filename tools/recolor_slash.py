#!/usr/bin/env python3
"""斩击符号「刀面整片换色」（元素区分方案 A）。

从 96px RGBA 母版派生，不重复抠图、不在已量化的 32px 图上二次加工。

分区（按像素逐点判定，alpha 全程不变）：
  alpha <= 128      透明 / 半透明边缘 -> 不动
  L < 60            深色轮廓            -> 不动
  S >= 45           原有彩色描边        -> 不动
  其余（灰阶刀面）  -> 按亮度插值 elem_dark -> elem_light
  L > 195 的高光    -> 额外向白提亮，保留金属亮点

用法（本机只有 C:/Python315/python.exe 装了 Pillow；py launcher 会读 shebang
选到没有 PIL 的 3.14/3.12，故须显式指定解释器）：
  py -3.15 tools/recolor_slash.py --preview   # 样图写到 .workbuddy/art_trials/slash_v2/
  py -3.15 tools/recolor_slash.py             # 正式写入 assets/icons/symbols/ 与 16/
"""
import os
import sys

from PIL import Image, ImageEnhance

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets/icons/symbols/_source")
DST = os.path.join(ROOT, "assets/icons/symbols")
PREVIEW = os.path.join(ROOT, ".workbuddy/art_trials/slash_v2")

# 主色刻意拉开：火(深橙红) vs 光(浅金白) 靠明度分，冰(亮蓝) vs 毒(酸绿) 靠色相分；
# 暗紫提亮到 #9C68D0，避免在游戏底色 (29,18,25) 上隐形。
ELEM = {
    "fire_slash":   (232, 84, 28),    # #E8541C 深橙红
    "frost_slash":  (86, 170, 224),   # #56AAE0 亮蓝
    "poison_slash": (140, 210, 60),   # #8CD23C 酸绿
    "holy_slash":   (248, 232, 168),  # #F8E8A8 浅金白
    "shadow_slash": (156, 104, 208),  # #9C68D0 亮紫
    "iron_slash":   (168, 172, 178),  # #A8ACB2 中性冷灰
}
DARK_K = 0.40        # 暗面 = 主色 × 该系数
LIGHT_WHITE = 0.40   # 亮面 = 主色向白混合比例
HILITE_WHITE = 0.20  # L>195 额外向白混合上限
CONTOUR_L = 60       # 低于此亮度视为深色轮廓
SAT_EDGE = 45        # 高于此饱和视为彩边


def lum(c):
    return (c[0] * 299 + c[1] * 587 + c[2] * 114) // 1000


def recolor(master: Image.Image, main) -> Image.Image:
    out = master.copy().convert("RGBA")
    src, dst = master.load(), out.load()
    dark = tuple(int(v * DARK_K) for v in main)
    light = tuple(int(v + (255 - v) * LIGHT_WHITE) for v in main)
    changed = 0
    for y in range(master.height):
        for x in range(master.width):
            r, g, b, a = src[x, y]
            if a <= 128:
                continue
            s = max(r, g, b) - min(r, g, b)
            l = lum((r, g, b))
            if l < CONTOUR_L or s >= SAT_EDGE:
                continue
            t = min(max((l - CONTOUR_L) / 150.0, 0.0), 1.0)
            c = [dark[i] + (light[i] - dark[i]) * t for i in range(3)]
            if l > 195:
                k = min((l - 195) / 25.0, 1.0) * HILITE_WHITE
                c = [c[i] + (255 - c[i]) * k for i in range(3)]
            dst[x, y] = (round(c[0]), round(c[1]), round(c[2]), a)
            changed += 1
    return out, changed


def derive(im96: Image.Image, side: int, colors: int, contrast: float) -> Image.Image:
    """与 tools/split_symbols.py 完全一致的降采样管线。"""
    a = im96.resize((side, side), Image.BOX)
    rgb = a.convert("RGB").quantize(colors=colors, method=Image.MEDIANCUT,
                                    dither=Image.NONE).convert("RGB")
    rgb = ImageEnhance.Contrast(rgb).enhance(contrast)
    o = rgb.convert("RGBA")
    o.putalpha(a.split()[3])
    return o


def verify(before: Image.Image, after: Image.Image, name: str) -> None:
    """非目标像素改动必须为 0，alpha 必须逐点一致。"""
    b, a = before.load(), after.load()
    bad_rgb = bad_alpha = 0
    for y in range(before.height):
        for x in range(before.width):
            rb, ra = b[x, y], a[x, y]
            if rb[3] != ra[3]:
                bad_alpha += 1
            if rb[3] <= 128 or lum(rb) < CONTOUR_L or (max(rb[:3]) - min(rb[:3])) >= SAT_EDGE:
                if rb[:3] != ra[:3]:
                    bad_rgb += 1
    assert bad_rgb == 0 and bad_alpha == 0, f"{name}: 越界改动 rgb={bad_rgb} alpha={bad_alpha}"
    print(f"  verify ok (非目标像素改动 0 / alpha 差异 0)")


def make_compare(new32: dict) -> None:
    """上排 32px 原版 1:1，中排新版 1:1，下排新版 4x；右侧附 20px 小屏模拟。"""
    names = list(ELEM)
    S, cell, pad = 4, 32 * 4 + 16, 16
    W = cell * 6 + pad
    H = pad + 32 + 8 + 32 + 8 + 32 * S + pad
    out = Image.new("RGBA", (W, H), (29, 18, 25, 255))
    for i, n in enumerate(names):
        x = pad + i * cell
        old = Image.open(os.path.join(DST, f"{n}.png")).convert("RGBA")
        out.alpha_composite(old, (x, pad))
        out.alpha_composite(new32[n], (x, pad + 32 + 8))
        out.alpha_composite(new32[n].resize((32 * S, 32 * S), Image.NEAREST),
                            (x, pad + 32 + 8 + 32 + 8))
    out.convert("RGB").save(os.path.join(PREVIEW, "compare.png"))

    # 小屏模拟：32px 缩到 20px 再用 NEAREST 放大 4x（掌机窗口缩小时的观感）
    small = Image.new("RGBA", (cell * 6 + pad, pad + 20 * S + pad), (29, 18, 25, 255))
    for i, n in enumerate(names):
        x = pad + i * cell
        s = new32[n].resize((20, 20), Image.BOX)
        small.alpha_composite(s.resize((20 * S, 20 * S), Image.NEAREST), (x, pad))
    small.convert("RGB").save(os.path.join(PREVIEW, "small_screen.png"))


def main() -> None:
    preview = "--preview" in sys.argv
    outdir = PREVIEW if preview else DST
    os.makedirs(outdir, exist_ok=True)
    if not preview:
        os.makedirs(os.path.join(outdir, "16"), exist_ok=True)
    new32 = {}
    for name, main_color in ELEM.items():
        master = Image.open(os.path.join(SRC, f"{name}_96.png")).convert("RGBA")
        recolored, n = recolor(master, main_color)
        verify(master, recolored, name)
        print(f"{name:15s} 刀面重着色 {n:4d} px  main={main_color}")
        for side, colors, contrast, sub in ((32, 22, 1.12, ""), (16, 14, 1.18, "16/")):
            target = os.path.join(outdir, sub + f"{name}.png")
            if preview and side == 16:
                continue
            img = derive(recolored, side, colors, contrast)
            if preview and side == 32:
                target = os.path.join(outdir, f"{name}_v2.png")
            img.save(target)
            if side == 32:
                new32[name] = img
    if preview:
        make_compare(new32)
        print(f"样图：{PREVIEW}/compare.png 与 small_screen.png（未改动正式资源）")
    else:
        print(f"已写入 {DST}/ 与 16/")


if __name__ == "__main__":
    main()
