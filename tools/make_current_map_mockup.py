from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "mockups" / "current_map_design_ui.png"
OUT.parent.mkdir(parents=True, exist_ok=True)
W, H = 1440, 810
BG = (20, 14, 24)
PANEL = (30, 22, 35)
PANEL2 = (39, 29, 44)
WALL = (27, 21, 32)
FLOOR = (46, 36, 48)
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

F12, F14, F16, F18, F20, F22, F26 = [font(s) for s in (12, 14, 16, 18, 20, 22, 26)]

def rect(box, fill=PANEL, outline=DIM, width=2):
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

# Header
rect((24, 18, 1416, 74), PANEL, GOLD, 2)
txt(42, 30, "SEEK DEAD · 灰沼回廊 / 当前地图方案", F26, GOLD_HI)
txt(42, 62, "14×9  ·  61 可行走格  ·  16 场战斗  ·  4 宝箱  ·  3 陷阱  ·  无骰子 / 无行动点", F16, TEXT)

# Map and side panels
rect((24, 94, 958, 734), PANEL, DIM)
rect((976, 94, 1416, 734), PANEL, GOLD, 2)
txt(44, 108, "三区域逻辑地图", F22, GOLD_HI)
txt(44, 140, "点击相邻格移动，或选择等待；每次操作推进一个地图回合", F14, TEXT)
txt(1000, 108, "当前局面", F26, GOLD_HI)

# Region labels
for x, title, color in [(60, "A · 入口区", GREEN), (356, "B · 交汇区", GOLD_HI), (668, "C · 深层区", PURPLE)]:
    txt(x, 166, title, F16, color)

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
player_id = 43  # row3,col1 start
next_trap_id = 45

cw, ch, gap = 58, 52, 4
x0, y0 = 48, 196
for r in range(9):
    for c in range(14):
        chv = layout[r][c]
        idx = c + r * 14
        x, y = x0 + c * (cw + gap), y0 + r * (ch + gap)
        box = (x, y, x + cw, y + ch)
        if chv == "#":
            rect(box, WALL, DIM)
            continue
        rect(box, FLOOR, DIM)
        if idx == player_id:
            rect(box, (43, 55, 52), BLUE, 3)
            sprite("assets/characters/char/idle_01.png", (x + 8, y + 2, x + 50, y + 40))
            center((x + 2, y + 36, x + cw - 2, y + 50), "你", F12, BLUE)
        elif idx == patrol_id:
            sprite("assets/characters/a1_elite_brute_ice/idle_01.png", (x + 8, y + 2, x + 50, y + 40))
            center((x + 2, y + 36, x + cw - 2, y + 50), "巡逻", F12, RED)
        elif chv == "B":
            sprite("assets/characters/frozen_urn/idle_01.png", (x + 8, y + 2, x + 50, y + 40))
            center((x + 2, y + 36, x + cw - 2, y + 50), "BOSS", F12, RED)
        elif chv == "E":
            sprite("assets/characters/a1_elite_brute_ice/idle_01.png", (x + 8, y + 2, x + 50, y + 40))
            center((x + 2, y + 36, x + cw - 2, y + 50), "精英", F12, RED)
        elif chv == "T":
            d.rectangle((x + 17, y + 9, x + 41, y + 25), fill=GOLD, outline=GOLD_HI, width=2)
            d.line((x + 17, y + 16, x + 41, y + 16), fill=BG, width=2)
            center((x + 2, y + 30, x + cw - 2, y + 48), "宝箱", F12, GOLD_HI)
        elif chv == "N":
            center(box, "普", F18, RED)
        elif chv == "P":
            center(box, "商", F18, GOLD_HI)
        elif chv == "R":
            center(box, "休", F18, GREEN)
        elif chv == "V":
            center(box, "事", F18, PURPLE)
        elif chv == "D":
            center(box, "门", F18, BLUE)
        if idx in trap_ids:
            d.rectangle((x + 37, y + 30, x + 53, y + 46), fill=(64, 38, 38), outline=RED, width=1)
            center((x + 33, y + 29, x + 57, y + 47), "陷", F12, RED)

# Patrol next-step arrow: row2,col2 → row2,col3 trap
sx = x0 + 2 * (cw + gap) + cw / 2
sy = y0 + 2 * (ch + gap) - 12
ex = x0 + 3 * (cw + gap) + cw / 2
d.line((sx + 20, sy, ex - 18, sy), fill=GOLD_HI, width=3)
d.polygon([(ex - 18, sy - 8), (ex - 5, sy), (ex - 18, sy + 8)], fill=GOLD_HI)
center((sx - 18, sy - 28, ex + 28, sy - 10), "下一步", F12, GOLD_HI)

# Map legend/footer
rect((44, 682, 938, 714), PANEL2, DIM)
center((44, 682, 938, 714), "普：普通战  ·  陷：破甲陷阱  ·  门：区域通道  ·  箭头：怪物下一步", F14, TEXT)

# Right decision cards
rect((1000, 156, 1392, 276), PANEL2, RED, 2)
sprite("assets/characters/a1_elite_brute_ice/idle_01.png", (1014, 164, 1084, 260))
txt(1100, 166, "巡逻怪", F26, RED)
txt(1100, 206, "预告：向左进入陷阱", F18, TEXT)
txt(1100, 238, "实际移动与预告一致", F16, MUTED)

steps = [
    ("① 选择等待", "你原地不动，地图推进一回合", BLUE),
    ("② 怪物踩陷阱", "触发公开破甲陷阱", GOLD_HI),
    ("③ 转轮战斗", "敌方护甲降低，仍靠 Build 击败", GREEN),
]
for i, (title, desc, color) in enumerate(steps):
    y = 298 + i * 90
    rect((1000, y, 1392, y + 76), PANEL2, color, 2)
    txt(1016, y + 10, title, F22, color)
    txt(1016, y + 46, desc, F14, TEXT)

rect((1000, 594, 1392, 650), (82, 62, 35), GOLD_HI, 2)
center((1000, 594, 1392, 650), "等待一回合", F26, GOLD_HI)
rect((1000, 666, 1392, 710), PANEL2, DIM)
center((1000, 666, 1392, 710), "也可移动 / 绕行 / 查看构筑", F16, MUTED)

# Footer
rect((24, 750, 1416, 794), PANEL, DIM)
center((24, 750, 1416, 794), "地图负责观察与诱导；转轮负责战斗与成长；BOSS 由你准备好后主动挑战", F18, TEXT)

im.save(OUT)
print(OUT)
