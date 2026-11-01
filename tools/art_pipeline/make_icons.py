#!/usr/bin/env python3
"""战斗 UI 纠偏 · 样板图标（2026-10-31，按《纠偏执行任务书》附录 A）

规则（脚本内自动校验）：
    16×16 RGBA，主体限制在 x=2…13 / y=1…14，四周至少 1px 透明安全区；
    每枚图标最多 3 个实体颜色 + 透明色；不允许半透明过渡像素；
    24×24 = 16×16 主体原尺寸居中（不是拉伸），不预先烘焙外框/角标。

输出：
    assets/icons/16/*.png
    assets/icons/24/*.png
    docs/baseline/2026-10-31_ui/correct1/icon_contact_sheet.png（1× / 2× / 4× / 剪影 / 24 卡图）

用法（仓库根目录）：
    python tools/art_pipeline/make_icons.py
"""

import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT16 = os.path.join(ROOT, "assets", "icons", "16")
OUT24 = os.path.join(ROOT, "assets", "icons", "24")
SHEET_DIR = os.path.join(ROOT, "docs", "baseline", "2026-10-31_ui", "correct2")
SHEET_PATH = os.path.join(SHEET_DIR, "icon_contact_sheet.png")

# 字符 → 颜色（None = 透明）。每枚图标只允许出现其中 ≤3 个。
PALETTE = {
    ".": None,
    "k": (0x3A, 0x22, 0x2B),   # 深描边
    "w": (0xE2, 0xD7, 0xBD),   # 暖白
    "m": (0xA9, 0x9D, 0x89),   # 次级
    "s": (0xB9, 0xB8, 0xB0),   # 玩家/中性金属
    "r": (0xE3, 0x5B, 0x50),   # 危险/火焰
    "R": (0x8C, 0x34, 0x38),   # 火焰暗阶
    "g": (0xD5, 0xA3, 0x3D),   # 交互金/充能/技能
    "y": (0x8C, 0x6A, 0x24),   # 金·暗阶
    "n": (0xA4, 0xBC, 0x4D),   # 生命绿
    "N": (0x6E, 0x82, 0x30),   # 生命绿·暗阶
    "b": (0x62, 0xA1, 0xC2),   # 护盾蓝
    "B": (0x37, 0x61, 0x7A),   # 护盾蓝·暗阶
}

