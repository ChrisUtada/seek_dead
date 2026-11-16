from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(r"C:/Users/chris/.kimi-code/sessions/wd_seek_dead_8eaddc1acf35/session_b048cc92-76b5-4971-9749-f6d123761f40/media/f_96adf7e7-f80d-4a7a-9bae-1a2094a50fdb.png")
OUT = ROOT / "docs" / "mockups" / "ash_frost_border_grid_ui.png"
OUT.parent.mkdir(parents=True, exist_ok=True)
W, H = 1440, 810
GOLD = (196, 161, 98, 255)
GOLD_HI = (239, 207, 137, 255)
TEXT = (234, 226, 207, 255)
MUTED = (178, 163, 166, 255)
DIM = (105, 89, 105, 255)
GREEN = (105, 180, 136, 255)
RED = (211, 94, 88, 255)
BLUE = (116, 173, 202, 255)
PURPLE = (162, 130, 187, 255)

base = Image.open(SOURCE).convert("RGBA").resize((W, H), Image.Resampling.LANCZOS)
# Slightly darken the backdrop so UI cues remain readable without changing the scene itself.
shade = Image.new("RGBA", (W, H), (14, 10, 18, 48))
base = Image.alpha_composite(base, shade)

def font(size):
    return ImageFont.truetype(str(ROOT / "assets" / "fonts" / "zpix.ttf"), size)

F12, F14, F16, F18, F20, F24 = [font(s) for s in (12, 14, 16, 18, 20, 24)]
d = ImageDraw.Draw(base, "RGBA")

def rect(box, fill, outline, width=2):
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
    base.alpha_composite(img, (int(box[0] + (tw - img.width) / 2), int(box[1] + th - img.height)))

# Header: compact and translucent, preserving the castle portal.
rect((24, 18, 1416, 78), (25, 18, 29, 226), GOLD, 2)
txt(44, 30, "灰烬与冻土的边境 · 格子探索", F24, GOLD_HI)
txt(44, 62, "连续地表表现，逻辑网格驱动移动与巡逻", F16, TEXT)

# Logical 14×9 grid. It is intentionally subtle rather than a board-game frame.
cols, rows = 14, 9
cw, ch = 92, 64
x0, y0 = 48, 108
for r in range(rows):
    for c in range(cols):
        x, y = x0 + c * cw, y0 + r * ch
        d.rectangle((x, y, x + cw, y + ch), outline=(216, 190, 152, 28), width=1)

# Region labels on quiet parts of the scene.
rect((58, 104, 220, 136), (25, 18, 29, 190), (0, 0, 0, 0), 0)
txt(66, 112, "A · 灰烬镇", F16, GREEN)
rect((562, 104, 756, 136), (25, 18, 29, 190), (0, 0, 0, 0), 0)
txt(570, 112, "B · 旧墓道", F16, GOLD_HI)
rect((1050, 104, 1250, 136), (25, 18, 29, 190), (0, 0, 0, 0), 0)
txt(1058, 112, "C · 冻土关隘", F16, PURPLE)

# Key cells: a walkable route, player, patrol, trap and boss.
def cell_box(c, r):
    x, y = x0 + c * cw, y0 + r * ch
    return (x + 3, y + 3, x + cw - 3, y + ch - 3)

# Legal movement cells around the player.
for c, r in [(3, 5), (5, 5), (4, 4), (4, 6)]:
    rect(cell_box(c, r), (58, 98, 104, 42), BLUE, 2)

# Chest and rest point remain visible on the same continuous ground.
for c, r, label, color in [(2, 5, "宝箱", GOLD_HI), (1, 5, "休整", GREEN), (3, 1, "商店", BLUE)]:
    rect(cell_box(c, r), (45, 34, 39, 120), color, 2)
    x, y = x0 + c * cw + 8, y0 + r * ch + 4
    txt(x, y, label, F14, color)

# Player at col4,row5.
px, py = x0 + 4 * cw, y0 + 5 * ch
sprite("assets/characters/char/idle_01.png", (px + 16, py - 8, px + 68, py + 48))
rect(cell_box(4, 5), (0, 0, 0, 0), BLUE, 3)
txt(px + 18, py + 46, "你", F14, BLUE)

# Patrol monster at col5,row5; next step goes left to trap at col4,row5.
mx, my = x0 + 5 * cw, y0 + 5 * ch
sprite("assets/characters/a1_elite_brute_ice/idle_01.png", (mx + 14, my - 10, mx + 70, my + 48))
rect(cell_box(5, 5), (0, 0, 0, 0), RED, 2)
txt(mx + 4, my + 46, "巡逻", F14, RED)

# Trap icon at col4,row5, next cell of the patrol.
tx, ty = x0 + 4 * cw, y0 + 5 * ch
for i in range(4):
    xx = tx + 10 + i * 13
    d.polygon([(xx, ty + 35), (xx + 6, ty + 17), (xx + 12, ty + 35)], fill=GOLD_HI)
txt(tx + 6, ty + 44, "破甲陷阱", F12, RED)

# Patrol preview arrow, kept on the road.
d.line((mx + 8, my - 12, px + 70, my - 12), fill=GOLD_HI, width=3)
d.polygon([(px + 70, my - 20), (px + 56, my - 12), (px + 70, my - 4)], fill=GOLD_HI)
txt(mx - 26, my - 44, "下一步", F14, GOLD_HI)

# Boss is visible at the gate, not hidden behind a dice roll.
bx, by = x0 + 11 * cw, y0 + 1 * ch
sprite("assets/characters/frozen_urn/idle_01.png", (bx + 10, by - 8, bx + 74, by + 52))
txt(bx + 12, by + 48, "冰封铁瓮", F14, RED)

# Right information panel in a quiet sky area.
rect((1052, 156, 1394, 402), (28, 20, 33, 226), GOLD, 2)
txt(1072, 172, "回合制地图", F24, GOLD_HI)
txt(1072, 212, "你：移动或等待", F18, TEXT)
txt(1072, 246, "怪物：按预告巡逻", F18, TEXT)
txt(1072, 280, "陷阱：改变下一场战斗", F18, TEXT)
rect((1070, 322, 1376, 386), (51, 37, 48, 235), RED, 2)
txt(1084, 332, "选择等待 → 怪物踩中陷阱", F18, GOLD_HI)
txt(1084, 360, "转轮战斗开局破甲", F16, TEXT)

# Bottom instruction strip: no dice and no action-point economy.
rect((24, 746, 1416, 794), (25, 18, 29, 226), DIM, 1)
center((24, 746, 1416, 794), "地图保留概念图氛围；格子只负责碰撞、移动、巡逻和镜头，不把地表切成棋盘", F16, TEXT)

base.convert("RGB").save(OUT)
print(OUT)
