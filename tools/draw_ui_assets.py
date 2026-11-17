"""UI 像素资产 v4：参照用户给的参考图重画。
要点：装饰性轨道（断口+宝石点缀）、凸起转轮面板+顶部徽饰、菱形角钉、尖头红幅。
"""
import os
from PIL import Image, ImageDraw

OUT = 'assets/ui'
os.makedirs(OUT, exist_ok=True)

K  = (9, 5, 8, 255)
B3 = (240, 216, 160, 255)   # 金·亮
B2 = (186, 146, 92, 255)    # 金·中
B1 = (112, 80, 52, 255)     # 金·暗
P3 = (66, 44, 58, 255)      # 面板亮
P2 = (44, 28, 38, 255)      # 面板
P1 = (34, 20, 30, 255)      # 面板深
R2 = (170, 56, 48, 255)
R1 = (108, 30, 30, 255)
GEM = (232, 138, 52, 255)   # 琥珀宝石
GEM_D = (146, 74, 24, 255)


def rect(d, x0, y0, x1, y1, c):
    if x1 < x0 or y1 < y0:
        return
    d.rectangle([x0, y0, x1, y1], fill=c)


def diamond(d, cx, cy, c=GEM, cd=GEM_D):
    """3×3 菱形宝石。"""
    d.point((cx, cy - 1), fill=c)
    d.point((cx - 1, cy), fill=c)
    d.point((cx, cy), fill=c)
    d.point((cx + 1, cy), fill=c)
    d.point((cx, cy + 1), fill=c)
    d.point((cx, cy + 1), fill=cd)


def corner_gem(d, x, y, c=B3):
    """角部小菱形钉（比铆钉更精致）。"""
    d.point((x, y), fill=c)
    d.point((x + 1, y), fill=c)
    d.point((x, y + 1), fill=c)
    d.point((x + 1, y + 1), fill=B2)


def rail(d, x0, x1, y, gems=None):
    """一条装饰轨道：黑 / 亮 / 中 / 暗 四层，每 16px 收一个断口，断口处放宝石。"""
    rect(d, x0, y, x1, y, K)
    rect(d, x0, y + 1, x1, y + 1, B3)
    rect(d, x0, y + 2, x1, y + 2, B2)
    rect(d, x0, y + 3, x1, y + 3, B1)
    rect(d, x0, y + 4, x1, y + 4, K)
    # 断口：每 16px 挖 2px 缺口，读起来像锻造接缝
    for nx in range(x0 + 60, x1 - 12, 60):
        rect(d, nx, y, nx + 1, y + 4, K)
        rect(d, nx, y + 1, nx + 1, y + 2, B2)
    if gems:
        for gx in gems:
            diamond(d, gx, y + 2)


def make_slot(size=30):
    im = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    rect(d, 0, 0, size - 1, size - 1, K)
    rect(d, 1, 1, size - 2, size - 2, B2)
    rect(d, 2, 2, size - 3, size - 3, P1)
    d.line([2, size - 3, size - 3, size - 3], fill=P3)
    # 上左亮、下右暗
    d.line([1, 1, size - 2, 1], fill=B3)
    d.line([1, 1, 1, size - 2], fill=B3)
    d.line([1, size - 2, size - 2, size - 2], fill=B1)
    d.line([size - 2, 1, size - 2, size - 2], fill=B1)
    # 四角小菱形钉
    for (gx, gy) in ((2, 2), (size - 4, 2), (2, size - 4), (size - 4, size - 4)):
        corner_gem(d, gx, gy)
    return im


