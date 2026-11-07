#!/usr/bin/env python3
"""Step 3 样板角色风格化（2026-10-31）

把现有像素立绘按「少量色阶」重新映射，产出红色 BOSS 与普通敌人样板。
只改颜色，不改尺寸、不改像素位置、不写透明通道；**不覆盖任何原始素材**。
玩家已改为 redraw_player.py 的定制骑士，本脚本保留而不覆盖 viking_ash/。

用法（仓库根目录）：
    python tools/art_pipeline/stylize_sample.py

输出：
    assets/bossbf_ember.png
    assets/enemy_ember.png

映射原则：
    1. 按感知亮度分档，每档一个颜色 → 保留原图的明暗结构，丢掉原始色相；
    2. 玩家使用 6 阶暖灰，BOSS 使用 6 阶红（取自任务书色板的敌人红/暗红）；
    3. 透明度原样保留（半透明描边不会被填实）。
"""

import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

BOSS_SRC = os.path.join(ROOT, "assets", "bossbf.png")
BOSS_DST = os.path.join(ROOT, "assets", "bossbf_ember.png")

# 普通敌人红色少色副本。原始 assets/enemy.png 为 16×16，
# 保持原尺寸与透明通道，只做亮度分档重映射；不覆盖原始文件。
ENEMY_SRC = os.path.join(ROOT, "assets", "enemy.png")
ENEMY_DST = os.path.join(ROOT, "assets", "enemy_ember.png")

# (亮度上限, 颜色) —— 按顺序取第一个满足 L <= 上限的档位。
EMBER_RAMP = [
    (0.08, (0x3A, 0x12, 0x16)),
    (0.20, (0x5E, 0x1A, 0x1F)),
    (0.34, (0x7E, 0x26, 0x2C)),
    (0.50, (0x9E, 0x34, 0x38)),
    (0.68, (0xC0, 0x47, 0x4A)),
    (1.01, (0xE3, 0x5B, 0x50)),
]


def luminance(r, g, b):
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255.0


def remap(img, ramp):
    out = img.copy()
    px = out.load()
    w, h = out.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            lum = luminance(r, g, b)
            for limit, color in ramp:
                if lum < limit:
                    px[x, y] = (color[0], color[1], color[2], a)
                    break
    return out


def main():
    print("player: preserved custom knight; use redraw_player.py instead")

    img = Image.open(BOSS_SRC).convert("RGBA")
    if img.size != (48, 48):
        raise SystemExit("unexpected size %s %s" % (BOSS_SRC, img.size))
    remap(img, EMBER_RAMP).save(BOSS_DST)
    print("boss:  ", os.path.relpath(BOSS_DST, ROOT))

    img = Image.open(ENEMY_SRC).convert("RGBA")
    if img.size != (16, 16):
        raise SystemExit("unexpected size %s %s" % (ENEMY_SRC, img.size))
    remap(img, EMBER_RAMP).save(ENEMY_DST)
    print("enemy: ", os.path.relpath(ENEMY_DST, ROOT))


if __name__ == "__main__":
    main()
