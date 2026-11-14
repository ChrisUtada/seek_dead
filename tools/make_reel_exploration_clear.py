from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "mockups" / "reel_exploration_clear_ui.png"
OUT.parent.mkdir(parents=True, exist_ok=True)
W, H = 1440, 810
BG = (20, 14, 24)
PANEL = (30, 22, 35)
PANEL2 = (39, 29, 44)
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

F14, F16, F18, F20, F22, F26, F34, F42 = [font(s) for s in (14, 16, 18, 20, 22, 26, 34, 42)]

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

def arrow(x, y):
    d.line((x, y, x + 35, y), fill=GOLD_HI, width=4)
    d.polygon([(x + 35, y - 10), (x + 50, y), (x + 35, y + 10)], fill=GOLD_HI)

# Header
rect((24, 20, 1416, 80), PANEL, GOLD, 2)
txt(44, 34, "SEEK DEAD · 一眼看懂探索与转轮", F26, GOLD_HI)
txt(44, 66, "地图只负责选目标；转轮负责解决遭遇；成长会真实改变下一次转轮", F16, TEXT)

# Three panels
panels = [(24, 102, 450, 720), (468, 102, 968, 720), (986, 102, 1416, 720)]
for p in panels:
    rect(p, PANEL, DIM)

# Step 1: map choice
rect((44, 120, 430, 178), PANEL2, GREEN, 2)
txt(62, 130, "① 选一个目的地", F26, GREEN)
txt(62, 162, "先看奖励，再决定去哪里", F16, TEXT)

# Player start
rect((54, 208, 196, 300), PANEL2, BLUE, 3)
sprite("assets/characters/char/idle_01.png", (66, 210, 124, 270))
center((54, 264, 196, 296), "当前位置", F18, BLUE)
txt(104, 328, "下一站", F18, MUTED)

choices = [
    ("怪物据点", "战斗 · 获得成长", RED, "assets/characters/a1_elite_brute_ice/idle_01.png"),
    ("武器宝箱", "探索 · 获得装备", GOLD_HI, "assets/icons/weapons/cell/icon_fire_sword_32.png"),
    ("商店", "购买 · 定向补强", BLUE, "assets/icons/weapons/cell/icon_forge_greatsword_32.png"),
]
for i, (name, sub, color, icon) in enumerate(choices):
    y = 364 + i * 96
    rect((64, y, 420, y + 82), PANEL2, color if i == 0 else DIM, 3 if i == 0 else 2)
    sprite(icon, (76, y + 8, 122, y + 54))
    txt(136, y + 12, name, F22, color)
    txt(136, y + 46, sub, F16, TEXT)
    if i == 0:
        txt(300, y + 14, "已选择 →", F16, GREEN)

rect((54, 662, 420, 704), PANEL2, DIM)
center((54, 662, 420, 704), "不用先转动转轮来决定走哪里", F16, MUTED)

# Step 2: combat encounter
rect((488, 120, 948, 178), PANEL2, GOLD_HI, 2)
txt(506, 130, "② 停轮解决遭遇", F26, GOLD_HI)
txt(506, 162, "例：怪物据点 → 转轮战斗", F16, TEXT)

rect((500, 202, 936, 316), PANEL2, RED, 2)
sprite("assets/characters/a1_elite_brute_ice/idle_01.png", (514, 208, 586, 300))
txt(600, 214, "寒铁精英", F26, RED)
txt(600, 256, "HP 402 / 402", F20, TEXT)
txt(600, 286, "预告：下回合叠甲＋冻结", F16, GOLD_HI)

# Reel three cells
reel_paths = [
    "assets/icons/weapons/cell/icon_fire_sword_32.png",
    "assets/icons/weapons/cell/icon_fire_sword_32.png",
    "assets/icons/weapons/cell/icon_forge_greatsword_32.png",
]
for i, p in enumerate(reel_paths):
    x = 512 + i * 138
    rect((x, 342, x + 118, 452), PANEL2, GOLD_HI, 3)
    sprite(p, (x + 23, 352, x + 95, 424))
    center((x + 4, 418, x + 114, 446), "火斩", F20, TEXT)

rect((500, 478, 936, 554), (64, 48, 28), GOLD_HI, 2)
center((500, 478, 936, 554), "三列火斩 → 同族三连 ×1.5", F26, GOLD_HI)
txt(518, 584, "每列都可以按停；停中的符号决定结果", F18, TEXT)
rect((500, 620, 936, 678), (84, 64, 35), GOLD_HI, 2)
center((500, 620, 936, 678), "空格：逐列停轮", F26, GOLD_HI)

# Step 3: growth choice
rect((1006, 120, 1396, 178), PANEL2, PURPLE, 2)
txt(1024, 130, "③ 选一项成长", F26, PURPLE)
txt(1024, 162, "胜利后强化当前 Build", F16, TEXT)

cards = [
    ("武器训练", "火焰剑熟练 +1", "武器来源继续成长", GOLD_HI, "assets/icons/weapons/cell/icon_fire_sword_32.png"),
    ("符号灌注", "火斩 3格 → 4格", "转轮里出现得更多", GREEN, "assets/icons/weapons/cell/icon_forge_greatsword_32.png"),
    ("守望", "下房护盾 +8", "下一战更容易生存", BLUE, ""),
]
for i, (title, effect, note, color, icon) in enumerate(cards):
    y = 212 + i * 136
    rect((1014, y, 1388, y + 118), PANEL2, color, 2)
    if icon:
        sprite(icon, (1028, y + 14, 1074, y + 60))
    txt(1090 if icon else 1030, y + 14, title, F22, color)
    txt(1030, y + 52, effect, F20, TEXT)
    txt(1030, y + 86, note, F16, MUTED)

rect((1014, 634, 1388, 700), PANEL2, PURPLE, 2)
center((1014, 634, 1388, 700), "成长后，下一次转轮会实际改变", F18, PURPLE)

# Arrows between panels
arrow(452, 398)
arrow(970, 398)

# Bottom loop
rect((24, 742, 1416, 794), PANEL, GOLD, 2)
center((24, 742, 1416, 794), "选目标  →  停轮战斗  →  获得成长  →  回到地图继续探索  →  准备后挑战 BOSS", F20, GOLD_HI)

im.save(OUT)
print(OUT)
