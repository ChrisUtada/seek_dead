#!/usr/bin/env python3
"""转轮符号图标的统一派生管线（96 母版 -> 32 / 16 两档）。

背景：早期符号是一批各自为政的 AI 平涂图（无统一暗部 / 高光 / 轮廓），
6 把斩击剑后来做过一次「刀面整片换色」，两者摆在转轮里风格不一致。
本脚本把所有符号收拢到同一条管线：一张色表、同一套明暗三层结构、
与 tools/split_symbols.py 完全一致的 BOX 降采样 + 量化 + 对比增强。

分区（逐点判定，alpha 全程不变）：
  mode="blade"（剑族，已验收的分区规则）
      alpha <= 128  -> 不动
      L < 60        -> 深色轮廓，不动
      S >= 45       -> 原有彩色描边，不动
      其余灰阶刀面  -> 按亮度插值 elem_dark -> elem_light
                       （fire_slash 例外：改走 FIRE_RAMPS 火色带）
  mode="solid"（早期平涂符号，没有彩边概念）
      alpha <= 128  -> 不动
      L < 60        -> 统一压到该元素的深轮廓色
      其余全部主体  -> 按亮度插值 elem_dark -> elem_light（不论原本饱和度）
  L > 195 的高光额外向白提亮，保留金属 / 晶体亮点。

用法（本机只有 C:/Python315/python.exe 装了 Pillow；py launcher 会读 shebang
选到没有 PIL 的 3.14/3.12，故须显式指定解释器）：
  py -3.15 tools/recolor_symbols.py --preview   # 样图写到 .workbuddy/art_trials/symbols_unified/
  py -3.15 tools/recolor_symbols.py             # 正式写入 assets/icons/symbols/ 与 16/
  py -3.15 tools/recolor_symbols.py --check     # 只校验 blade 组与已落盘资源逐像素一致
  py -3.15 tools/recolor_symbols.py --ramp=b    # 火系色带切到 b 档（默认 a）
"""
import os
import sys

from PIL import Image, ImageEnhance, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets/icons/symbols/_source")
DST = os.path.join(ROOT, "assets/icons/symbols")
PREVIEW = os.path.join(ROOT, ".workbuddy/art_trials/symbols_unified")

# 元素主色。刻意拉开易撞的两对：火/光靠明度，冰/毒靠色相；
# 暗紫提亮到 #9C68D0，避免在游戏底色 (29,18,25) 上隐形。
ELEM = {
    "fire":   (232, 84, 28),    # #E8541C 深橙红
    "ice":    (86, 170, 224),   # #56AAE0 亮蓝
    "poison": (140, 210, 60),   # #8CD23C 酸绿
    "light":  (248, 232, 168),  # #F8E8A8 浅金白
    "dark":   (156, 104, 208),  # #9C68D0 亮紫
    "none":   (168, 172, 178),  # #A8ACB2 中性冷灰
}

# 火焰专用亮度色带（2026-11-13 用户反馈「橘色不像火」后重做）：
# 真火是「深红棕轮廓 -> 红 -> 橙 -> 亮黄芯 -> 白热」的多层色，
# 用单一主色做明暗插值只会得到一片橘色（看起来像橘子而不像火）。
# 作用对象：solid 的 burn / flame_special，以及 blade 的 fire_slash 刀面。
# blade 模式原有的「L<60 深轮廓 + S>=45 彩边不动」保护依然生效，
# 只有灰阶刀面改走色带，所以剑的深色描边与金属高光不会丢。
FIRE_RAMPS = {
    "a": [(0, (66, 16, 12)), (60, (132, 32, 14)), (110, (214, 62, 18)),
          (160, (246, 132, 30)), (205, (255, 198, 64)), (255, (255, 242, 168))],
    "b": [(0, (58, 12, 16)), (60, (116, 22, 20)), (110, (192, 42, 22)),
          (160, (230, 86, 26)), (205, (248, 146, 46)), (255, (255, 214, 116))],
}
FIRE_RAMP_JOBS = {"burn", "flame_special", "fire_slash"}

