from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "mockups" / "patrol_trap_map_ui.png"
OUT.parent.mkdir(parents=True, exist_ok=True)
W, H = 1440, 810
BG = (20, 14, 24)
PANEL = (30, 22, 35)
PANEL2 = (39, 29, 44)
FLOOR = (47, 37, 49)
WALL = (28, 22, 33)
GOLD = (196, 161, 98)
GOLD_HI = (239, 207, 137)
TEXT = (234, 226, 207)
MUTED = (164, 151, 156)
DIM = (91, 76, 95)
GREEN = (101, 174, 130)
RED = (202, 87, 83)
BLUE = (111, 165, 194)
PURPLE = (153, 119, 178)

im = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(im)

def font(size):
    return ImageFont.truetype(str(ROOT / "assets" / "fonts" / "zpix.ttf"), size)

F14, F16, F18, F20, F22, F26, F32 = [font(s) for s in (14, 16, 18, 20, 22, 26, 32)]

def rect(box, fill=PANEL, outline=DIM, width=2):
    d.rectangle(box, fill=fill, outline=outline, width=width)

def txt(x, y, s, f=F16, color=TEXT):
    d.text((x, y), s, font=f, fill=color)

def center(box, s, f=F16, color=TEXT):
    x1, y1, x2, y2 = box
    bb = d.textbbox((0, 0), s, font=f)
    d.text(((x1 + x2 - (bb[2] - bb[0])) / 2, (y1 + y2 - (bb[3] - bb[1])) / 2 - 2), s, font=f, fill=color)

