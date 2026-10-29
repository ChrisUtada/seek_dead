#!/usr/bin/env python3
"""Seek Dead 美术后处理管道（M0-03 固化）。

能力：
  palette  渲染主色板预览图
  normalize  AI 候选图 -> 去背景 / 量化 / 整数归一到目标画布 / 锚点对齐
  check    规格检查（尺寸 / RGBA / 透明 / 板外色 / 色数 / 包围盒 / 脚底 / 居中）并输出 JSON
  sheet    同批 contact sheet（1x 可辨 / 3x 细节 / 纯黑剪影）

依赖：Python 3.10+、Pillow。无其他第三方依赖。

示例：
  python tools/art_pipeline/pipeline.py palette --out docs/M0-03/palette_v3.png
  python tools/art_pipeline/pipeline.py normalize raw/hero.png out/hero_idle.png --mode sprite48
  python tools/art_pipeline/pipeline.py check assets/characters/char/idle_01.png --mode sprite48 --json out.json
  python tools/art_pipeline/pipeline.py sheet --out docs/M0-03/sheet.png --items a.png b.png c.png

规范见 docs/M0-03_美术规范.md；色板见 tools/art_pipeline/palette.json。
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PIPELINE_DIR = Path(__file__).resolve().parent
PALETTE_PATH = PIPELINE_DIR / "palette.json"

MODES = {
    #  画布      色数上限键   锚点
    "sprite48": ((48, 48), "sprite48", "bottom"),
    "boss96":   ((96, 96), "boss96", "bottom"),
    "icon24":   ((24, 24), "icon24", "center"),
    "icon16":   ((16, 16), "icon16", "center"),
}


# ---------------------------------------------------------------- 色板 / 工具

def load_palette():
    data = json.loads(PALETTE_PATH.read_text(encoding="utf-8"))
    colors = []
    for c in data["colors"]:
        h = c["hex"].lstrip("#")
        colors.append((c["name"], (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))))
    return data, colors


def parse_canvas(text: str) -> tuple[int, int]:
    w, h = text.lower().split("x")
    return int(w), int(h)


def resolve_mode(args):
    """返回 (canvas, max_colors, anchor)。显式参数覆盖 mode 预设。"""
    canvas, limit_key, anchor = MODES[args.mode]
    data, _ = load_palette()
    if args.canvas:
        canvas = parse_canvas(args.canvas)
    if args.max_colors is not None:
        max_colors = args.max_colors
    else:
        max_colors = data["limits"][limit_key]
    if args.anchor:
        anchor = args.anchor
    return canvas, max_colors, anchor


def parse_hex(text: str):
    h = text.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


# ---------------------------------------------------------------- 图像处理

def remove_background(im: Image.Image, mode: str, tol: int) -> Image.Image:
    """mode: auto（取四角众数色）/ none / #RRGGBB 抠色。"""
    im = im.convert("RGBA")
    if mode == "none":
        return im
    alpha = im.getchannel("A")
    if alpha.getextrema()[0] < 255:
        return im  # 已带透明通道，交给后续阈值处理
    w, h = im.size
    px = im.load()
    if mode == "auto":
        samples = [px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1]]
        key = max(set(samples), key=samples.count)
    else:
        key = parse_hex(mode)
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            if abs(r - key[0]) <= tol and abs(g - key[1]) <= tol and abs(b - key[2]) <= tol:
                px[x, y] = (0, 0, 0, 0)
    return im


def harden_alpha(im: Image.Image, threshold: int) -> Image.Image:
    """像素风只允许全透明 / 全不透明，消除抗锯齿半透明边。"""
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            px[x, y] = (0, 0, 0, 0) if a < threshold else (r, g, b, 255)
    return im