# name -> (主色覆盖 or 元素键, mode)。覆盖用于保持物件固有色（骨白獠牙等）。
JOBS = {
    # --- 斩击剑族：沿用已验收的 blade 规则，重跑结果须与落盘资源逐像素一致 ---
    "fire_slash":   ("fire", "blade"),
    "frost_slash":  ("ice", "blade"),
    "poison_slash": ("poison", "blade"),
    "holy_slash":   ("light", "blade"),
    "shadow_slash": ("dark", "blade"),
    "iron_slash":   ("none", "blade"),
    # --- 早期平涂符号：统一到三层明暗结构 ---
    # 这几个物件本身造型就带元素语义（火焰 / 日出 / 光箭），直接套 #E8541C / #F8E8A8
    # 会被暗面压成土棕或洗成米白，故按物件单独给主色，仍走同一套管线与规则。
    # burn 例外：2026-11-13 已换成「火把」灰阶母版并改走 FIRE_RAMPS，spec 不生效。
    "burn":         ((255, 112, 42), "solid"),    # 占位，实际由火色带决定
    "dawn_light":   ((242, 198, 104), "solid"),   # 饱和金，避免与光箭一起洗白
    "frost":        ("ice", "solid"),
    "holy_bolt":    ((242, 198, 104), "solid"),
    "ice_crystal":  ("ice", "solid"),
    "poison":       ("poison", "solid"),
    "venom_bite":   ((196, 214, 150), "solid"),   # 骨白偏毒绿，避免獠牙整颗变酸绿
    # --- 高频符号 14 张 + 两个旧图标重制：AI 只出中性灰阶母版，颜色在此统一注入 ---
    # 投射物族
    "arrow_shot":               ("none", "solid"),
    "bolt_shot":                ("none", "solid"),
    "pistol_shot":              ((240, 200, 72), "solid"),
    "plague_bolt":              ("poison", "solid"),
    "ice_shot":                 ("ice", "solid"),
    "dawn_bolt":                ((242, 198, 104), "solid"),
    # 锁链鞭 / 短刃 / 单体
    "shadow_chain":             ("dark", "solid"),
    "viper_lash":               ("poison", "solid"),
    "dagger_slash":             ((206, 204, 178), "solid"),
    "shadow_guillotine_slash":  ("dark", "solid"),
    "corrosive_spray":          ("poison", "solid"),
    "abyss_bite":               ("dark", "solid"),
    "holy_mace_smash":          ((242, 198, 104), "solid"),
    "flame_special":            ((255, 112, 42), "solid"),
    # 旧 16px 图标迁入 symbols 体系（axe_slash / gold）
    "axe_slash":                ((200, 140, 90), "solid"),
    "gold":                     ((248, 200, 72), "solid"),
}

# 少数 AI 母版造型失败时的复用映射（沿用「复用直刃 / 复用獠牙」的口径）。
# 值 = (源母版文件名, 水平放大系数)；放大后居中裁回 96，用于把普通剑撑成重斩大刃。
# 源母版都是抠底后的原始灰阶图，未经换色，可直接进 solid 管线。
SOURCE_OVERRIDE = {
    "shadow_guillotine_slash": ("iron_slash_96.png", 1.20),
    "abyss_bite":              ("venom_bite_96.png", 1.0),
}

DARK_K = 0.40        # 暗面 = 主色 × 该系数
LIGHT_WHITE = 0.40   # 亮面 = 主色向白混合比例
HILITE_WHITE = 0.20  # L>195 额外向白混合上限
CONTOUR_L = 60       # 低于此亮度视为深色轮廓
SAT_EDGE = 45        # blade 模式：高于此饱和视为彩边
CONTOUR_K = 0.22     # solid 模式：深轮廓色 = 主色 × 该系数


def lum(c):
    return (c[0] * 299 + c[1] * 587 + c[2] * 114) // 1000


