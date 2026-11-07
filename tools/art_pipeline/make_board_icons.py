#!/usr/bin/env python3
"""G3-02 棋盘节点图标（2026-11-07）

沿用 make_icons.py 的规则：
    16×16 RGBA；主体限制在 x=2…13 / y=1…14；每枚 ≤3 个实体颜色 + 透明；
    不允许半透明过渡像素；不预烘焙外框（状态框由 BoardScreen 绘制）。

输出：
    assets/icons/16/board_{start,normal,elite,boss,charm,shop,rest,treasure,shrine,armory}.png
    docs/baseline/2026-11-07_g3/board_icons_sheet.png（1× / 2× / 4×）

用法（仓库根目录）：
    python -I tools/art_pipeline/make_board_icons.py
"""

import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT16 = os.path.join(ROOT, "assets", "icons", "16")
SHEET = os.path.join(ROOT, "docs", "baseline", "2026-11-07_g3", "board_icons_sheet.png")

PALETTE = {
    ".": None,
    "k": (0x3A, 0x22, 0x2B),   # 深描边
    "w": (0xE2, 0xD7, 0xBD),   # 暖白
    "g": (0xD5, 0xA3, 0x3D),   # 交互金
    "y": (0x8C, 0x6A, 0x24),   # 金·暗阶
    "r": (0xE3, 0x5B, 0x50),   # 敌人红
    "R": (0x8C, 0x34, 0x38),   # 敌人红·暗阶
}

ICONS = {
    # 起点：向右上升的三级阶梯
    "start": [
        "................",
        "................",
        "..........kkkk..",
        "..........kwwk..",
        "..........kwwk..",
        ".......kkkkwwk..",
        ".......kwwkwwk..",
        ".......kwwkwwk..",
        "....kkkkwwkwwk..",
        "....kwwkwwkwwk..",
        "....kwwkwwkwwk..",
        ".kkkkwwkwwkwwk..",
        ".kwwkwwkwwkwwk..",
        ".kwwkwwkwwkwwk..",
        ".kkkkkkkkkkkkk..",
        "................",
    ],
    # 普通战斗：直立短剑（红刃、暖白护手）
    "normal": [
        "................",
        "................",
        "......k...k.....",
        ".......kk.......",
        "......krrk......",
        "......krrk......",
        "......krrk......",
        "......krrk......",
        "......krrk......",
        "....kkrrrrkk....",
        "......kRRk......",
        "......kRRk......",
        "......kRRk......",
        ".......kk.......",
        "................",
        "................",
    ],
    # 精英：带角颅骨（红底 + 深色眼窝/齿缝）
    "elite": [
        "................",
        "................",
        "...rr......rr...",
        "...rrr....rrr...",
        "....rrr..rrr....",
        "....rrrrrrrr....",
        "...rrrrrrrrrr...",
        "..rrrkrrrrkrrr..",
        "..rrrrrrrrrrrr..",
        "..rrkkrrrrkkrr..",
        "...rrrrrrrrrr...",
        "....rrrrrrrr....",
        ".....rrrrrr.....",
        "......rrrr......",
        "................",
        "................",
    ],
    # BOSS：金冠（三尖 + 暗金宝石）
    "boss": [
        "................",
        "................",
        "..g....g....g...",
        "..gg...gg...gg..",
        "..ggg..ggg..ggg.",
        "..gggggggggggg..",
        "..gggggggggggg..",
        "..gyggggggggyg..",
        "..gggggggggggg..",
        "...gggggggggg...",
        "....gggggggg....",
        "....kkkkkkkk....",
        "................",
        "................",
        "................",
        "................",
    ],
    # 护符：菱形护身符（暖白边 + 金色核心）
    "charm": [
        "................",
        "................",
        ".......kk.......",
        "......kwwk......",
        ".....kwwwwk.....",
        "....kwwwwwwk....",
        "...kwwwwwwwwk...",
        "..kwwwggggwwwk..",
        "..kwwwggggwwwk..",
        "...kwwwwwwwwk...",
        "....kwwwwwwk....",
        ".....kwwwwk.....",
        "......kwwk......",
        ".......kk.......",
        "................",
        "................",
    ],
    # 商店：条纹雨棚 + 摊位柜台
    "shop": [
        "................",
        "................",
        "..kkkkkkkkkkkk..",
        "..kggggggggggk..",
        "..kgwkgwkgwkgk..",
        "..kggggggggggk..",
        "..kkkkkkkkkkkk..",
        "...kwwwwwwwwk...",
        "...kwwwwwwwwk...",
        "...kwwwwkwwwk...",
        "...kwwwwkwwwk...",
        "...kkkkkkkkkk...",
        "................",
        "................",
        "................",
        "................",
    ],
    # 棋子：金色兵（12×12 主体，居中放在 16×16 画布）
    "piece": [
        "................",
        "................",
        "......gggg......",
        ".....gggggg.....",
        "......gggg......",
        ".....gggggg.....",
        "....gggggggg....",
        "....gggggggg....",
        "...gggggggggg...",
        "...gggggggggg...",
        "..kkkkkkkkkkkk..",
        "................",
        "................",
        "................",
        "................",
        "................",
    ],
    # 休整：营火（红焰 + 暖白柴堆）
    "rest": [
        "................",
        "................",
        ".......r........",
        "......rrr.......",
        "......rrr.......",
        ".....rrrrr......",
        ".....rrrrr......",
        "....rrrrrrr.....",
        ".....rrrrr......",
        "..kkkkkkkkkkk...",
        "...kwwwwwwwk....",
        "....kwwwwwk.....",
        ".....kkkkk......",
        "................",
        "................",
        "................",
    ],
    # 宝箱：木箱轮廓 + 锁孔（金色箱体、暖白锁扣）
    "treasure": [
        "................",
        "................",
        "...kkkkkkkkkk...",
        "..kggggggggggk..",
        "..kggggggggggk..",
        "..kkkkkkkkkkkk..",
        "..kggggggggggk..",
        "..kggggwwggggk..",
        "..kggggwwggggk..",
        "..kgggwwwwgggk..",
        "..kggggwwggggk..",
        "..kggggggggggk..",
        "..kkkkkkkkkkkk..",
        "................",
        "................",
        "................",
    ],
    # 神龛：石龛屋顶 + 龛身 + 底座（暖白龛体、金色檐口）
    "shrine": [
        "................",
        "................",
        "......kkkk......",
        ".....kggggk.....",
        "....kggggggk....",
        "...kggggggggk...",
        "..kkkkkkkkkkkk..",
        ".....kwwwwk.....",
        ".....kwwwwk.....",
        ".....kwwwwk.....",
        ".....kwwwwk.....",
        "...kkkkkkkkkk...",
        "...kggggggggk...",
        "...kkkkkkkkkk...",
        "................",
        "................",
    ],
    # 武器藏库：交叉双剑（暖白剑身、金色护手），一眼可读的“武库”符号
    "armory": [
        "................",
        "..kk........kk..",
        "..kwk......kwk..",
        "...kwk....kwk...",
        "....kwk..kwk....",
        ".....kwkkwk.....",
        "......kggk......",
        ".....kwkkwk.....",
        "....kwk..kwk....",
        "...kwk....kwk...",
        "..kwk......kwk..",
        "..kk........kk..",
        "................",
        "................",
        "................",
        "................",
    ],
}