def quantize_to_palette(im: Image.Image, palette, keep_colors: bool = False) -> Image.Image:
    """最近色量化到主色板。keep_colors=True 时仍量化，但不裁减（由 check 报板外色）。"""
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    cache: dict[tuple, tuple] = {}
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            rgb = (r, g, b)
            hit = cache.get(rgb)
            if hit is None:
                hit = min(
                    palette,
                    key=lambda c: (c[1][0] - r) ** 2 * 0.299
                    + (c[1][1] - g) ** 2 * 0.587
                    + (c[1][2] - b) ** 2 * 0.114,
                )[1]
                cache[rgb] = hit
            px[x, y] = hit + (255,)
    return im


def fit_to_canvas(im: Image.Image, canvas: tuple[int, int]) -> tuple[Image.Image, list[str]]:
    """裁到包围盒，按整数倍放大；过大则最近邻缩到能放下。返回 (图, 警告)。"""
    warns: list[str] = []
    bbox = im.getbbox()
    if not bbox:
        return Image.new("RGBA", canvas, (0, 0, 0, 0)), ["空白图（无可见像素）"]
    im = im.crop(bbox)
    cw, ch = canvas
    w, h = im.size
    if w > cw or h > ch:
        f = min(cw / w, ch / h)
        nw, nh = max(1, round(w * f)), max(1, round(h * f))
        warns.append(f"源图 {w}x{h} 大于画布，非整数缩小到 {nw}x{nh}（{f:.3f}x）——应回生成端出更小尺寸")
        im = im.resize((nw, nh), Image.NEAREST)
    else:
        f = min(cw // w, ch // h)
        if f >= 2:
            warns.append(f"源图 {w}x{h} 整数放大 {f}x 到 {w * f}x{h * f}")
            im = im.resize((w * f, h * f), Image.NEAREST)
    return im, warns


def anchor_into(im: Image.Image, canvas: tuple[int, int], anchor: str, pad_bottom: int) -> Image.Image:
    cw, ch = canvas
    w, h = im.size
    out = Image.new("RGBA", canvas, (0, 0, 0, 0))
    x = (cw - w) // 2
    if anchor == "bottom":
        y = ch - h - pad_bottom
    else:
        y = (ch - h) // 2
    out.alpha_composite(im, (x, y))
    return out


# ---------------------------------------------------------------- 检查

def image_metrics(im: Image.Image, palette_rgb: set) -> dict:
    rgba = im.convert("RGBA")
    w, h = rgba.size
    px = rgba.load()
    colors = set()
    off_palette = 0
    opaque = 0
    bbox = rgba.getbbox()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            opaque += 1
            colors.add((r, g, b))
            if (r, g, b) not in palette_rgb:
                off_palette += 1
    feet_gap = None
    center_offset = None
    bbox_fill = 0.0
    if bbox:
        bx0, by0, bx1, by1 = bbox
        feet_gap = h - by1
        center_offset = (bx0 + bx1) / 2 - w / 2
        bbox_fill = (bx1 - bx0) * (by1 - by0) / (w * h)
    return {
        "size": [w, h],
        "mode": im.mode,
        "bbox": list(bbox) if bbox else None,
        "opaque_pixels": opaque,
        "transparent_ratio": round(1 - opaque / (w * h), 3),
        "unique_colors": len(colors),
        "off_palette_pixels": off_palette,
        "off_palette_ratio": round(off_palette / opaque, 4) if opaque else 0.0,
        "feet_gap": feet_gap,
        "center_offset": round(center_offset, 2) if center_offset is not None else None,
        "bbox_fill": round(bbox_fill, 3),
    }


def check_one(path: Path, canvas, max_colors: int, palette_rgb: set) -> dict:
    fails: list[str] = []
    warns: list[str] = []
    try:
        im = Image.open(path)
    except Exception as exc:  # noqa: BLE001
        return {"file": str(path), "status": "FAIL", "fails": [f"无法打开：{exc}"], "warns": []}
    m = image_metrics(im, palette_rgb)
    if tuple(m["size"]) != tuple(canvas):
        fails.append(f"尺寸 {m['size']} != 目标 {list(canvas)}")
    if im.mode not in ("RGBA", "LA", "P"):
        warns.append(f"模式 {im.mode} 不是 RGBA（Godot 导入后需为 RGBA）")
    if m["bbox"] is None:
        fails.append("无可见像素")
    else:
        if m["unique_colors"] > max_colors:
            fails.append(f"色数 {m['unique_colors']} > 上限 {max_colors}")
        if m["off_palette_ratio"] > 0.05:
            fails.append(f"板外色占比 {m['off_palette_ratio']:.1%} > 5%")
        elif m["off_palette_pixels"]:
            warns.append(f"板外色 {m['off_palette_pixels']} 像素（≤5%，建议归一）")
        if m["transparent_ratio"] < 0.05:
            warns.append("透明像素过少，确认背景已处理")
        if canvas[0] == canvas[1] and canvas[0] >= 48:
            if m["feet_gap"] is not None and m["feet_gap"] > 1:
                warns.append(f"脚底离画布底 {m['feet_gap']}px（角色类应 0–1px）")
            if m["center_offset"] is not None and abs(m["center_offset"]) > 1:
                warns.append(f"水平中心偏移 {m['center_offset']}px（应 ≤1px）")
        if canvas[0] <= 24 and m["bbox_fill"] < 0.25:
            fails.append(f"图标主体占比 {m['bbox_fill']:.0%} < 25%，小尺寸下会糊")
    return {
        "file": str(path),
        "status": "FAIL" if fails else "PASS",
        "metrics": m,
        "fails": fails,
        "warns": warns,
    }


# ---------------------------------------------------------------- 渲染

def font(size: int):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:  # Pillow < 10
        return ImageFont.load_default()


def cmd_palette(args):
    data, palette = load_palette()
    cell_w, cell_h = 220, 44
    cols = 4
    rows = (len(palette) + cols - 1) // cols
    img = Image.new("RGB", (cols * cell_w + 16, rows * cell_h + 32), parse_hex("#160D13"))
    d = ImageDraw.Draw(img)
    f, fs = font(11), font(9)
    d.text((8, 6), f"Seek Dead palette v{data['version']} · {len(palette)} colors",
           fill=parse_hex("#E2D7BD"), font=f)
    for i, (name, rgb) in enumerate(palette):
        cx = 8 + (i % cols) * cell_w
        cy = 28 + (i // cols) * cell_h
        d.rectangle([cx, cy, cx + 26, cy + 26], fill=rgb, outline=parse_hex("#E2D7BD"))
        d.text((cx + 34, cy), name, fill=parse_hex("#E2D7BD"), font=f)
        d.text((cx + 34, cy + 14), "#%02X%02X%02X" % rgb, fill=parse_hex("#A99D89"), font=fs)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print(f"palette -> {out} ({len(palette)} colors)")


def cmd_normalize(args):
    data, palette = load_palette()
    palette_rgb = {c[1] for c in palette}
    canvas, max_colors, anchor = resolve_mode(args)
    im = Image.open(args.src)
    im = remove_background(im, args.bg, args.bg_tolerance)
    im = harden_alpha(im, args.alpha_threshold)
    im, warns = fit_to_canvas(im, canvas)
    im = quantize_to_palette(im, palette)
    im = anchor_into(im, canvas, anchor, args.pad_bottom)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    im.save(out)
    for w in warns:
        print(f"WARN {w}")
    rep = check_one(out, canvas, max_colors, palette_rgb)
    print(json.dumps(rep, ensure_ascii=False, indent=2))
    return 0 if rep["status"] == "PASS" else 1


def cmd_check(args):
    data, palette = load_palette()
    palette_rgb = {c[1] for c in palette}
    canvas, max_colors, _ = resolve_mode(args)
    paths = [Path(p) for p in args.files]
    reports = [check_one(p, canvas, max_colors, palette_rgb) for p in paths]
    for r in reports:
        mark = "PASS" if r["status"] == "PASS" else "FAIL"
        print(f"[{mark}] {r['file']}")
        for f in r.get("fails", []):
            print(f"  x {f}")
        for w in r.get("warns", []):
            print(f"  ! {w}")
    if args.json:
        out = Path(args.json)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(reports, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"json -> {out}")
    return 0 if all(r["status"] == "PASS" for r in reports) else 1


def cmd_sheet(args):
    data, palette = load_palette()
    bg = parse_hex(args.bg)
    paths = [Path(p) for p in args.items]
    if not paths:
        print("sheet 需要 --items", file=sys.stderr)
        return 2
    scale = args.scale
    pad = 10
    label_w = 120
    cells = []
    for p in paths:
        im = Image.open(p).convert("RGBA")
        sil = None
        if args.silhouette:
            sil = Image.new("RGBA", im.size, (0, 0, 0, 0))
            sil.paste((0, 0, 0, 255), (0, 0), im.split()[3])
        cells.append((p, im, sil))
    big_w = max(im.width for _, im, _ in cells) * scale
    cols = 1 + (1 if args.one_x else 0) + (1 if args.silhouette else 0)
    sheet_w = label_w + cols * (big_w + pad) + pad
    sheet_h = 24 + sum(im.height * scale + pad * 2 for _, im, _ in cells)
    img = Image.new("RGB", (sheet_w, max(sheet_h, 60)), bg)
    d = ImageDraw.Draw(img)
    f, fs = font(10), font(9)
    d.text((8, 4), f"contact sheet · 1x / {scale}x{' / silhouette' if args.silhouette else ''}",
           fill=parse_hex("#E2D7BD"), font=f)
    y = 24
    for p, im, sil in cells:
        row_h = im.height * scale + pad * 2
        d.text((8, y + 4), p.name[:20], fill=parse_hex("#E2D7BD"), font=f)
        d.text((8, y + 16), f"{im.width}x{im.height}", fill=parse_hex("#A99D89"), font=fs)
        x = label_w
        if args.one_x:
            img.paste(im, (x, y + pad), im)
            x += big_w + pad
        big = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
        img.paste(big, (x, y + pad), big)
        x += big_w + pad
        if sil is not None:
            sbig = sil.resize((sil.width * scale, sil.height * scale), Image.NEAREST)
            img.paste(sbig, (x, y + pad), sbig)
        y += row_h
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print(f"sheet -> {out} ({len(cells)} items, {img.width}x{img.height})")
    return 0


# ---------------------------------------------------------------- CLI

def main(argv=None):
    ap = argparse.ArgumentParser(description="Seek Dead 美术后处理管道")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("palette", help="渲染主色板预览")
    p.add_argument("--out", required=True)
    p.set_defaults(func=cmd_palette)

    def add_mode_args(sp):
        sp.add_argument("--mode", default="sprite48", choices=sorted(MODES))
        sp.add_argument("--canvas", help="覆盖画布，如 48x48")
        sp.add_argument("--max-colors", type=int, default=None)
        sp.add_argument("--anchor", choices=["bottom", "center"], default=None)

    n = sub.add_parser("normalize", help="候选图 -> 入库图")
    n.add_argument("src")
    n.add_argument("out")
    add_mode_args(n)
    n.add_argument("--bg", default="auto", help="auto / none / #RRGGBB")
    n.add_argument("--bg-tolerance", type=int, default=24)
    n.add_argument("--alpha-threshold", type=int, default=96)
    n.add_argument("--pad-bottom", type=int, default=0)
    n.set_defaults(func=cmd_normalize)

    c = sub.add_parser("check", help="规格检查")
    c.add_argument("files", nargs="+")
    add_mode_args(c)
    c.add_argument("--json", help="输出 JSON 报告路径")
    c.set_defaults(func=cmd_check)

    s = sub.add_parser("sheet", help="contact sheet")
    s.add_argument("--out", required=True)
    s.add_argument("--items", nargs="+", required=True)
    s.add_argument("--scale", type=int, default=3)
    s.add_argument("--bg", default="#160D13")
    s.add_argument("--silhouette", action="store_true")
    s.add_argument("--no-one-x", dest="one_x", action="store_false", default=True)
    s.set_defaults(func=cmd_sheet)

    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
