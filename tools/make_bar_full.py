"""重绘战斗底栏底图 bar_full.png（480×74），按运行时真实坐标对齐。

设计来源：用户参考图（整条深色金属底带 + 中央浅色转轮凸起 + 下方暗红 SPIN 挂牌）。
对齐依据：tools/probe_bottom.gd 读出的运行时矩形（480×270 逻辑分辨率）：
  - 普通槽位 30×30，中心 y=206..236（底图内 y=9..39，底图起点 y=197）
  - 转轮格 3×42×42，x=170/216/262，y=197..239（底图内 y=0..42）
  - SPIN 按钮 x=196..284, y=246..264（底图内 y=49..67，靠近转轮格）
  - 金币框（中轴校正后）中心 x=460, y=206..236
底图节点放在 (0,197)，尺寸 480×74。

改进（相对旧 480×65 底图）：
  1. 删除底带下沿连续链条/珠点装饰（方案§2 要删的脏装饰）
  2. 转轮内腔按 42px 格 / 46px 间距重画，与代码格子精确对齐
  3. 转轮格统一为深紫金框（与普通槽位一致）；SPIN 暗红挂牌更干净
  4. 只画固定框线，不画任何图标/文字

用法:
    py -3.15 tools/make_bar_full.py
输出: assets/ui/bar_full.png (覆盖; 备份 D:/tmp_workbuddy/bar_full.bak2.png)
"""
import os
from PIL import Image, ImageDraw

OUT = "assets/ui/bar_full.png"
BAK = "D:/tmp_workbuddy/bar_full.bak2.png"
W, H = 480, 74
BAR_Y = 197  # 底图节点在屏幕上的 y

# —— 配色（沿用 draw_ui_assets.py v4 + 参考图浅色内腔）——
K = (9, 5, 8, 255)
B3 = (240, 216, 160, 255)   # 金·亮
B2 = (186, 146, 92, 255)    # 金·中
B1 = (112, 80, 52, 255)     # 金·暗
P3 = (66, 44, 58, 255)      # 面板亮
P2 = (44, 28, 38, 255)      # 面板
P1 = (34, 20, 30, 255)      # 面板深
INNER = (240, 230, 216, 255)   # 转轮内腔 米白（参考图）
INNER_D = (214, 202, 186, 255) # 内腔暗部
R2 = (170, 56, 48, 255)
R1 = (108, 30, 30, 255)
GEM = (232, 138, 52, 255)
GEM_D = (146, 74, 24, 255)


def rect(d, x0, y0, x1, y1, c):
    if x1 < x0 or y1 < y0:
        return
    d.rectangle([x0, y0, x1, y1], fill=c)


def line_h(d, x0, x1, y, c):
    d.line([x0, y, x1, y], fill=c)


def line_v(d, x, y0, y1, c):
    d.line([x, y0, x, y1], fill=c)


def gem(d, cx, cy, c=GEM, cd=GEM_D):
    d.point((cx, cy - 1), fill=c)
    d.point((cx - 1, cy), fill=c)
    d.point((cx, cy), fill=c)
    d.point((cx + 1, cy), fill=c)
    d.point((cx, cy + 1), fill=cd)


def rivet(d, x, y):
    d.point((x, y), fill=B3)
    d.point((x + 1, y), fill=B2)
    d.point((x, y + 1), fill=B2)


def slot_frame(d, cx, cy, size=30):
    """普通槽位空框：深紫内腔 + 金框。"""
    x0, y0 = cx - size // 2, cy - size // 2
    x1, y1 = x0 + size - 1, y0 + size - 1
    rect(d, x0, y0, x1, y1, K)
    rect(d, x0 + 1, y0 + 1, x1 - 1, y1 - 1, B2)
    rect(d, x0 + 2, y0 + 2, x1 - 2, y1 - 2, P1)
    line_h(d, x0 + 1, x1 - 1, y0 + 1, B3)
    line_v(d, x0 + 1, y0 + 1, y1 - 1, B3)
    line_h(d, x0 + 1, x1 - 1, y1 - 1, B1)
    line_v(d, x1 - 1, y0 + 1, y1 - 1, B1)


def reel_cell(d, cx, cy, size=42):
    """转轮格：深紫内腔 + 金框（与普通槽位统一；用户 2026-11-17 嫌米白格丑）。"""
    x0, y0 = cx - size // 2, cy - size // 2
    x1, y1 = x0 + size - 1, y0 + size - 1
    rect(d, x0, y0, x1, y1, K)
    rect(d, x0 + 1, y0 + 1, x1 - 1, y1 - 1, B2)
    rect(d, x0 + 2, y0 + 2, x1 - 2, y1 - 2, P1)
    # 内腔底部一条微亮线，读出凹陷（与普通槽位一致）
    line_h(d, x0 + 2, x1 - 2, y1 - 2, P3)
    line_h(d, x0 + 1, x1 - 1, y0 + 1, B3)
    line_v(d, x0 + 1, y0 + 1, y1 - 1, B3)
    line_h(d, x0 + 1, x1 - 1, y1 - 1, B1)
    line_v(d, x1 - 1, y0 + 1, y1 - 1, B1)


