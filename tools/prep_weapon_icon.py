#!/usr/bin/env python3
"""武器图标后处理 v2：AI 洋红底原图 -> 96 母版 / 48 成品（写入待确认目录）。

与旧 tools/prep_icon.py 的区别：
  1. AI 出图底色是渐变洋红 (R=255,B=255,G 约 20~43)，固定色距会失效；
     改用洋红度 min(R,B)-G > 25 一刀切，边缘混色带实测只有几百像素。
  2. 不做 26 色量化 / 对比增强。已接入的 ember_sword / fire_sword 48 成品
     实测 231 / 318 色，是纯缩放；用户已明确否掉量化清理，效果优先。
  3. 只做抠底 + 清水印 + 裁透明边 + 归一，不锚色归并、不清噪、不改描边。
  4. 输出到 --out 指定的待确认目录，不直接写正式 assets 路径；
     人工确认后再拷到 assets/icons/weapons/ 与 _source/。

用法：
  py -3.15 tools/prep_weapon_icon.py <AI原图.png> <资源id> --out .workbuddy/art_trials/weapon_first
"""
import argparse
import math
import os
import statistics

from PIL import Image, ImageChops, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ANCHORS = ["ember_sword", "fire_sword"]
BG = (29, 18, 25, 255)  # 游戏底色


def cut_magenta(im: Image.Image):
    """洋红度判据抠底：m = min(R,B) - G，背景 m>200，角色 m<=0。"""
    rgb = im.convert("RGB")
    r, g, b = rgb.split()
    m = ImageChops.subtract(ImageChops.darker(r, b), g)  # L 图，负值 clamp 到 0
    mb = m.tobytes()

    out = rgb.convert("RGBA")
    data = bytearray(out.tobytes())
    cut = 0
    for i, v in enumerate(mb):
        if v > 25:
            data[4 * i + 3] = 0
            cut += 1
    out = Image.frombytes("RGBA", rgb.size, bytes(data))

    # AI 强制水印区（1024 坐标 x>=870, y>=915），按图比例换算
    w, h = out.size
    px = out.load()
    x0, y0 = int(w * 870 / 1024), int(h * 915 / 1024)
    for y in range(y0, h):
        for x in range(x0, w):
            px[x, y] = (0, 0, 0, 0)
    return out, cut, w, h