ICONS = {
    # HP 心形：约 11×11，双圆角方形瓣 → 收束成尖角，生命绿实心
    "hp": [
        "................",
        "................",
        "..nnn...nnn.....",
        "..nnnn.nnnn.....",
        "..nnnnnnnnn.....",
        "..nnnnnnnnn.....",
        "..nnnnnnnnn.....",
        "...nnnnnnn......",
        "....nnnnn.......",
        ".....nnn........",
        "......n.........",
        "................",
        "................",
        "................",
        "................",
        "................",
    ],
    # 护盾：平顶，左右竖边向下阶梯收尖；蓝色外框 + 暗色盾芯
    "shield": [
        "................",
        "................",
        "..bbbbbbbbbb....",
        "..bBBBBBBBBb....",
        "..bBBBBBBBBb....",
        "..bBBBBBBBBb....",
        "..bBBBBBBBBb....",
        "...bBBBBBBb.....",
        "...bBBBBBBb.....",
        "....bBBBBb......",
        ".....bBBb.......",
        "......bb........",
        "................",
        "................",
        "................",
        "................",
    ],
    # 护甲：肩部缺口 + 实心胸甲 + 暗色中缝，与护盾轮廓一眼可分
    "armor": [
        "................",
        "................",
        "..bb....bb......",
        "..bbbbbbbbbb....",
        "..bbbbbbbbbb....",
        "..bbbBBBBbbb....",
        "..bbbBBBBbbb....",
        "...bbBBBBbb.....",
        "...bbbbbbbb.....",
        "....bbbbbb......",
        "....bbbbbb......",
        ".....bbbb.......",
        "................",
        "................",
        "................",
        "................",
    ],
    # 金币：阶梯方圆形，金色外圈 + 暗色竖向币纹
    "gold": [
        "................",
        "................",
        "....gggggg......",
        "..gggggggggg....",
        "..ggyyyyyygg....",
        "..ggyggggygg....",
        "..ggyggggygg....",
        "..ggyggggygg....",
        "..ggyyyyyygg....",
        "..gggggggggg....",
        "....gggggg......",
        "................",
        "................",
        "................",
        "................",
        "................",
    ],
    # 火斩：左下→右上对角剑，红色剑刃 + 金色短护手 + 暗色剑柄
    "fire_slash": [
        "................",
        "...........rr...",
        "..........rrr...",
        ".........rrr....",
        "........rrr.....",
        ".......rrr......",
        "......rrr.......",
        ".....rrr........",
        "...ggggg........",
        "...kk...........",
        "..kk............",
        "..kk............",
        "................",
        "................",
        "................",
        "................",
    ],
    # 灼烧：顶部火舌向右错峰、底部宽；红色外层 + 金色火芯
    "burn": [
        "................",
        "..........rr....",
        ".........rrr....",
        ".....rr..rrrr...",
        "....rrr.rrrrr...",
        "....rrrrrrrrr...",
        "...rrrrrrrrrrr..",
        "...rrrggggrrrr..",
        "..rrrggggggrrr..",
        "..rrggggggggrr..",
        "..rrggggggggrr..",
        "..rrrggggggrrr..",
        "....rrrrrrrr....",
        "......rrrr......",
        ".......rr.......",
        "................",
    ],
    # 斧斩：斜向斧柄，斧头明显偏右上、单侧宽刃；灰白金属 + 金色箍 + 暗色柄
    "axe_slash": [
        "................",
        "......sssss.....",
        ".....ssssssss...",
        ".....ssssssss...",
        "......ssssss....",
        ".......gg.......",
        "......kk........",
        ".....kk.........",
        "....kk..........",
        "...kk...........",
        "..kk............",
        "................",
        "................",
        "................",
        "................",
        "................",
    ],
    # 武器：火焰剑（暖白剑刃 + 金色护手 + 暗色剑柄）
    "fire_sword": [
        "................",
        "...........ww...",
        "..........www...",
        ".........www....",
        "........www.....",
        ".......www......",
        "......www.......",
        ".....www........",
        "...ggggg........",
        "...kk...........",
        "..kk............",
        "..kk............",
        "................",
        "................",
        "................",
        "................",
    ],
    # 武器：战斧（斧头偏右上、单侧宽刃；金属 + 金色箍 + 暗色柄）
    "battle_axe": [
        "................",
        ".....sssss......",
        ".....sssssss....",
        ".....sssssssss..",
        ".....sssssss....",
        ".....sssss......",
        "......gg........",
        "......kk........",
        "......kk........",
        "......kk........",
        "......kk........",
        "......kk........",
        "......kk........",
        ".....gggg.......",
        "................",
        "................",
    ],
    # 消耗品：短瓶盖 + 窄颈 + 阶梯方瓶身，红色液体 + 暖白高光
    "potion": [
        "................",
        "....kkkk........",
        "....kkkk........",
        ".....rr.........",
        "....rrrr........",
        "...rrrrrr.......",
        "..rrrrrrrr......",
        "..rrwwrrrr......",
        "..rrwwrrrr......",
        "..rrrrrrrr......",
        "..rrrrrrrr......",
        "...rrrrrr.......",
        "...kkkkkk.......",
        "................",
        "................",
        "................",
    ],
    # 充能：金色折线闪电，顶部偏右，中部收窄，底部反向折回
    "charge": [
        "................",
        "........gg......",
        ".......gg.......",
        "......gg........",
        ".....gg.........",
        "....ggggg.......",
        "...gggggg.......",
        "......ggg.......",
        ".......gg.......",
        "......gg........",
        ".....gg.........",
        "....gg..........",
        "...gg...........",
        "..gg............",
        "................",
        "................",
    ],
    # 技能/星芒：四角星，中心块 + 阶梯四臂，金色
    "star": [
        "................",
        "......gg........",
        "......gg........",
        ".....gggg.......",
        ".....gggg.......",
        "..gggggggggggg..",
        "..gggggggggggg..",
        ".....gggg.......",
        ".....gggg.......",
        "......gg........",
        "......gg........",
        "................",
        "................",
        "................",
        "................",
        "................",
    ],
}

# 24×24 卡片主图 = 16×16 主体居中（不做拉伸）
CARD_ART = ["fire_sword", "battle_axe", "hp", "shield", "gold", "potion"]


