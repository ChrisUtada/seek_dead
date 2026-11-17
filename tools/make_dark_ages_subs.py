"""重绘 4 个丢失的第三方 UI 素材（Dark Ages 风格，配色沿用 draw_ui_assets.py）。

背景：远端 UI 换皮引用了 assets/ui/dark_ages/frames/ 下 4 个素材，但该目录被
.gitignore 排除（第三方 license），本机没有副本导致 HUD preload 失败。本脚本按项目
现有的金/紫/铜配色体系重画同类替代素材，仅用于本机运行与截图验证。

注意：输出目录被 .gitignore 忽略，生成的 png 不会入库；本脚本会入库，方便复现。

输出 (assets/ui/dark_ages/frames/):
  slot_blue.png      32x32  margin 8   —— 槽位/转轮格空框
  thin_frame_a.png   96x96  margin 32  —— 分组框（细边框 + 大内腔）
  gold_frame_plum.png 96x96 margin 10  —— 华丽金框（紫底 + 描边 + 角饰）
  parchment.png      48x48  margin 8   —— 羊皮纸底（浅色内腔）

用法:
    py -3.15 tools/make_dark_ages_subs.py
"""
import os
from PIL import Image, ImageDraw

OUT = "assets/ui/dark_ages/frames"
os.makedirs(OUT, exist_ok=True)

# —— 配色：与 tools/draw_ui_assets.py v4 完全一致 ——
K = (9, 5, 8, 255)
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
PARCH = (224, 208, 176, 255)    # 羊皮纸亮
PARCH_D = (196, 176, 144, 255)  # 羊皮纸暗


def rect(d, x0, y0, x1, y1, c):
    if x1 < x0 or y1 < y0:
        return
    d.rectangle([x0, y0, x1, y1], fill=c)


def corner_gem(d, x, y, c=B3):
    d.point((x, y), fill=c)
    d.point((x + 1, y), fill=c)
    d.point((x, y + 1), fill=c)
    d.point((x + 1, y + 1), fill=B2)


def diamond(d, cx, cy, c=GEM, cd=GEM_D):
    d.point((cx, cy - 1), fill=c)
    d.point((cx - 1, cy), fill=c)
    d.point((cx, cy), fill=c)
    d.point((cx + 1, cy), fill=c)
    d.point((cx, cy + 1), fill=cd)


def bevel_frame(d, x0, y0, x1, y1, t=3):
    """通用多层斜角框：黑外框 -> 金中 -> 深紫内腔，上左亮/下右暗，四角菱形钉。"""
    rect(d, x0, y0, x1, y1, K)
    rect(d, x0 + 1, y0 + 1, x1 - 1, y1 - 1, B2)
    rect(d, x0 + 2, y0 + 2, x1 - 2, y1 - 2, P1)
    # 上左高光 / 下右暗边
    d.line([x0 + 1, y0 + 1, x1 - 1, y0 + 1], fill=B3)
    d.line([x0 + 1, y0 + 1, x0 + 1, y1 - 1], fill=B3)
    d.line([x0 + 1, y1 - 1, x1 - 1, y1 - 1], fill=B1)
    d.line([x1 - 1, y0 + 1, x1 - 1, y1 - 1], fill=B1)
    # 内腔底部一条微亮线，增加凹陷感
    d.line([x0 + 2, y1 - 2, x1 - 2, y1 - 2], fill=P3)
    for (gx, gy) in ((x0 + 2, y0 + 2), (x1 - 4, y0 + 2),
                     (x0 + 2, y1 - 4), (x1 - 4, y1 - 4)):
        corner_gem(d, gx, gy)


def make_slot_blue(size=32):
    """槽位空框：深紫内腔 + 金框 + 四角菱形钉。9-slice margin 8。"""
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bevel_frame(ImageDraw.Draw(im), 0, 0, size - 1, size - 1)
    return im


def make_thin_frame(size=96, m=32):
    """分组细框：宽内腔、细金边、四角小钉。margin 32 => 内腔 32x32。"""
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # 外框 3 层（薄）
    rect(d, 0, 0, size - 1, size - 1, K)
    rect(d, 1, 1, size - 2, size - 2, B2)
    rect(d, 2, 2, size - 3, size - 3, P1)
    d.line([1, 1, size - 2, 1], fill=B3)
    d.line([1, 1, 1, size - 2], fill=B3)
    d.line([1, size - 2, size - 2, size - 2], fill=B1)
    d.line([size - 2, 1, size - 2, size - 2], fill=B1)
    # margin 区内的角钉（不进内腔）
    for (gx, gy) in ((4, 4), (size - 6, 4), (4, size - 6), (size - 6, size - 6)):
        corner_gem(d, gx, gy)
    # 内腔边缘一圈微亮线（内腔本身透明）
    d.line([m, m, size - m - 1, m], fill=P3)
    d.line([m, m, m, size - m - 1], fill=P3)
    return im


def make_gold_frame_plum(size=96, m=10):
    """华丽金框：紫底 + 金描边 + 边缘菱形装饰。margin 10。"""
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    bevel_frame(d, 0, 0, size - 1, size - 1)
    # 沿四边中段的菱形节奏装饰（复古感来自像素边+铜金，不做大面积渐变）
    step = 14
    for x in range(m + step, size - m - step // 2, step):
        diamond(d, x, m - 3, B3, B2)
        diamond(d, x, size - m + 2, B3, B2)
    for y in range(m + step, size - m - step // 2, step):
        diamond(d, m - 3, y, B3, B2)
        diamond(d, size - m + 2, y, B3, B2)
    return im


def make_parchment(size=48, m=8):
    """羊皮纸底：浅米色内腔 + 暗铜窄边。margin 8。"""
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    rect(d, 0, 0, size - 1, size - 1, K)
    rect(d, 1, 1, size - 2, size - 2, B1)
    rect(d, 2, 2, size - 3, size - 3, PARCH_D)
    rect(d, 3, 3, size - 4, size - 4, PARCH)
    # 纸面轻微横向纹理（像素噪点，不模糊）
    for y in range(5, size - 5, 3):
        for x in range(5, size - 5, 7):
            d.point((x, y), fill=PARCH_D)
    # 上左高光
    d.line([2, 2, size - 3, 2], fill=B3)
    d.line([2, 2, 2, size - 3], fill=B3)
    return im


assets = {
    "slot_blue.png": make_slot_blue(32),
    "thin_frame_a.png": make_thin_frame(96, 32),
    "gold_frame_plum.png": make_gold_frame_plum(96, 10),
    "parchment.png": make_parchment(48, 8),
}
for name, im in assets.items():
    p = os.path.join(OUT, name)
    im.save(p)
    print("%-22s %s" % (name, im.size))

# 放大预览拼图，便于肉眼核对风格
pv = Image.new("RGBA", (400, 120), (16, 10, 16, 255))
x = 8
for name, im in assets.items():
    z = im.resize((im.width * 2, im.height * 2), Image.NEAREST)
    if x + z.width > 400:
        break
    pv.alpha_composite(z, (x, 8))
    x += z.width + 8
pv.save("D:/tmp_workbuddy/dark_ages_subs_preview.png")
print("preview -> D:/tmp_workbuddy/dark_ages_subs_preview.png")