def sprite(path, box):
    img = Image.open(ROOT / path).convert("RGBA")
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)
    tw, th = int(box[2] - box[0]), int(box[3] - box[1])
    scale = max(1, min(tw // img.width, th // img.height))
    img = img.resize((img.width * scale, img.height * scale), Image.Resampling.NEAREST)
    im.paste(img, (int(box[0] + (tw - img.width) / 2), int(box[1] + th - img.height)), img)

# Header
rect((24, 20, 1416, 78), PANEL, GOLD, 2)
txt(44, 32, "SEEK DEAD · 巡逻与诱导", F26, GOLD_HI)
txt(44, 64, "看怪物下一步 → 移动或等待 → 利用陷阱 → 转轮战斗获得优势", F16, TEXT)

# Main map panel
rect((24, 100, 960, 724), PANEL, DIM)
txt(46, 114, "灰沼回廊 · 地图回合 04", F22, GOLD_HI)
txt(46, 148, "目标：让怪物踩到陷阱，下一场战斗开局破甲", F16, TEXT)

# Map grid: 7 x 5
cols, rows = 7, 5
cw, ch, gap = 112, 92, 10
x0, y0 = 48, 192
walls = {(0, 0), (1, 0), (3, 0), (4, 0), (5, 0), (0, 4), (1, 4), (5, 4), (6, 4)}
for r in range(rows):
    for c in range(cols):
        x, y = x0 + c * (cw + gap), y0 + r * (ch + gap)
        box = (x, y, x + cw, y + ch)
        if (c, r) in walls:
            rect(box, WALL, DIM)
            d.line((x + 10, y + 12, x + cw - 10, y + ch - 12), fill=DIM, width=3)
            continue
        rect(box, FLOOR, DIM)
        if (c, r) == (3, 2):
            # trap
            d.rectangle((x + 24, y + 24, x + 88, y + 60), fill=(64, 38, 38), outline=RED, width=2)
            for tx in range(5):
                xx = x + 30 + tx * 13
                d.polygon([(xx, y + 52), (xx + 6, y + 34), (xx + 12, y + 52)], fill=GOLD_HI)
            center((x + 4, y + 62, x + cw - 4, y + 86), "破甲陷阱", F14, RED)
        elif (c, r) == (1, 1):
            d.rectangle((x + 34, y + 18, x + 76, y + 48), fill=GOLD, outline=GOLD_HI, width=3)
            d.line((x + 34, y + 31, x + 76, y + 31), fill=BG, width=3)
            center((x + 4, y + 58, x + cw - 4, y + 86), "武器宝箱", F16, GOLD_HI)
        elif (c, r) == (1, 3):
            d.rectangle((x + 49, y + 12, x + 63, y + 48), fill=GREEN)
            d.rectangle((x + 38, y + 24, x + 74, y + 36), fill=GREEN)
            center((x + 4, y + 58, x + cw - 4, y + 86), "休整点", F16, GREEN)
        elif (c, r) == (6, 1):
            sprite("assets/characters/frozen_urn/idle_01.png", (x + 20, y + 4, x + 92, y + 66))
            center((x + 4, y + 66, x + cw - 4, y + 88), "冰封铁瓮", F14, RED)
        elif (c, r) == (4, 2):
            sprite("assets/characters/a1_elite_brute_ice/idle_01.png", (x + 26, y + 4, x + 86, y + 62))
            center((x + 4, y + 64, x + cw - 4, y + 86), "巡逻怪", F16, RED)
        elif (c, r) == (2, 3):
            rect(box, (43, 55, 52), BLUE, 3)
            sprite("assets/characters/char/idle_01.png", (x + 26, y + 4, x + 86, y + 62))
            center((x + 4, y + 64, x + cw - 4, y + 86), "你", F18, BLUE)
        else:
            center(box, "·", F26, DIM)

# Enemy predicted movement: from (4,2) left to trap at (3,2)
start_x = x0 + 4 * (cw + gap) + cw / 2
start_y = y0 + 2 * (ch + gap) + 18
end_x = x0 + 3 * (cw + gap) + cw / 2
end_y = start_y
d.line((start_x - 22, start_y, end_x + 28, end_y), fill=GOLD_HI, width=4)
d.polygon([(end_x + 28, end_y - 10), (end_x + 12, end_y), (end_x + 28, end_y + 10)], fill=GOLD_HI)
center((end_x - 26, start_y - 36, start_x + 30, start_y - 16), "下一步 ← 陷阱", F16, GOLD_HI)

# Map legend
rect((44, 670, 940, 706), PANEL2, DIM)
center((44, 670, 940, 706), "蓝色：你  ·  红色：怪物/BOSS  ·  金色箭头：怪物公开下一步", F16, TEXT)

# Right: decision panel
rect((978, 100, 1416, 724), PANEL, GOLD, 2)
txt(1000, 116, "当前局面", F26, GOLD_HI)
txt(1000, 154, "怪物正在接近陷阱", F20, TEXT)
rect((1000, 196, 1394, 306), PANEL2, RED, 2)
sprite("assets/characters/a1_elite_brute_ice/idle_01.png", (1014, 204, 1088, 294))
txt(1104, 210, "寒铁精英", F26, RED)
txt(1104, 252, "下一步：向左进入陷阱", F18, TEXT)

# Three-step explanation
steps = [
    ("① 选择等待", "你原地不动，不消耗任何行动点", BLUE),
    ("② 怪物踩陷阱", "地图推进一回合，诱导成功", GOLD_HI),
    ("③ 转轮战斗", "敌方护甲 20 → 0，仍需停轮击败", GREEN),
]
for i, (title, desc, color) in enumerate(steps):
    y = 328 + i * 90
    rect((1000, y, 1394, y + 76), PANEL2, color, 2)
    txt(1016, y + 10, title, F22, color)
    txt(1016, y + 46, desc, F14, TEXT)

rect((1000, 612, 1394, 666), (82, 62, 35), GOLD_HI, 2)
center((1000, 612, 1394, 666), "等待一回合", F26, GOLD_HI)
rect((1000, 680, 1394, 710), PANEL2, DIM)
center((1000, 680, 1394, 710), "也可以选择移动或绕行", F14, MUTED)

# Footer
rect((24, 744, 1416, 796), PANEL, DIM)
center((24, 744, 1416, 796), "陷阱不是秒杀：它只创造战斗优势；真正击败怪物仍然依靠转轮与 Build", F18, TEXT)

im.save(OUT)
print(OUT)