def main():
    os.makedirs(os.path.dirname(BAK), exist_ok=True)
    if os.path.exists(OUT):
        Image.open(OUT).convert("RGBA").save(BAK)
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    # 屏幕 y -> 底图 y
    def by(screen_y):
        return screen_y - BAR_Y

    # —— 1. 底带主体条：y=206..236（屏幕），即底图内 y9..39 ——
    # 2026-11-17：左右各留 8px 空白，不紧贴画面边缘（x8..471）
    band_x0, band_x1 = 8, W - 9
    band_top, band_bot = by(206), by(236)
    # 上沿金属轨道（黑/亮/中/暗四层，2px）
    for dy, col in ((0, K), (1, B3), (2, B2), (3, B1)):
        line_h(d, band_x0, band_x1, band_top - 4 + dy, col)
    # 主体暗紫漆面
    rect(d, band_x0, band_top, band_x1, band_bot, P2)
    # 下沿金属轨道
    for i, col in enumerate((K, B1, B2)):
        line_h(d, band_x0, band_x1, band_bot + 1 + i, col)
    # 左右竖封边
    for x in (band_x0, band_x1):
        line_v(d, x, band_top, band_bot, K)
    for x in (band_x0 + 1, band_x1 - 1):
        line_v(d, x, band_top + 1, band_bot - 1, B1)

    # —— 2. 普通槽位空框：武器 y206、技能 y206、消耗品 y206、金币 y206 ——
    # 中轴校正（2026-11-17）：以 x=240 为真中心。左侧不动；消耗品右移2；金币右移5。
    # 武器 20/52, 技能 84/116/148, 消耗品 332/364/396/428, 金币 460（均与 battle_hud.gd 坐标表同步）
    # 屏幕中心 y = 221, 底图内 = 24
    sy = by(221)
    for cx in (20, 52, 84, 116, 148, 332, 364, 396, 428, 460):
        slot_frame(d, cx, sy, 30)
    # 少量铆钉：转轮区左右两侧的间隙中心（上/下各一颗）。
    # 左间隙=技能右缘163..转轮左缘173 -> x168；右间隙=转轮右缘307..消耗品左缘317 -> x312。
    # 之前右侧是 321，落在消耗品槽内部被框盖住，才显得"右边少了两颗铆钉"。
    for rx in (168, 312):
        rivet(d, rx, band_top + 1)
        rivet(d, rx, band_bot - 2)

    # —— 3. 中央转轮格：x=173..307, y=197..239（屏幕），底图内 y0..42 ——
    # 2026-11-17：去掉凸起底座铜框（用户嫌那圈高出槽位的框突兀），转轮格与两侧槽位平齐。
    # 3 个转轮格：中心 x=194/240/286（整体右移3，中轴 240）, 屏幕 y=218
    for cx in (194, 240, 286):
        reel_cell(d, cx, by(218), 42)

    # —— 4. SPIN 暗红挂牌：x=196..284, y=246..264（屏幕上移 6px，靠近转轮格）——
    sx0, sx1 = 192, 288
    sy0, sy1 = by(244), by(264)
    # 尖头横幅：左右内收 4px
    def span(x):
        if x < sx0 + 4:
            return sx0 + 4 - x
        if x > sx1 - 4:
            return x - (sx1 - 4)
        return 0
    for x in range(sx0, sx1 + 1):
        s = span(x)
        rect(d, x, sy0 + s, x, sy1 - s, K)
    for x in range(sx0 + 1, sx1):
        s = span(x)
        rect(d, x, sy0 + s + 1, x, sy1 - s - 1, R1)
    for x in range(sx0 + 1, sx1):
        s = span(x)
        rect(d, x, sy0 + s + 2, x, sy1 - s - 4, R2)
        d.point((x, sy0 + s + 1), fill=B2)
        d.point((x, sy1 - s - 1), fill=B2)
    # 中央高光横线（不画文字，文字由 SpinButton 控件叠加）
    line_h(d, sx0 + 10, sx1 - 10, sy0 + 6, (214, 96, 80, 255))

    im.save(OUT)
    print("saved", OUT, im.size)
    im.resize((W * 2, H * 2), Image.NEAREST).save("D:/tmp_workbuddy/bar_full_new2_zoom.png")


if __name__ == "__main__":
    main()
