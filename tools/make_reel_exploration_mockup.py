from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "mockups" / "reel_exploration_ui.png"
OUT.parent.mkdir(parents=True, exist_ok=True)
W, H = 1440, 810
BG = (20, 14, 24)
PANEL = (29, 21, 34)
PANEL_2 = (36, 26, 42)
GOLD = (190, 157, 96)
GOLD_HI = (235, 203, 129)
TEXT = (230, 222, 201)
MUTED = (153, 142, 148)
DIM = (94, 80, 98)
RED = (198, 83, 82)
GREEN = (96, 170, 125)
BLUE = (106, 155, 188)
PURPLE = (77, 57, 91)

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
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    d.text(((x1 + x2 - tw) / 2, (y1 + y2 - th) / 2 - 2), s, font=f, fill=color)

def sprite(path, box):
    img = Image.open(ROOT / path).convert("RGBA")
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)
    target_w, target_h = int(box[2] - box[0]), int(box[3] - box[1])
    scale = max(1, min(target_w // img.width, target_h // img.height))
    img = img.resize((img.width * scale, img.height * scale), Image.Resampling.NEAREST)
    im.paste(img, (int(box[0] + (target_w - img.width) / 2), int(box[1] + target_h - img.height)), img)

# Header
rect((24, 20, 1416, 66), PANEL, GOLD, 2)
txt(44, 33, "SEEK DEAD · 灰沼远征", F22, GOLD_HI)
txt(890, 37, "ACT I  ·  探索回合 04  ·  HP 86/100  ·  金币 37", F16, TEXT)

# Main panels
rect((24, 82, 866, 650), PANEL, DIM)
rect((880, 82, 1416, 650), PANEL, GOLD, 2)
txt(46, 98, "灰沼地窖 · 迷雾地图", F20, GOLD_HI)
txt(46, 126, "公开：精英 / BOSS / 装备    未知区域不决定奖励，地图内容已冻结", F14, MUTED)
txt(902, 98, "探索转轮", F20, GOLD_HI)
txt(902, 126, "按停获得行动；不是随机决定地图内容", F14, MUTED)

# Map grid
cols, rows = 6, 4
cw, ch, gap = 108, 104, 12
x0, y0 = 48, 166
public = {
    (0, 0): ("rest", "休整"), (1, 0): ("shop", "商店"),
    (3, 2): ("chest", "武器宝箱"), (4, 1): ("elite", "寒铁精英"),
    (5, 0): ("boss", "冰封铁瓮"),
}
path = {(0, 2), (1, 2), (2, 2), (2, 1)}
legal = {(3, 2), (2, 1), (1, 2)}
for r in range(rows):
    for c in range(cols):
        x, y = x0 + c * (cw + gap), y0 + r * (ch + gap)
        box = (x, y, x + cw, y + ch)
        if (c, r) in public:
            rect(box, PANEL_2, GOLD if (c, r) in [(3, 2), (5, 0)] else DIM)
            kind, label = public[(c, r)]
            if kind == "elite":
                sprite("assets/characters/a1_elite_brute_ice/idle_01.png", (x + 20, y + 6, x + 88, y + 70))
            elif kind == "boss":
                sprite("assets/characters/frozen_urn/idle_01.png", (x + 18, y + 4, x + 90, y + 72))
            elif kind == "chest":
                d.rectangle((x + 36, y + 20, x + 72, y + 48), fill=GOLD, outline=GOLD_HI, width=3)
                d.line((x + 36, y + 32, x + 72, y + 32), fill=BG, width=3)
                d.rectangle((x + 50, y + 30, x + 58, y + 39), fill=BG)
            elif kind == "shop":
                d.ellipse((x + 37, y + 13, x + 71, y + 47), fill=GOLD, outline=GOLD_HI, width=2)
                center((x + 37, y + 13, x + 71, y + 47), "金", F18, BG)
            else:
                d.rectangle((x + 48, y + 12, x + 60, y + 48), fill=GREEN)
                d.rectangle((x + 36, y + 24, x + 72, y + 36), fill=GREEN)
            center((x + 2, y + 72, x + cw - 2, y + 98), label, F14, GOLD_HI if kind in ["boss", "chest"] else TEXT)
        elif (c, r) in path:
            rect(box, (43, 55, 52), BLUE if (c, r) in legal else DIM)
            if (c, r) == (2, 2):
                sprite("assets/characters/char/idle_01.png", (x + 20, y + 4, x + 88, y + 72))
                center((x + 2, y + 72, x + cw - 2, y + 98), "当前位置", F14, BLUE)
            else:
                center(box, "已探索", F16, MUTED)
        else:
            rect(box, (27, 20, 35), PURPLE)
            center(box, "?", F32, PURPLE)

# Map footer
rect((44, 572, 846, 630), PANEL_2, DIM)
txt(60, 582, "当前：破碎回廊", F16, GOLD_HI)
txt(60, 607, "可选：→ 向右探索（武器宝箱）  ·  ↑ 返回整备  ·  BOSS 暂不强制挑战", F14, TEXT)

# Reel cards
reels = [
    ("移动", "×2", GREEN, "靴",
     "沿已开放区域移动"),
    ("探索", "×1", GOLD_HI, "眼",
     "驱散相邻迷雾"),
    ("搜寻", "×1", BLUE, "箱",
     "开启宝箱 / 获得补给"),
]
for i, (name, count, color, glyph, desc) in enumerate(reels):
    x = 902 + i * 166
    box = (x, 166, x + 152, 326)
    rect(box, PANEL_2, color, 3)
    center((x + 4, 176, x + 148, 204), name, F20, color)
    center((x + 12, 204, x + 140, 270), glyph, F32, color)
    center((x + 4, 268, x + 148, 296), count, F22, TEXT)
    center((x + 4, 296, x + 148, 320), desc, F14, MUTED)
    center((x + 4, 328, x + 148, 350), "已停" if i == 2 else "空格停列", F14, color)

# Action allocation
rect((902, 370, 1394, 472), PANEL_2, DIM)
txt(918, 382, "本轮行动分配", F16, GOLD_HI)
txt(918, 410, "① 向右移动 → 驱散迷雾       ② 探索回廊 → 获得武器", F14, TEXT)
txt(918, 437, "③ 搜寻宝箱 → 获得消耗品与金币", F14, TEXT)

# Loot preview
rect((902, 488, 1394, 572), PANEL_2, GOLD)
txt(918, 500, "探索发现 · 同源火系构筑", F16, GOLD_HI)
sprite("assets/icons/weapons/cell/icon_fire_sword_32.png", (920, 524, 960, 564))
sprite("assets/icons/weapons/cell/icon_forge_greatsword_32.png", (970, 524, 1010, 564))
txt(1022, 525, "火焰剑 + 锻炉巨剑", F16, TEXT)
txt(1022, 549, "不同来源火斩，仍可同族连线", F14, MUTED)

rect((902, 588, 1208, 632), (82, 62, 35), GOLD_HI, 2)
center((902, 588, 1208, 632), "停轮并探索  →", F20, GOLD_HI)
rect((1220, 588, 1394, 632), PANEL_2, DIM)
center((1220, 588, 1394, 632), "查看构筑", F18, TEXT)

# Bottom flow
rect((24, 666, 866, 748), PANEL, DIM)
txt(46, 680, "探索循环", F16, GOLD_HI)
steps = ["选目标", "转轮停列", "分配行动", "获得战利品", "准备后挑战BOSS"]
x = 46
for i, step in enumerate(steps):
    txt(x, 710, step, F16, TEXT if i < 4 else GOLD_HI)
    x += d.textlength(step, font=F16) + 24
    if i < len(steps) - 1:
        txt(x - 10, 710, "→", F16, MUTED)
        x += 22
rect((880, 666, 1416, 748), (49, 31, 39), RED, 2)
center((880, 666, 1416, 748), "准备完成后：挑战 冰封铁瓮", F22, RED)
txt(32, 770, "玩法概念稿 · 非最终界面 · 仅用于展示转轮驱动地图探索的交互结构", F14, MUTED)
txt(1160, 770, "SEEK DEAD / UI MOCKUP", F14, DIM)

im.save(OUT)
print(OUT)
