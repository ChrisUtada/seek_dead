"""九宫格边距检测：量出每张 UI 图四边的实际边框厚度，输出建议的 texture_margin。

背景：`StyleBoxTexture.texture_margin_*` 必须等于「图片里真实边框的厚度（含角部装饰）」。
填小了，控件内容会压到边框上；填大了，边角会被拉伸变形。
靠肉眼估这个数字反复出错，所以用脚本量。

用法：
    py -3.15 tools/check_9slice.py                # 检查 assets/ui/ 下全部 png
    py -3.15 tools/check_9slice.py --tscn scenes/ui/battle_hud.tscn
"""
import sys
import os
import glob
import re
from collections import Counter
from PIL import Image


def measure(path):
    """以内腔中心点的颜色为基准，测四边到这里的中位距离 = 边框厚度。"""
    im = Image.open(path).convert('RGBA')
    w, h = im.size
    px = im.load()
    interior = px[w // 2, h // 2][:3]

    def side_depth(side):
        vals = []
        if side in ('top', 'bottom'):
            rng_x = range(int(w * 0.30), int(w * 0.70))
            for x in rng_x:
                rng = range(h) if side == 'top' else range(h - 1, -1, -1)
                for i in rng:
                    c = px[x, i]
                    if c[3] < 40:
                        continue
                    if c[:3] == interior:
                        vals.append(i)
                        break
        else:
            rng_y = range(int(h * 0.30), int(h * 0.70))
            for y in rng_y:
                rng = range(w) if side == 'left' else range(w - 1, -1, -1)
                for i in rng:
                    c = px[i, y]
                    if c[3] < 40:
                        continue
                    if c[:3] == interior:
                        vals.append(i)
                        break
        if not vals:
            return None
        vals.sort()
        return vals[len(vals) // 2]

    return w, h, interior, (side_depth('left'), side_depth('right'),
                            side_depth('top'), side_depth('bottom'))


def scan_tscn(path):
    """读场景里每张 StyleBoxTexture 当前填的边距，用于对比。"""
    if not os.path.exists(path):
        return {}
    s = open(path, encoding='utf-8').read()
    tex_vars = dict(re.findall(r'id="(\w+)"\]\n?', ''))
    out = {}
    for m in re.finditer(r'\[sub_resource type="StyleBoxTexture" id="(\w+)"\](.*?)(?=^\[|\Z)', s, re.M | re.S):
        sid, body = m.group(1), m.group(2)
        tex = re.search(r'texture = ExtResource\("([^"]+)"\)', body)
        vals = re.search(r'texture_margin_left = ([\d.]+)\s*\n?.*?texture_margin_top = ([\d.]+)\s*\n?.*?texture_margin_right = ([\d.]+)\s*\n?.*?texture_margin_bottom = ([\d.]+)', body, re.S)
        if tex and vals:
            key = os.path.basename(tex.group(1))
            out[key] = (sid, tuple(int(float(v)) for v in vals.groups()))
    return out


def main():
    tscn = None
    if '--tscn' in sys.argv:
        tscn = sys.argv[sys.argv.index('--tscn') + 1]
    current = scan_tscn(tscn) if tscn else {}

    files = sorted(glob.glob('assets/ui/*.png'))
    if not files:
        print('assets/ui/ 下没有 png')
        return

    print('%-18s %-9s %-22s %-16s %s' % ('文件', '尺寸', '内腔色', '实测边框 L/R/T/B', '结论'))
    print('-' * 92)
    for f in files:
        name = os.path.basename(f)
        w, h, interior, (l, r, t, b) = measure(f)
        sug = max(2, max([v for v in (l, r, t, b) if v is not None] or [2]))
        note = ''
        if name in current:
            sid, cur = current[name]
            cur_max = max(cur)
            if cur_max < sug:
                note = '⚠ 场景填 %s 偏小（建议 %d），会压边' % (sid, sug)
            elif cur_max > sug * 2:
                note = '⚠ 场景填 %s 偏大（建议 %d），角部会变形' % (sid, sug)
            else:
                note = '✓ 场景 %s = %d 合适' % (sid, cur_max)
        else:
            note = '建议 margin = %d' % sug
        print('%-18s %-9s %-22s %-16s %s' % (
            name, '%dx%d' % (w, h), str(interior[:3]), '%s/%s/%s/%s' % (l, r, t, b), note))


if __name__ == '__main__':
    main()
