"""九宫格参数可视化对照：拉伸 vs 平铺。

为什么需要这个工具：
  像素 UI 边框的边纹（编织、锁链、石砖）是「周期图案」，横向拉伸会把每个
  图案单元拽长，看起来就是「糊了 / 断了」。Godot 的 StyleBoxTexture 有
  axis_stretch_horizontal / vertical = TILE_FIT，可以把边纹重复而不是拉伸。
  光看数值推不出该用哪个，直接把两种做法渲染出来对比最快。

用法：
    py -3.15 tools/preview_9slice.py assets/ui/dark_ages/frames/gold_frame.png \
        --size 200 140 --margins 16 --margins 32 --tile

输出：
    .workbuddy/shots/9slice_<name>.png  （拉伸与平铺并排）
"""
import sys
import os
from PIL import Image, ImageDraw


def _blit_tiled(out, piece, box, tw, th):
    """把 piece 以 box 左上角为起点，在 tw×th 区域内重复贴。"""
    pw, ph = piece.size
    if pw <= 0 or ph <= 0:
        return
    x0, y0 = box
    for y in range(0, th, ph):
        for x in range(0, tw, pw):
            crop = piece.crop((0, 0, min(pw, tw - x), min(ph, th - y)))
            out.alpha_composite(crop, (x0 + x, y0 + y))


def nine_patch(src, tw, th, m, tile=False):
    """九宫格 9-slice。tile=True 时边纹与中心平铺（等价 Godot TILE_FIT）。"""
    w, h = src.size
    m = min(m, w // 2, h // 2)
    out = Image.new('RGBA', (tw, th), (0, 0, 0, 0))

    cw, ch = tw - 2 * m, th - 2 * m

    def put(box, size, pos, tiled=False):
        piece = src.crop(box)
        if tiled:
            _blit_tiled(out, piece, pos, size[0], size[1])
            return
        if piece.size != size:
            piece = piece.resize(size, Image.NEAREST)
        out.alpha_composite(piece, pos)

    put((0, 0, m, m), (m, m), (0, 0))
    put((w - m, 0, w, m), (m, m), (tw - m, 0))
    put((0, h - m, m, h), (m, m), (0, th - m))
    put((w - m, h - m, w, h), (m, m), (tw - m, th - m))

    put((m, 0, w - m, m), (cw, m), (m, 0), tile)
    put((m, h - m, w - m, h), (cw, m), (m, th - m), tile)
    put((0, m, m, h - m), (m, ch), (0, m), tile)
    put((w - m, m, w, h - m), (m, ch), (tw - m, m), tile)
    put((m, m, w - m, h - m), (cw, ch), (m, m), tile)
    return out


def main():
    path = sys.argv[1]
    tw = th = 0
    margins = []
    do_tile = '--tile' in sys.argv
    if '--size' in sys.argv:
        i = sys.argv.index('--size')
        tw, th = int(sys.argv[i + 1]), int(sys.argv[i + 2])
    if '--margins' in sys.argv:
        i = sys.argv.index('--margins')
        j = i + 1
        while j < len(sys.argv) and not sys.argv[j].startswith('--'):
            margins.append(int(sys.argv[j]))
            j += 1
    tw = tw or 60
    th = th or 40
    margins = margins or [4, 6, 8, 12]

    src = Image.open(path).convert('RGBA')
    Z = 3
    gap = 14
    cell_w, cell_h = tw * Z, th * Z
    modes = [False, True] if do_tile else [False]
    W = gap + len(margins) * (cell_w + gap)
    H = gap + len(modes) * (cell_h + 20 + gap)
    canvas = Image.new('RGBA', (W, H), (22, 15, 22, 255))
    d = ImageDraw.Draw(canvas)

    y = gap
    for mode in modes:
        x = gap
        for m in margins:
            img = nine_patch(src, tw, th, m, tile=mode)
            img = img.resize((cell_w, cell_h), Image.NEAREST)
            canvas.alpha_composite(img, (x, y))
            d.text((x + 2, y + 2), 'm=%d %s' % (m, 'TILE' if mode else 'STRETCH'),
                   fill=(255, 214, 96, 255))
            x += cell_w + gap
        y += cell_h + 20 + gap

    os.makedirs('.workbuddy/shots', exist_ok=True)
    out = '.workbuddy/shots/9slice_%s.png' % os.path.splitext(os.path.basename(path))[0]
    canvas.save(out)
    print('margins:', margins, '-> target', tw, 'x', th, 'tile:', do_tile)
    print('输出:', out)


if __name__ == '__main__':
    main()