def cut_dark_bg(im: Image.Image, tol: int = 35):
    """AI 偶尔无视洋红底要求，改成近纯色深底。逐边采样中位数 + 色距 floodfill 抠底。

    实测 (16,10,11) 底：D<=5 占 67.7%（底），D>=50 才是角色暗部，
    tol=35 只吃底和混色边，不挖主体；内部封闭近底色块一并清掉。
    """
    rgb = im.convert("RGB")
    w, h = rgb.size
    samples = []
    for x in range(0, w, max(1, w // 64)):
        samples.append(rgb.getpixel((x, 2)))
        samples.append(rgb.getpixel((x, h - 3)))
    for y in range(0, h, max(1, h // 64)):
        samples.append(rgb.getpixel((2, y)))
        samples.append(rgb.getpixel((w - 3, y)))
    bg = tuple(int(statistics.median(c[i] for c in samples)) for i in range(3))

    diff = ImageChops.difference(rgb, Image.new("RGB", rgb.size, bg))
    dr, dg, db = diff.split()
    d = ImageChops.lighter(ImageChops.lighter(dr, dg), db)
    near = d.point(lambda v: 255 if v <= tol else 0).convert("L")
    for seed in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        if near.getpixel(seed) == 255:
            ImageDraw.floodfill(near, seed, 128, thresh=0)
    nb = near.tobytes()

    out = rgb.convert("RGBA")
    data = bytearray(out.tobytes())
    cut = 0
    for i, v in enumerate(nb):
        if v in (128, 255):  # 外部背景 + 内部封闭近底色泄漏块
            data[4 * i + 3] = 0
            cut += 1
    out = Image.frombytes("RGBA", rgb.size, bytes(data))

    px = out.load()
    x0, y0 = int(w * 870 / 1024), int(h * 915 / 1024)
    for y in range(y0, h):
        for x in range(x0, w):
            px[x, y] = (0, 0, 0, 0)
    return out, cut, w, h, bg


def mean_lum(im: Image.Image) -> float:
    vals = [0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]
            for c in im.getdata() if c[3] > 128]
    return sum(vals) / len(vals) if vals else 0.0


def make_preview(i96: Image.Image, i48: Image.Image, wid: str, out_path: str):
    cells = [(f"{wid} 96 master", i96.resize((384, 384), Image.NEAREST)),
             (f"{wid} 48 game", i48.resize((384, 384), Image.NEAREST))]
    for name in ANCHORS:
        p = os.path.join(ROOT, "assets/icons/weapons", f"icon_{name}.png")
        if os.path.exists(p):
            cells.append((f"{name} 48 (anchor)",
                          Image.open(p).convert("RGBA").resize((384, 384), Image.NEAREST)))
    gap = 24
    cv = Image.new("RGBA", (gap + len(cells) * (384 + gap), 384 + 2 * gap + 18), BG)
    d = ImageDraw.Draw(cv)
    for i, (label, pic) in enumerate(cells):
        x = gap + i * (384 + gap)
        d.text((x, gap), label, fill=(220, 210, 195, 255))
        cv.alpha_composite(pic, (x, gap + 18))
    cv.convert("RGB").save(out_path)


def principal_axis(im: Image.Image) -> float:
    """返回图标非透明区域的 PCA 主轴角度（度）。-45 左右 = 标准斜置；-90 = 垂直。

    2026-11-13 加：AI 对长杆类（法杖）默认竖放，ember_staff v3 出成 -89.8°、
    pyre_staff v5 出成 -89.7°，与全套 -45° 斜置不一致。落盘前用这个量化校验，
    超出 45±15° 视为不合格。
    """
    a = im.getchannel("A")
    w, h = im.size
    pts = [(x, y) for y in range(h) for x in range(w) if a.getpixel((x, y)) > 60]
    n = len(pts)
    if n < 8:
        return 0.0
    mx = sum(p[0] for p in pts) / n
    my = sum(p[1] for p in pts) / n
    sxx = sum((p[0] - mx) ** 2 for p in pts) / n
    syy = sum((p[1] - my) ** 2 for p in pts) / n
    sxy = sum((p[0] - mx) * (p[1] - my) for p in pts) / n
    return math.degrees(0.5 * math.atan2(2 * sxy, sxx - syy))


def de_green(im: Image.Image, keep: int = 0):
    """把偏绿的暗铁色调压回中性/暖调。

    2026-11-13：AI 反复把 "dark charcoal iron / soot-black steel" 出成暗橄榄绿
    （实测 5 张火系重出图主体 G 通道普遍高于 R），与已接入的暗铁体系不协调。

    2026-11-16 重写判据。原实现是「G > R 就把 G 压到 R+4」，有两个缺陷：
      ① 冰蓝 (111,183,201) 同样 G > R，会被压成紫灰，毁掉冰系配色；
      ② 只压到 R+4，对 B 很低的黄绿（如 (52,56,44)）压完仍是黄绿。
    新判据 = 绿通道同时高于红和蓝才算黄绿/橄榄，把 G 压到 max(R, B) + keep：
      · 冰蓝（B 最高）与火橙/旧金（R 最高）天然不受影响，无需特判；
      · 暗铁 (52,56,44) -> (52,52,44)，真正回到中性。
    keep 是允许的余量，默认 0（最中性）；想保留一丝暖调可给 2–4。
    """
    out = im.copy()
    dst = out.load()
    n = 0
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = im.getpixel((x, y))
            if a == 0:
                continue
            if g <= max(r, b) + keep:
                continue
            # 绿色主导：直接灰度化。只压 G 不够 —— (90,95,60) 这类像素压到 cap 后
            # 仍是黄绿（因为 B 太低），必须把三通道统一到亮度才真正回到中性铁。
            lum = (r * 299 + g * 587 + b * 114) // 1000
            dst[x, y] = (lum, lum, lum, a)
            n += 1
    return out, n


def drop_islands(im: Image.Image, min_px: int = 16):
    """删除小于 min_px 的孤立连通块（原图残留在裁边后剩下的碎片）。

    2026-11-16：`ice_gun` 出图后右上角残留一块 13 像素的碎块，缩到 48px 后仍可见，
    在转轮格子里特别扎眼。这里按 8-邻接做连通域分析，只保留面积 >= min_px 的块。
    96px 尺度上 16 像素 ≈ 4×4，正常武器部件都远大于此，不会误删。
    """
    from collections import deque

    w, h = im.size
    alpha = im.getchannel("A")
    seen = [[False] * w for _ in range(h)]
    keep = Image.new("L", (w, h), 0)
    kp = keep.load()
    removed = 0
    for y in range(h):
        for x in range(w):
            if seen[y][x] or alpha.getpixel((x, y)) <= 8:
                continue
            q = deque([(x, y)])
            seen[y][x] = True
            pts = []
            while q:
                cx, cy = q.popleft()
                pts.append((cx, cy))
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        if dx == 0 and dy == 0:
                            continue
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] \
                                and alpha.getpixel((nx, ny)) > 8:
                            seen[ny][nx] = True
                            q.append((nx, ny))
            if len(pts) >= min_px:
                for px_, py_ in pts:
                    kp[px_, py_] = 255
            else:
                removed += len(pts)
    out = im.copy()
    out.putalpha(Image.composite(im.getchannel("A"), Image.new("L", (w, h), 0), keep))
    return out, removed


def mean_l(im: Image.Image) -> float:
    px = [(r, g, b) for r, g, b, a in im.getdata() if a > 200]
    if not px:
        return 0.0
    return sum((r * 299 + g * 587 + b * 114) // 1000 for r, g, b in px) / len(px)


def auto_level(im: Image.Image, target: float, tol: float = 1.5):
    """自动调 gamma 把平均亮度拉到 target 附近。

    2026-11-16：同一批物品图标实测 meanL 跨度 33.8–134.8（玻璃瓶暗、羊皮纸亮），
    手工试 gamma 太慢。mean_l 随 gamma 单调递增，直接二分即可。
    """
    cur = mean_l(im)
    if cur <= 0 or abs(cur - target) <= tol:
        return im, 1.0
    lo, hi = 0.35, 3.0
    best, best_gap, best_g = im, abs(cur - target), 1.0
    for _ in range(16):
        g = (lo + hi) * 0.5
        t = apply_gamma(im, g)
        diff = mean_l(t) - target
        if abs(diff) < best_gap:
            best, best_gap, best_g = t, abs(diff), g
        if diff < 0:
            lo = g
        else:
            hi = g
    return best, best_g


def boost_warm(im: Image.Image, percent: int = 150, squash: float = 0.0):
    """把暖色（R 主导）像素按同一比例提亮 —— 只提亮度，不改色相。

    2026-11-16：用户反馈「红色和代表熔岩的色彩偏暗」。实测 heal_potion 的"红液体"
    平均只有 (109,67,31)、亮度 75 —— 是暗棕橙，不是红色；火系武器图标的橙是
    (232,118,42)。原因是全图 meanL 归一为照顾大面积暗玻璃，把仅占 16% 的暖色也压平了。

    第一版把 R 直接顶到固定值、G/B 增幅递减，结果红色被推成橙色而且丢层次
    （v3 的药剂变成橙水）。改成**等比提亮**：R/G/B 乘同一系数，色相与层次
    都不变，只是变亮。percent 是百分比，150 = ×1.5。

    squash > 0 时先压 G/B 到 R 的比例（强制橙红），再提亮 —— 用于 AI 把"熔岩"
    画成暗黄的情况：lava_burst 实测暖色 (113,95,32)，G/R=0.84 整体发黄，
    等比提亮只会更黄。squash=0.55 → (113,62,34)。
    """
    k = percent / 100.0
    out = im.copy()
    dst = out.load()
    n = 0
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = im.getpixel((x, y))
            if a == 0 or r < 45:
                continue
            if squash > 0.0:
                # 强制橙红模式：只要求 R 明显高于 B，**不要求 R 高于 G** ——
                # 要救的正是 "亮黄" (255,230,60) 这种 R≈G 的熔岩，
                # 用默认的 r > g*1.15 会把它整个跳过（实测第一版就是这么失效的）。
                if not (r > b * 1.25 and r > 60):
                    continue
            else:
                if not (r > g * 1.15 and r > b * 1.25):
                    continue
            nr, ng, nb = r, g, b
            # 先等比提亮，再压 G/B —— 顺序不能反：先压后乘会把压下去的 G 又乘回来
            # （实测第一版 lava 的裂缝 (255,215,0) 压到 132 后 ×1.7 又回到 224，仍是黄）
            nr = min(255, round(nr * k))
            ng = min(255, round(ng * k))
            nb = min(255, round(nb * k))
            if squash > 0.0:
                ng = min(ng, round(nr * squash))
                nb = min(nb, round(nr * squash * 0.55))
            dst[x, y] = (nr, ng, nb, a)
            n += 1
    return out, n


def apply_gamma(im: Image.Image, g: float):
    """整体提亮 / 压暗（g > 1 提亮，g < 1 压暗，1.0 = 不处理），alpha 全保留。

    2026-11-16：AI 对同一提示词给出的明暗差异很大 —— 战斧两版分别是 meanL 35.6 与 97.1，
    差将近 3 倍，靠重出收敛不了。与其反复出图，不如把亮度过高/过低的那版用 gamma 拉回
    目标区间（武器图标锚点 42–88）。
    """
    if abs(g - 1.0) < 1e-4:
        return im
    out = im.copy()
    dst = out.load()
    tab = [min(255, round(((i / 255.0) ** (1.0 / g)) * 255)) for i in range(256)]
    for y in range(im.height):
        for x in range(im.width):
            r, gg, b, a = im.getpixel((x, y))
            if a == 0:
                continue
            dst[x, y] = (tab[r], tab[gg], tab[b], a)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("raw")
    ap.add_argument("wid")
    ap.add_argument("--out", required=True)
    ap.add_argument("--bg", choices=["magenta", "dark"], default="magenta",
                     help="magenta=洋红度判据；dark=AI 乱给近纯色深底时用色距法")
    ap.add_argument("--tol", type=int, default=35, help="dark 模式色距阈值")
    ap.add_argument("--degreen", action="store_true",
                     help="把偏绿的暗铁色调压回中性（AI 把 charcoal iron 出成橄榄绿时用）")
    ap.add_argument("--degreen-keep", type=int, default=0,
                     help="degreen 后允许 G 超出 R 的余量")
    ap.add_argument("--gamma", type=float, default=1.0,
                     help=">1 提亮 / <1 压暗（武器锚点 meanL 42–88），1 = 不处理")
    ap.add_argument("--target-l", type=float, default=0.0,
                     help="自动把平均亮度拉到该值（0 = 关闭）；优先于 --gamma")
    ap.add_argument("--warm-boost", type=int, default=0,
                     help="暖色(R主导)等比提亮百分比（0 = 关闭）；150 = ×1.5，红/熔岩类物品用 145–170")
    ap.add_argument("--warm-squash", type=float, default=0.0,
                     help="先把暖色 G 通道压到 R×该比例（强制橙红，救 AI 画成暗黄的熔岩）；0.55 常用")
    ap.add_argument("--drop-islands", type=int, default=60,
                     help="删除小于该像素数的孤立碎块（0 = 关闭）；裁边后残留的原图碎片")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    raw = Image.open(args.raw)
    if args.bg == "dark":
        im, cut, w, h, bg = cut_dark_bg(raw, args.tol)
        print(f"dark bg sampled={bg} tol={args.tol}")
    else:
        im, cut, w, h = cut_magenta(raw)
    bb = im.getbbox()
    if bb is None:
        raise SystemExit("全部透明：洋红度阈值可能不对")
    content = im.crop(bb)
    if args.degreen:
        content, dg = de_green(content, args.degreen_keep)
        print(f"de-green: {dg} px 压回中性")
    if args.target_l > 0.0:
        content, g_used = auto_level(content, args.target_l)
        print(f"auto-level: target {args.target_l} -> gamma {g_used:.2f}, meanL {mean_l(content):.1f}")
    elif abs(args.gamma - 1.0) > 1e-4:
        content = apply_gamma(content, args.gamma)
        print(f"gamma: {args.gamma}")
    if args.warm_boost > 0:
        content, wb = boost_warm(content, args.warm_boost, args.warm_squash)
        print(f"warm-boost: {wb} px 暖色提到 R={args.warm_boost}")
    cw, ch = content.size
    side = max(cw, ch)
    pad = int(side * 0.06)
    canvas = Image.new("RGBA", (side + 2 * pad, side + 2 * pad), (0, 0, 0, 0))
    canvas.alpha_composite(content, ((canvas.width - cw) // 2, (canvas.height - ch) // 2))

    i96 = canvas.resize((96, 96), Image.LANCZOS)
    # 碎块清理放在 96 尺度：阈值语义才和最终图标同量级（96px 上 60 ≈ 8×8）。
    # 在原始 1024 尺度上判断会因为同一块被放大十几倍而从不触发 —— ice_gun 实测碎片
    # 在 48px 是 13px、96px 是 35px、原图是上千 px，阈值只有放在 96 才准。
    if args.drop_islands > 0:
        i96, dropped = drop_islands(i96, args.drop_islands)
        if dropped:
            print(f"drop-islands: 删除 {dropped} px 碎片")
    i48 = i96.resize((48, 48), Image.BOX)
    p96 = os.path.join(args.out, f"icon_{args.wid}_96.png")
    p48 = os.path.join(args.out, f"icon_{args.wid}.png")
    i96.save(p96)
    i48.save(p48)
    prev = os.path.join(args.out, f"preview_{args.wid}.png")
    make_preview(i96, i48, args.wid, prev)

    print(f"raw={w}x{h} cut_px={cut} bbox={bb} content={cw}x{ch}")
    print(f"96: colors={len(i96.getcolors(100000) or [])} meanL={mean_lum(i96):.1f} -> {p96}")
    print(f"48: colors={len(i48.getcolors(100000) or [])} meanL={mean_lum(i48):.1f} -> {p48}")
    axis = principal_axis(i48)
    warn = "" if -60.0 <= axis <= -30.0 else "   <-- 角度不合格（应 45°±15），AI 很可能画成了竖直"
    print(f"axis={axis:+.1f} deg (target -45){warn}")
    print(f"preview -> {prev}")


if __name__ == "__main__":
    main()
