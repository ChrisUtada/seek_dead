"""从 gold_frame_plum 母版派生出"窄边条"版本：四边只保留菱形格纹装饰，中腔全空。

母版 96x96 的问题：四角卷草花饰向内延伸到 15px，而实际边条只有 11px 厚。
所以把边条外侧的卷草区域整体剔除，只留 11px 素边条 —— 中腔必然干净。

输出尺寸按"可整除平铺"反推：
    内腔段 66x50，加两侧边条 11 -> 88x72
    ReelPanel 目标 154x72 -> 横向 132/66 = 2 次平铺，纵向 50/50 = 1 次，无缝。

用法:
    py -3.15 tools/make_band_frame.py
"""
import os

from PIL import Image

SRC = "assets/ui/dark_ages/frames/gold_frame_plum.png"
OUT_DIR = "assets/ui/dark_ages/frames"
T = 11          # 边条厚度（实测：中心行/列 0..10 为边框）
IW = 66         # 横向内腔段长 = 81 - 15
IH = 50         # 纵向内腔段长（取 15..65，避开母版卷草）


def make(src_path, out_name, color=None):
    src = Image.open(src_path).convert("RGBA")
    W, H = IW + 2 * T, IH + 2 * T
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))

    # 四角：母版 11x11 格纹转角（不含卷草）
    out.paste(src.crop((0, 0, T, T)), (0, 0))
    out.paste(src.crop((96 - T, 0, 96, T)), (W - T, 0))
    out.paste(src.crop((0, 96 - T, T, 96)), (0, H - T))
    out.paste(src.crop((96 - T, 96 - T, 96, 96)), (W - T, H - T))

    # 四边：取母版边条中段（15..81），长度正好等于内腔段
    out.paste(src.crop((15, 0, 15 + IW, T)), (T, 0))
    out.paste(src.crop((15, 96 - T, 15 + IW, 96)), (T, H - T))
    out.paste(src.crop((0, 15, T, 15 + IH)), (0, T))
    out.paste(src.crop((96 - T, 15, 96, 15 + IH)), (W - T, T))

    if color:
        r, g, b = color
        px = list(out.getdata())
        out = Image.frombytes("RGBA", out.size,
                              b"".join(bytes((r, g, b, p[3])) for p in px))

    p = os.path.join(OUT_DIR, out_name)
    out.save(p)
    print(f"{p}  {W}x{H}  margin={T}  inner={IW}x{IH}")
    return p


if __name__ == "__main__":
    make(SRC, "frame_band_plum.png")
