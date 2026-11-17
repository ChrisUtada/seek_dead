"""预览 Kenney Fantasy UI Borders 在游戏真实尺寸下的染色与九宫格效果。

用法:
    py -3.15 tools/preview_kenney_borders.py --zip C:/Users/chris/Downloads/kenney_fantasy-ui-borders.zip

输出: assets/ui/_preview/kenney_test.png（2 倍放大便于目视）

素材是纯白 + 全透明两色、无抗锯齿，所以染色是零损失的：
直接把 RGB 换成目标色，alpha 原样保留。
"""
import argparse
import io
import os
import zipfile

from PIL import Image, ImageDraw

INK = (29, 18, 25, 255)          # 主题 bg_color 深紫褐
TXT = (226, 215, 189, 255)       # 主题 font_color 米黄

COLORS = [
    ("muted beige 169,157,137", (169, 157, 137)),
    ("warm gold 214,178,106", (214, 178, 106)),
    ("cold teal 140,158,160", (140, 158, 160)),
]


def load_sheet(zip_path, folder, ext="png"):
    out = {}
    with zipfile.ZipFile(zip_path) as z:
        for n in z.namelist():
            if n.startswith(folder) and n.endswith("." + ext):
                out[os.path.basename(n)] = Image.open(io.BytesIO(z.read(n))).convert("RGBA")
    return out


def recolor(img, color):
    r, g, b = color
    px = list(img.getdata())
    return Image.new("RGBA", img.size, (0, 0, 0, 0)) if False else Image.frombytes(
        "RGBA", img.size, b"".join(bytes((r, g, b, p[3])) for p in px)
    )


def slice9(src, w, h, m, tile=True):
    """m 为九宫格 margin。

    tile=True  1:1 角块 + 平铺边与中腔（Godot axis_stretch = TILE_FIT）
    tile=False 1:1 角块 + 拉伸边与中腔（Godot 默认 STRETCH，游戏实际用法）
    """
    iw, ih = src.size
    if w < 2 * m + 1 or h < 2 * m + 1:
        return src.resize((w, h), Image.NEAREST)
    dst = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dst.paste(src.crop((0, 0, m, m)), (0, 0))
    dst.paste(src.crop((iw - m, 0, iw, m)), (w - m, 0))
    dst.paste(src.crop((0, ih - m, m, ih)), (0, h - m))
    dst.paste(src.crop((iw - m, ih - m, iw, ih)), (w - m, h - m))
    cw, ch = iw - 2 * m, ih - 2 * m
    if not tile:
        dst.paste(src.crop((m, 0, iw - m, m)).resize((w - 2 * m, m), Image.NEAREST), (m, 0))
        dst.paste(src.crop((m, ih - m, iw - m, ih)).resize((w - 2 * m, m), Image.NEAREST), (m, h - m))
        dst.paste(src.crop((0, m, m, ih - m)).resize((m, h - 2 * m), Image.NEAREST), (0, m))
        dst.paste(src.crop((iw - m, m, iw, ih - m)).resize((m, h - 2 * m), Image.NEAREST), (w - m, m))
        dst.paste(src.crop((m, m, iw - m, ih - m)).resize((w - 2 * m, h - 2 * m), Image.NEAREST), (m, m))
        return dst
    for x in range(m, w - m):
        sx = m + ((x - m) % cw)
        dst.paste(src.crop((sx, 0, sx + 1, m)), (x, 0))
        dst.paste(src.crop((sx, ih - m, sx + 1, ih)), (x, h - m))
    for y in range(m, h - m):
        sy = m + ((y - m) % ch)
        dst.paste(src.crop((0, sy, m, sy + 1)), (0, y))
        dst.paste(src.crop((iw - m, sy, iw, sy + 1)), (w - m, y))
    for y in range(m, h - m):
        sy = m + ((y - m) % ch)
        for x in range(m, w - m):
            sx = m + ((x - m) % cw)
            dst.paste(src.crop((sx, sy, sx + 1, sy + 1)), (x, y))
    return dst