def to_image(rows, size):
    if len(rows) != size:
        raise SystemExit("row count %d != %d" % (len(rows), size))
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    used = set()
    for y, row in enumerate(rows):
        if len(row) != size:
            raise SystemExit("row %d length %d != %d: %r" % (y, len(row), size, row))
        for x, ch in enumerate(row):
            col = PALETTE.get(ch)
            if col is None:
                if ch != ".":
                    raise SystemExit("unknown char %r at %d,%d" % (ch, x, y))
                continue
            used.add(ch)
            px[x, y] = (col[0], col[1], col[2], 255)
    _check(used, rows, size)
    return img, used


def _check(used, rows, size):
    # 附录 A.2：每枚图标最多 3 个实体颜色
    if len(used) > 3:
        raise SystemExit("too many colors %s: %s" % (sorted(used), rows[0]))
    # 附录 A.1：16×16 主体限制在 x=2…13 / y=1…14，四周留 1px 安全区
    if size == 16:
        for y, row in enumerate(rows):
            for x, ch in enumerate(row):
                if ch == ".":
                    continue
                if x < 2 or x > 13 or y < 1 or y > 14:
                    raise SystemExit("pixel outside safe area at %d,%d" % (x, y))


def centered24(icon16):
    img = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
    img.alpha_composite(icon16, (4, 4))
    return img


def build_sheet(icons16, icons24):
    """1× / 2× / 4× / 剪影 / 24 卡图，一张 contact sheet。"""
    names = list(icons16.keys())
    scale_rows = [(1, 16), (2, 32), (4, 64)]
    pad = 8
    label_w = 78
    row_h = 64 + pad
    width = label_w + len(names) * (64 + pad) + pad
    height = row_h * (len(scale_rows) + 2) + pad
    sheet = Image.new("RGBA", (width, height), (0x16, 0x0D, 0x13, 255))
    draw = ImageDraw.Draw(sheet)
    y = pad
    for factor, px in scale_rows:
        draw.text((pad, y + 24), "%dx" % factor, fill=(0xE2, 0xD7, 0xBD, 255))
        x = label_w
        for name in names:
            scaled = icons16[name].resize((px, px), Image.NEAREST)
            sheet.alpha_composite(scaled, (x, y))
            x += px + pad
        y += row_h
    # 剪影：暖白填充放暗底，确保实际可读后验证剑/斧、火焰/药剂、护盾/金币不混淆
    draw.text((pad, y + 24), "silhouette", fill=(0xE2, 0xD7, 0xBD, 255))
    x = label_w
    for name in names:
        sil = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        src = icons16[name].resize((64, 64), Image.NEAREST)
        ivory = Image.new("RGBA", (64, 64), (0xE2, 0xD7, 0xBD, 255))
        sil.paste(ivory, (0, 0), src)
        sheet.alpha_composite(sil, (x, y))
        x += 64 + pad
    y += row_h
    # 24×24 卡片主图（1× 与 2×）
    draw.text((pad, y + 24), "card 24", fill=(0xE2, 0xD7, 0xBD, 255))
    x = label_w
    for name in CARD_ART:
        sheet.alpha_composite(icons24[name], (x, y))
        x += 24 + pad
    x += 24
    for name in CARD_ART:
        sheet.alpha_composite(icons24[name].resize((48, 48), Image.NEAREST), (x, y + 8))
        x += 48 + pad
    return sheet


def main():
    os.makedirs(OUT16, exist_ok=True)
    os.makedirs(OUT24, exist_ok=True)
    made = {}
    for name, rows in ICONS.items():
        img, used = to_image(rows, 16)
        img.save(os.path.join(OUT16, name + ".png"))
        made[name] = img
        print("16: %-12s colors=%s" % (name, "".join(sorted(used))))
    made24 = {}
    for name in CARD_ART:
        img = centered24(made[name])
        img.save(os.path.join(OUT24, name + ".png"))
        made24[name] = img
        print("24: %s" % name)
    os.makedirs(SHEET_DIR, exist_ok=True)
    build_sheet(made, made24).save(SHEET_PATH)
    print("sheet:", os.path.relpath(SHEET_PATH, ROOT))


if __name__ == "__main__":
    main()