def main_color(spec):
    return ELEM[spec] if isinstance(spec, str) else spec


def ramp_color(ramp, l: int):
    """按亮度在色带锚点间线性插值；l 超出范围时取端点。"""
    if l <= ramp[0][0]:
        return ramp[0][1]
    for i in range(len(ramp) - 1):
        l0, c0 = ramp[i]
        l1, c1 = ramp[i + 1]
        if l <= l1:
            t = (l - l0) / (l1 - l0)
            return tuple(round(c0[j] + (c1[j] - c0[j]) * t) for j in range(3))
    return ramp[-1][1]


# 2026-11-13：burn 旧母版是两色平涂（无描边 / 无灰阶），曾尝试程序归一补描边，
# 用户判定「风格差异太大」—— 根因是造型本身是抽象圆团，不是层次问题。
# 现已整体换成 AI 重出的「火把」灰阶母版（100% 灰阶 / 999px 深色描边），
# 不再需要任何母版预处理；所有符号一律从灰阶母版直接进色带。
# 结论：风格不一致先换造型，别在旧母版上做归一/补描边这类后处理。


def recolor(master: Image.Image, main, mode: str, ramp=None):
    out = master.copy().convert("RGBA")
    src, dst = master.load(), out.load()
    dark = tuple(int(v * DARK_K) for v in main)
    light = tuple(int(v + (255 - v) * LIGHT_WHITE) for v in main)
    contour = tuple(int(v * CONTOUR_K) for v in main)
    changed = 0
    for y in range(master.height):
        for x in range(master.width):
            r, g, b, a = src[x, y]
            if a <= 128:
                continue
            s = max(r, g, b) - min(r, g, b)
            l = lum((r, g, b))
            if mode == "blade":
                if l < CONTOUR_L or s >= SAT_EDGE:
                    continue
            elif l < CONTOUR_L:
                c = ramp_color(ramp, 0) if ramp else contour
                dst[x, y] = (c[0], c[1], c[2], a)
                changed += 1
                continue
            if ramp:
                c = ramp_color(ramp, l)
                dst[x, y] = (c[0], c[1], c[2], a)
                changed += 1
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


def verify(before: Image.Image, after: Image.Image, name: str, mode: str) -> None:
    """alpha 必须逐点一致；blade 模式的轮廓 / 彩边像素必须零改动。"""
    b, a = before.load(), after.load()
    bad_rgb = bad_alpha = 0
    for y in range(before.height):
        for x in range(before.width):
            rb, ra = b[x, y], a[x, y]
            if rb[3] != ra[3]:
                bad_alpha += 1
            protected = rb[3] <= 128 or lum(rb) < CONTOUR_L
            if mode == "blade":
                protected = protected or (max(rb[:3]) - min(rb[:3])) >= SAT_EDGE
            if protected and rb[:3] != ra[:3]:
                bad_rgb += 1
    # solid 模式会把 L<60 的轮廓统一染色，那是有意为之，只校验 alpha
    if mode == "blade":
        assert bad_rgb == 0, f"{name}: 越界改动 rgb={bad_rgb}"
    assert bad_alpha == 0, f"{name}: alpha 差异={bad_alpha}"
    print(f"  verify ok (alpha 差异 0{' / 轮廓+彩边改动 0' if mode == 'blade' else ''})")


def load_master(name: str) -> Image.Image:
    src_name, sx = SOURCE_OVERRIDE.get(name, (f"{name}_96.png", 1.0))
    im = Image.open(os.path.join(SRC, src_name)).convert("RGBA")
    if sx != 1.0:
        w = int(im.width * sx)
        scaled = im.resize((w, im.height), Image.LANCZOS)
        left = (w - im.width) // 2
        im = scaled.crop((left, 0, left + im.width, im.height))
    return im


def build(name: str, spec, mode: str, ramp=None):
    master = load_master(name)
    recolored, n = recolor(master, main_color(spec), mode, ramp)
    verify(master, recolored, name, mode)
    result = {}
    for side, colors, contrast in ((32, 22, 1.12), (16, 14, 1.18)):
        result[side] = derive(recolored, side, colors, contrast)
    print(f"{name:24s} {mode:5s} 重着色 {n:4d} px")
    return result