def validate(name: str, rows: list[str]) -> None:
    assert len(rows) == 16, f"{name}: {len(rows)} rows"
    used = set()
    for y, row in enumerate(rows):
        assert len(row) == 16, f"{name} row {y}: {len(row)} cols"
        for x, ch in enumerate(row):
            assert ch in PALETTE, f"{name}: unknown char {ch}"
            if PALETTE[ch] is not None:
                used.add(ch)
                if y == 0 or y == 15 or x == 0 or x == 15:
                    raise AssertionError(f"{name}: body touches border at {x},{y}")
    assert len(used) <= 3, f"{name}: {len(used)} colors {sorted(used)}"


def render(rows: list[str]) -> Image.Image:
    im = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    px = im.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            col = PALETTE[ch]
            if col is not None:
                px[x, y] = (*col, 255)
    return im


def main() -> None:
    os.makedirs(OUT16, exist_ok=True)
    os.makedirs(os.path.dirname(SHEET), exist_ok=True)
    names = list(ICONS)
    for name in names:
        validate(name, ICONS[name])
        im = render(ICONS[name])
        path = os.path.join(OUT16, f"board_{name}.png")
        im.save(path)
        print("wrote", path)

    # 1× / 2× / 4× contact sheet（深底，便于看边缘与色数）
    scales = [1, 2, 4]
    pad = 4
    cell = 16 * 4
    w = pad + len(names) * (cell + pad)
    h = pad
    for s in scales:
        h += 16 * s + pad
    sheet = Image.new("RGBA", (w, h), (0x16, 0x0D, 0x13, 255))
    y = pad
    for s in scales:
        x = pad
        for name in names:
            im = render(ICONS[name]).resize((16 * s, 16 * s), Image.NEAREST)
            sheet.alpha_composite(im, (x, y))
            x += cell + pad
        y += 16 * s + pad
    sheet.save(SHEET)
    print("wrote", SHEET)


if __name__ == "__main__":
    main()