DATASETS = [
    # (标题, 目标宽高, [(标签, 文件, margin)], 是否画图标)
    ("A  slot 42x42", 42, 42,
     [("015 m2", "panel-border-015.png", 2),
      ("004 m8", "panel-border-004.png", 8)], True),
    ("B  reel window 154x72", 154, 72,
     [("002 m12", "panel-border-002.png", 12),
      ("010 m10", "panel-border-010.png", 10),
      ("019 m12", "panel-border-019.png", 12),
      ("006 m12", "panel-border-006.png", 12)], False),
    ("C  overlay 200x130", 200, 130,
     [("020 m20", "panel-border-020.png", 20),
      ("025 m20", "panel-border-025.png", 20),
      ("018 m14", "panel-border-018.png", 14)], False),
    ("D  composed 3-tone 240x130", 240, 130,
     [("004 + inner groove", "@c:panel-border-004.png", 8),
      ("020 + inner groove", "@c:panel-border-020.png", 20),
      ("025 + inner groove", "@c:panel-border-025.png", 20)], False),
]

FILL_TOP = (46, 32, 39)          # 面板填充（比底色亮一阶）
GROOVE = (26, 17, 22)            # 内嵌暗槽（比填充暗一阶，出凹陷感）


def compose_frame(borders, fname, m, w, h, hi):
    """亮外框 + 内嵌暗槽 + 深色填充，凑出三阶明暗。"""
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(out).rectangle([3, 3, w - 4, h - 4], fill=FILL_TOP)
    if "panel-border-015.png" in borders:
        groove = slice9(recolor(borders["panel-border-015.png"], GROOVE), w - 8, h - 8, 2)
        out.alpha_composite(groove, (4, 4))
    out.alpha_composite(slice9(recolor(borders[fname], hi), w, h, m), (0, 0))
    return out

SCALE = 2
PAD = 10
LABEL_H = 14


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zip", required=True)
    ap.add_argument("--icon", default="assets/icons/weapons/cell/icon_cinder_saber_32.png")
    ap.add_argument("--out", default="assets/ui/_preview/kenney_test.png")
    a = ap.parse_args()

    borders = load_sheet(a.zip, "PNG/Default/Border/")
    panels = load_sheet(a.zip, "PNG/Default/Panel/")
    icon = Image.open(a.icon).convert("RGBA") if os.path.exists(a.icon) else None

    W = PAD + max(14 + len(d[3]) * (d[1] + PAD) for d in DATASETS)
    H = PAD
    for _, _, h, cands, _ in DATASETS:
        H += LABEL_H + len(COLORS) * (h + LABEL_H) + PAD
    canvas = Image.new("RGBA", (W, H), INK)
    d = ImageDraw.Draw(canvas)

    y = PAD
    for title, w, h, cands, with_icon in DATASETS:
        d.text((PAD, y), f"{title}   (Kenney, recolored, 9-slice tile)", fill=TXT)
        y += LABEL_H
        for cname, col in COLORS:
            x = PAD
            d.text((PAD, y + h // 2 - 4), cname.split()[0][:2], fill=(110, 105, 100))
            x += 14
            for label, fname, m in cands:
                if fname.startswith("@c:"):
                    real = fname[3:]
                    if real in borders:
                        frame = compose_frame(borders, real, m, w, h, col)
                    else:
                        frame = None
                elif fname in borders:
                    frame = slice9(recolor(borders[fname], col), w, h, m)
                else:
                    frame = None
                if frame is not None:
                    canvas.alpha_composite(frame, (x, y))
                    if with_icon and icon:
                        iw, ih = icon.size
                        canvas.alpha_composite(icon, (x + (w - iw) // 2, y + (h - ih) // 2))
                    d.text((x, y + h + 1), f"{label}  {cname.split()[1][:3]}", fill=(150, 145, 135))
                x += w + PAD
            y += h + LABEL_H
        y += PAD

    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    canvas.resize((W * SCALE, H * SCALE), Image.NEAREST).save(a.out)
    print("saved", a.out, canvas.size, "->", (W * SCALE, H * SCALE))


if __name__ == "__main__":
    main()