def make_preview(all_new: dict) -> None:
    """全库总览（4x 放大）+ 20px 小屏模拟，用于一次性验收整套符号的色彩与辨识度。"""
    names = list(JOBS)
    pad, cols = 14, 7
    S = 3
    cell = 32 * S + 14
    rowh = 32 * S + 26
    rows = (len(names) + cols - 1) // cols
    out = Image.new("RGBA", (pad + cols * cell, pad + rows * rowh), (29, 18, 25, 255))
    d = ImageDraw.Draw(out)
    for i, n in enumerate(names):
        x = pad + (i % cols) * cell
        y = pad + (i // cols) * rowh
        d.text((x, y), n, fill=(225, 220, 210, 255))
        out.alpha_composite(all_new[n][32].resize((32 * S, 32 * S), Image.NEAREST), (x, y + 14))
    out.convert("RGB").save(os.path.join(PREVIEW, "all_symbols.png"))

    s2 = 3
    small = Image.new("RGBA", (pad + cols * cell, pad + rows * (20 * s2 + 22)), (29, 18, 25, 255))
    ds = ImageDraw.Draw(small)
    for i, n in enumerate(names):
        x = pad + (i % cols) * cell
        y = pad + (i // cols) * (20 * s2 + 22)
        ds.text((x, y), n, fill=(225, 220, 210, 255))
        s = all_new[n][32].resize((20, 20), Image.BOX)
        small.alpha_composite(s.resize((20 * s2, 20 * s2), Image.NEAREST), (x, y + 12))
    small.convert("RGB").save(os.path.join(PREVIEW, "small_screen.png"))
    print(f"样图：{PREVIEW}/all_symbols.png 与 small_screen.png（未改动正式资源）")


def do_check(all_new: dict) -> None:
    """blade 组重跑结果必须与当前落盘资源逐像素一致（确定性回归保护）。
    注意：fire_slash 已在 2026-11-13 按用户反馈改走火色带，基准即新落盘资源。"""
    bad = 0
    for name, (spec, mode) in JOBS.items():
        if mode != "blade":
            continue
        for side, sub in ((32, ""), (16, "16/")):
            cur = Image.open(os.path.join(DST, sub + f"{name}.png")).convert("RGBA")
            new = all_new[name][side]
            diff = sum(1 for a, b in zip(cur.get_flattened_data(), new.get_flattened_data()) if a != b)
            if diff:
                print(f"  MISMATCH {name} {side}px: {diff} px")
                bad += diff
    print("CHECK:", "blade 组逐像素一致 ✅" if bad == 0 else f"❌ 共 {bad} 处差异")


def main() -> None:
    preview = "--preview" in sys.argv
    check = "--check" in sys.argv
    ramp_key = "a"
    for arg in sys.argv:
        if arg.startswith("--ramp="):
            ramp_key = arg.split("=", 1)[1]
    assert ramp_key in FIRE_RAMPS, f"未知火系色带档位 {ramp_key}，可用：{list(FIRE_RAMPS)}"
    os.makedirs(PREVIEW if preview else os.path.join(DST, "16"), exist_ok=True)
    all_new = {}
    for n, (spec, mode) in JOBS.items():
        r = FIRE_RAMPS[ramp_key] if n in FIRE_RAMP_JOBS else None
        all_new[n] = build(n, spec, mode, r)
    if check:
        do_check(all_new)
        return
    if preview:
        make_preview(all_new)
        return
    for name, imgs in all_new.items():
        imgs[32].save(os.path.join(DST, f"{name}.png"))
        imgs[16].save(os.path.join(DST, "16", f"{name}.png"))
    print(f"已写入 {DST}/ 与 16/，共 {len(all_new)} 个符号 × 2 档")


if __name__ == "__main__":
    main()
