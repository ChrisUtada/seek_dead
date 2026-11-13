#!/usr/bin/env python3
"""敌人立绘朝向修正：水平镜像 idle_01.png。

约定：StageRow 为 HBoxContainer，玩家在左、敌人在右；玩家小人朝右，
所以敌人立绘必须 3/4 侧身朝左面向玩家。AI 出图偶尔会定成朝右，需人工核对后镜像。

仅做纯镜像：尺寸、alpha、调色板全部不变，.import 不需要改（Godot 会检测文件变化重新导入）。
原图自动备份到 .workbuddy/art_trials/orientation_backup/，可随时回退。

用法：
  py -3.15 tools/flip_enemy_art.py a2_brute_none --preview   # 只出对比图，不写正式资源
  py -3.15 tools/flip_enemy_art.py a2_brute_none             # 备份 + 镜像写回
  py -3.15 tools/flip_enemy_art.py a2_brute_none a3_brute_none   # 批量
"""
import os
import shutil
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHAR = os.path.join(ROOT, "assets/characters")
TRIALS = os.path.join(ROOT, ".workbuddy/art_trials")
BACKUP = os.path.join(TRIALS, "orientation_backup")


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    preview = "--preview" in sys.argv
    assert args, "请给出至少一个房间名（assets/characters/ 下的目录名）"
    os.makedirs(BACKUP, exist_ok=True)

    S, cell, pad = 4, 96 * 4 + 20, 20
    canvas = Image.new("RGBA", (pad + cell * len(args), pad + 96 * S + 44), (29, 18, 25, 255))
    d = ImageDraw.Draw(canvas)

    for i, room in enumerate(args):
        src = os.path.join(CHAR, room, "idle_01.png")
        assert os.path.exists(src), f"找不到 {src}"
        im = Image.open(src).convert("RGBA")
        assert im.size == (96, 96), f"{room}: 期望 96x96，实际 {im.size}"
        flipped = im.transpose(Image.FLIP_LEFT_RIGHT)

        x = pad + i * cell
        d.text((x, pad), room, fill=(225, 220, 210, 255))
        d.text((x, pad + 14), "BEFORE (faces right)", fill=(240, 170, 120, 255))
        d.text((x + 96 * S // 2, pad + 14), "AFTER (faces left)", fill=(130, 220, 150, 255))
        # 并排放原图 / 镜像，各 2 倍，便于直接对照
        half = im.resize((96 * 2, 96 * 2), Image.NEAREST)
        fh = flipped.resize((96 * 2, 96 * 2), Image.NEAREST)
        canvas.alpha_composite(half, (x, pad + 32))
        canvas.alpha_composite(fh, (x + 96 * 2, pad + 32))
        canvas.alpha_composite(flipped.resize((96 * S, 96 * S), Image.NEAREST), (x, pad + 32 + 96 * 2 + 8))

        if not preview:
            bak = os.path.join(BACKUP, f"{room}_idle_01.png")
            if not os.path.exists(bak):
                shutil.copy2(src, bak)
            flipped.save(src)
        print(f"{room:28s} 96x96 镜像{'（预览，未写入）' if preview else ' 已写回'}  备份: {BACKUP}")

    out = os.path.join(TRIALS, "orientation_flip_compare.png")
    canvas.convert("RGB").save(out)
    print(f"对比图：{out}")


if __name__ == "__main__":
    main()
