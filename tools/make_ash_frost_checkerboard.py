from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "mockups" / "ash_frost_checkerboard_ui.png"
OUT.parent.mkdir(parents=True, exist_ok=True)
W, H = 1440, 810
BG = (25, 12, 17)
PANEL = (34, 20, 26)
PANEL2 = (44, 28, 34)
GOLD = (196, 161, 98)
GOLD_HI = (239, 207, 137)
TEXT = (234, 226, 207)
MUTED = (164, 151, 156)
DIM = (78, 53, 58)
GREEN = (71, 139, 71)
GREEN_HI = (104, 183, 88)
BROWN = (116, 82, 58)
BROWN_HI = (150, 107, 71)
RED = (202, 87, 83)
BLUE = (111, 165, 194)
PURPLE = (153, 119, 178)

im = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(im)

def font(size):
    return ImageFont.truetype(str(ROOT / "assets" / "fonts" / "zpix.ttf"), size)

F12, F14, F16, F18, F20, F24 = [font(s) for s in (12, 14, 16, 18, 20, 24)]

def rect(box, fill, outline=DIM, width=2):
    d.rectangle(box, fill=fill, outline=outline, width=width)

def txt(x, y, s, f=F16, color=TEXT):
    d.text((x, y), s, font=f, fill=color)

def center(box, s, f=F16, color=TEXT):
    x1, y1, x2, y2 = box
    bb = d.textbbox((0, 0), s, font=f)
    d.text(((x1 + x2 - (bb[2] - bb[0])) / 2, (y1 + y2 - (bb[3] - bb[1])) / 2 - 1), s, font=f, fill=color)

