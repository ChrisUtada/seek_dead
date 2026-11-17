"""按网格切 UI 图集，并输出带坐标的索引图（便于人工认出哪片是角/边/中心）。

很多 itch 素材包给的是 32×32 的 tilesheet，不是独立 PNG；九宫格拼接需要先切出
「左上角 / 上边 / 右上角 / 左边 / 中心 / 右边 / 左下 / 下边 / 右下」这九片。

用法：
    py -3.15 tools/slice_ui_sheet.py <图集.png> [--grid 32] [--out assets/ui/dark_ages]
输出：
    <out>/tile_r<行>_c<列>.png    每片独立 PNG（跳过全透明）
    <out>/_index.png              带行列号的索引图，4× 放大
"""
import sys
import os
from PIL import Image, ImageDraw


def main():
    if len(sys.argv) < 2:
        print('用法: py -3.15 tools/slice_ui_sheet.py <图集.png> [--grid 32] [--out 目录]')
        return
    src_path = sys.argv[1]
    grid = 32
    out_dir = 'assets/ui/dark_ages'
    if '--grid' in sys.argv:
        grid = int(sys.argv[sys.argv.index('--grid') + 1])
    if '--out' in sys.argv:
        out_dir = sys.argv[sys.argv.index('--out') + 1]

    im = Image.open(src_path).convert('RGBA')
    os.makedirs(out_dir, exist_ok=True)
    cols, rows = im.width // grid, im.height // grid
    print('图集 %dx%d → %d 列 × %d 行（每片 %dpx）' % (im.width, im.height, cols, rows, grid))

    kept = []
    for r in range(rows):
        for c in range(cols):
            tile = im.crop((c * grid, r * grid, (c + 1) * grid, (r + 1) * grid))
            if tile.getbbox() is None:
                continue
            name = 'tile_r%d_c%d.png' % (r, c)
            tile.save(os.path.join(out_dir, name))
            kept.append((r, c, tile))
    print('切出 %d 片（跳过空片）→ %s' % (len(kept), out_dir))

    # 索引图：每片放大 4×，左上角标行列号
    Z = 4
    cell = grid * Z
    label_h = 12
    idx = Image.new('RGBA', (cols * cell, rows * (cell + label_h)), (30, 20, 28, 255))
    d = ImageDraw.Draw(idx)
    for r, c, tile in kept:
        big = tile.resize((cell, cell), Image.NEAREST)
        x, y = c * cell, r * (cell + label_h) + label_h
        idx.alpha_composite(big, (x, y))
        d.text((x + 2, y - label_h + 1), 'r%d c%d' % (r, c), fill=(230, 210, 170, 255))
    idx_path = os.path.join(out_dir, '_index.png')
    idx.save(idx_path)
    print('索引图:', idx_path)


if __name__ == '__main__':
    main()