def make_reel_panel(w=124, h=52):
    """凸起的转轮面板：外框更厚，顶部中央一个小徽饰。"""
    im = Image.new('RGBA', (w, h + 6), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    top = 6
    rect(d, 1, top, w - 2, h + top - 1, K)
    rect(d, 2, top + 1, w - 3, h + top - 2, B2)
    rect(d, 3, top + 2, w - 4, h + top - 3, P1)
    d.line([3, h + top - 3, w - 4, h + top - 3], fill=P3)
    d.line([2, top + 1, w - 3, top + 1], fill=B3)
    d.line([2, top + 1, 2, h + top - 2], fill=B3)
    d.line([2, h + top - 2, w - 3, h + top - 2], fill=B1)
    d.line([w - 3, top + 1, w - 3, h + top - 2], fill=B1)
    # 顶部徽饰：中央小拱 + 宝石
    rect(d, w // 2 - 10, top - 8, w // 2 + 10, top + 1, K)
    rect(d, w // 2 - 9, top - 7, w // 2 + 9, top, B2)
    rect(d, w // 2 - 8, top - 6, w // 2 + 8, top - 1, B3)
    rect(d, w // 2 - 7, top - 5, w // 2 + 7, top - 1, P2)
    diamond(d, w // 2, top - 3)
    # 两侧小角
    for sx in (w // 2 - 16, w // 2 + 16):
        corner_gem(d, sx - 1, top - 3)
    return im


def make_spin(w=100, h=24):
    im = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # 尖头红幅：左右各内收 4px 形成箭头端
    for x in range(w):
        inset = max(0, 4 - min(x, w - 1 - x))
        if x < 4:
            inset = 4 - x - 1 if x < 4 else 0
    def span(x):
        return 2 if (x < 2 or x >= w - 2) else (1 if (x < 4 or x >= w - 4) else 0)
    for x in range(w):
        s = span(x)
        rect(d, x, s, x, h - 1 - s, K)
    for x in range(1, w - 1):
        s = span(x) + 1
        rect(d, x, s, x, h - 1 - s, R1)
    for x in range(1, w - 1):
        s = span(x) + 1
        rect(d, x, s, x, h - 1 - s - 3, R2)
    # 上下金边（跟随尖角）
    for x in range(1, w - 1):
        s = span(x) + 1
        d.point((x, s), fill=B2)
        d.point((x, h - 1 - s), fill=B2)
        d.point((x, s + 1), fill=B3)
    # 中央高光横线
    d.line([8, h // 2 - 4, w - 9, h // 2 - 4], fill=(214, 96, 80, 255))
    return im


def make_band(w=480, h=72):
    im = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    rect(d, 0, 0, w - 1, h - 1, P2)
    rail(d, 0, w - 1, 0, gems=[w // 2])
    rail(d, 0, w - 1, h - 5)
    # 左右竖封边
    for x in (0, w - 1):
        d.line([x, 5, x, h - 6], fill=K)
    for x in (1, w - 2):
        d.line([x, 6, x, h - 7], fill=B1)
    # 内侧抖动带，压出凹陷
    for x in range(2, w - 2):
        if x % 2 == 0:
            d.point((x, 6), fill=(58, 38, 48, 255))
    return im


def make_gold_box(w=34, h=30):
    im = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    rect(d, 0, 0, w - 1, h - 1, K)
    rect(d, 1, 1, w - 2, h - 2, B2)
    rect(d, 2, 2, w - 3, h - 3, P1)
    d.line([1, 1, w - 2, 1], fill=B3)
    d.line([1, 1, 1, h - 2], fill=B3)
    d.line([1, h - 2, w - 2, h - 2], fill=B1)
    d.line([w - 2, 1, w - 2, h - 2], fill=B1)
    for (gx, gy) in ((2, 2), (w - 4, 2), (2, h - 4), (w - 4, h - 4)):
        corner_gem(d, gx, gy)
    return im


slot = make_slot(30)
reel = make_reel_panel(124, 44)
spin = make_spin(100, 24)
band = make_band(480, 72)
gold = make_gold_box(34, 30)
slot.save('%s/slot_frame.png' % OUT)
reel.save('%s/reel_panel.png' % OUT)
spin.save('%s/spin_banner.png' % OUT)
band.save('%s/bar_band.png' % OUT)
gold.save('%s/gold_box.png' % OUT)

# 合成预览：模仿参考图排布
pv = Image.new('RGBA', (480, 104), (16, 10, 16, 255))
pv.alpha_composite(band, (0, 20))
x = 14
for i in range(5):
    pv.alpha_composite(slot, (x, 34)); x += 32
pv.alpha_composite(reel, (176, 18))          # 上凸 8px
pv.alpha_composite(spin, (188, 72))          # 挂在面板下沿
x = 304
for i in range(4):
    pv.alpha_composite(slot, (x, 34)); x += 32
pv.alpha_composite(gold, (428, 34))
pv = pv.resize((pv.width * 2, pv.height * 2), Image.NEAREST)
pv.save('.workbuddy/shots/ui_v4.png')
print('v4 ok')