def sprite(path, box):
    img = Image.open(ROOT / path).convert("RGBA")
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)
    tw, th = int(box[2] - box[0]), int(box[3] - box[1])
    scale = max(1, min(tw // img.width, th // img.height))
    img = img.resize((img.width * scale, img.height * scale), Image.Resampling.NEAREST)
    im.paste(img, (int(box[0] + (tw - img.width) / 2), int(box[1] + th - img.height)), img)

def tree(x, y, color=GREEN_HI):
    d.rectangle((x + 5, y, x + 9, y + 3), fill=color)
    d.rectangle((x + 2, y + 3, x + 12, y + 7), fill=color)
    d.rectangle((x, y + 7, x + 14, y + 11), fill=color)
    d.rectangle((x + 6, y + 11, x + 8, y + 15), fill=BROWN)

def house(x, y, color=BROWN_HI):
    d.polygon([(x, y + 8), (x + 10, y), (x + 20, y + 8)], fill=color)
    d.rectangle((x + 3, y + 8, x + 17, y + 18), fill=color)
    d.rectangle((x + 8, y + 12, x + 12, y + 18), fill=BG)

def skull(x, y, color=RED):
    d.rectangle((x + 3, y, x + 15, y + 10), fill=color)
    d.rectangle((x + 5, y + 10, x + 13, y + 14), fill=color)
    d.rectangle((x + 5, y + 4, x + 7, y + 6), fill=BG)
    d.rectangle((x + 11, y + 4, x + 13, y + 6), fill=BG)
    d.rectangle((x + 8, y + 8, x + 10, y + 10), fill=BG)

# Header
rect((24, 18, 1416, 74), PANEL, GOLD, 2)
txt(44, 30, "灰烬与冻土 · 像素棋盘", F24, GOLD_HI)
txt(44, 60, "明显的格子、连续的路线、公开的巡逻下一步", F16, TEXT)

# Main board frame and right panel
rect((24, 94, 1050, 734), PANEL, DIM)
rect((1070, 94, 1416, 734), PANEL, GOLD, 2)
txt(1092, 110, "当前格子", F24, GOLD_HI)

# Region labels
for x, title, color in [(48, "A · 灰烬镇", GREEN_HI), (372, "B · 旧墓道", GOLD_HI), (694, "C · 冻土关隘", PURPLE)]:
    txt(x, 110, title, F16, color)

layout = [
    "##############",
    "#..T##T.V#..T#",
    "#N..##..E##XE#",
    "#V.X##P.N##N.#",
    "#SN.NDNN.NDNB#",
    "#...##R.N##R.#",
    "#..N##..E#..T#",
    "#V.N##V#.##.X#",
    "##############",
]
trap_ids = {45, 39, 110}
patrol_id = 30
player_id = 43
next_trap_id = 45
cw, ch, gap = 64, 58, 6
x0, y0 = 42, 150
for r in range(9):
    for c in range(14):
        chv = layout[r][c]
        idx = c + r * 14
        x, y = x0 + c * (cw + gap), y0 + r * (ch + gap)
        if chv == "#":
            # Empty void, matching the dark board background.
            if (c + r) % 3 == 0:
                tree(x + 22, y + 20, (46, 78, 46))
            continue
        # Every playable cell is an explicit tile; content cells become green rooms.
        fill = GREEN if chv not in [".", "D"] else BROWN
        outline = GREEN_HI if chv not in [".", "D"] else BROWN_HI
        rect((x, y, x + cw, y + ch), fill, outline, 2)
        d.rectangle((x + 5, y + 5, x + cw - 5, y + ch - 5), fill=PANEL)
        if idx == player_id:
            rect((x + 3, y + 3, x + cw - 3, y + ch - 3), (45, 75, 83), (235, 235, 220), 3)
            sprite("assets/characters/char/idle_01.png", (x + 14, y + 4, x + 50, y + 38))
            center((x + 6, y + 37, x + cw - 6, y + 52), "你", F12, (235, 235, 220))
        elif idx == patrol_id:
            rect((x + 3, y + 3, x + cw - 3, y + ch - 3), PANEL, RED, 3)
            sprite("assets/characters/a1_elite_brute_ice/idle_01.png", (x + 14, y + 4, x + 50, y + 38))
            center((x + 6, y + 37, x + cw - 6, y + 52), "巡逻", F12, RED)
        elif chv == "B":
            rect((x + 3, y + 3, x + cw - 3, y + ch - 3), PANEL, RED, 3)
            sprite("assets/characters/frozen_urn/idle_01.png", (x + 14, y + 4, x + 50, y + 38))
            center((x + 6, y + 37, x + cw - 6, y + 52), "BOSS", F12, RED)
        elif chv == "E":
            sprite("assets/characters/a1_elite_brute_ice/idle_01.png", (x + 14, y + 4, x + 50, y + 38))
            center((x + 6, y + 37, x + cw - 6, y + 52), "精英", F12, RED)
        elif chv == "T":
            d.rectangle((x + 21, y + 10, x + 43, y + 28), fill=GOLD, outline=GOLD_HI, width=2)
            d.line((x + 21, y + 18, x + 43, y + 18), fill=PANEL, width=2)
            center((x + 6, y + 32, x + cw - 6, y + 50), "宝箱", F12, GOLD_HI)
        elif chv == "N":
            skull(x + 22, y + 14)
            center((x + 6, y + 34, x + cw - 6, y + 52), "普通", F12, RED)
        elif chv == "P":
            house(x + 20, y + 12, GOLD_HI)
            center((x + 6, y + 34, x + cw - 6, y + 52), "商店", F12, GOLD_HI)
        elif chv == "R":
            d.rectangle((x + 27, y + 10, x + 37, y + 32), fill=GREEN_HI)
            d.rectangle((x + 19, y + 18, x + 45, y + 24), fill=GREEN_HI)
            center((x + 6, y + 34, x + cw - 6, y + 52), "休整", F12, GREEN_HI)
        elif chv == "V":
            d.polygon([(x + 32, y + 8), (x + 44, y + 22), (x + 32, y + 36), (x + 20, y + 22)], fill=PURPLE)
            center((x + 6, y + 36, x + cw - 6, y + 52), "神龛", F12, PURPLE)
        elif chv == "D":
            d.rectangle((x + 19, y + 10, x + 45, y + 36), fill=BROWN_HI, outline=GOLD_HI, width=2)
            center((x + 6, y + 36, x + cw - 6, y + 52), "区域门", F12, GOLD_HI)
        else:
            tree(x + 24, y + 16, GREEN_HI)
        if idx in trap_ids:
            for k in range(3):
                xx = x + 8 + k * 10
                d.polygon([(xx, y + 44), (xx + 5, y + 31), (xx + 10, y + 44)], fill=GOLD_HI)
            txt(x + 32, y + 34, "陷", F12, RED)

# Next-step arrow between patrol and trap
sx = x0 + 2 * (cw + gap) + cw / 2
sy = y0 + 2 * (ch + gap) - 12
ex = x0 + 3 * (cw + gap) + cw / 2
d.line((sx + 24, sy, ex - 18, sy), fill=GOLD_HI, width=3)
d.polygon([(ex - 18, sy - 8), (ex - 5, sy), (ex - 18, sy + 8)], fill=GOLD_HI)
txt(sx - 10, sy - 30, "下一步", F12, GOLD_HI)

# Board footer
rect((42, 682, 1028, 714), PANEL2, DIM)
center((42, 682, 1028, 714), "绿色：房间  ·  棕色：通道  ·  白框：你  ·  金箭头：巡逻预告", F14, TEXT)

# Right decision panel
rect((1092, 154, 1394, 282), PANEL2, RED, 2)
sprite("assets/characters/a1_elite_brute_ice/idle_01.png", (1108, 166, 1178, 264))
txt(1194, 172, "巡逻怪", F24, RED)
txt(1194, 214, "下一步：向左", F18, TEXT)
txt(1194, 246, "目标：破甲陷阱", F16, GOLD_HI)

steps = [
    ("① 等待", "原地不动，推进回合", BLUE),
    ("② 踩中陷阱", "怪物进入破甲格", GOLD_HI),
    ("③ 转轮战斗", "开局破甲，不直接秒杀", GREEN_HI),
]
for i, (title, desc, color) in enumerate(steps):
    y = 306 + i * 90
    rect((1092, y, 1394, y + 76), PANEL2, color, 2)
    txt(1108, y + 10, title, F20, color)
    txt(1108, y + 44, desc, F14, TEXT)

rect((1092, 594, 1394, 650), (82, 62, 35), GOLD_HI, 2)
center((1092, 594, 1394, 650), "等待一回合", F24, GOLD_HI)
rect((1092, 668, 1394, 710), PANEL2, DIM)
center((1092, 668, 1394, 710), "也可移动 / 绕行", F16, MUTED)

# Footer
rect((24, 750, 1416, 794), PANEL, DIM)
center((24, 750, 1416, 794), "棋盘只是视觉结构；真正决策是走哪一格、等一等，还是把怪物引到陷阱里", F16, TEXT)

im.save(OUT)
print(OUT)
