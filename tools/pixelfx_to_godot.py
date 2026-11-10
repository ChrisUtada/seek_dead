#!/usr/bin/env python3
"""把 pixelfx 导出的 Aseprite sheet + JSON 转成 Godot 4 的 SpriteFrames 资源。

用法：
    python tools/pixelfx_to_godot.py ice/frost-breath ice/snowflake-burst ice/ice-spikes

约定：
- 输入：.workbuddy/vendor/pixelfx-main/records/<id>/<name>.png|.json
- 输出：assets/fx/<name>/<name>.png（贴图） + assets/fx/<name>/<name>.tres（SpriteFrames）
- 动画名统一为 "default"，speed 取 JSON 的 fps，loop 取 JSON 的 loop。
- 只写 .png 与 .tres；.import 由 Godot 首次打开时生成（不入库）。
"""
from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RECORDS = ROOT / ".workbuddy/vendor/pixelfx-main/records"
OUT_ROOT = ROOT / "assets/fx"


def build(effect_id: str) -> Path:
    name = effect_id.split("/")[-1]
    src = RECORDS / effect_id
    png, meta_path = src / f"{name}.png", src / f"{name}.json"
    if not png.exists() or not meta_path.exists():
        raise FileNotFoundError(f"缺少导出产物：{png} / {meta_path}")

    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    frames = meta["frames"]
    fx = meta.get("meta", {}).get("pixelfx", {})
    fps = float(fx.get("fps") or 30)
    loop = bool(fx.get("loop", False))

    out_dir = OUT_ROOT / name
    out_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(png, out_dir / f"{name}.png")

    ext_id = "1_sheet"
    lines = [
        '[gd_resource type="SpriteFrames" load_steps=%d format=3]' % (len(frames) + 2),
        "",
        '[ext_resource type="Texture2D" path="res://assets/fx/%s/%s.png" id="%s"]' % (name, name, ext_id),
        "",
    ]
    for i, fr in enumerate(frames):
        f = fr["frame"]
        lines += [
            '[sub_resource type="AtlasTexture" id="AtlasTexture_%03d"]' % i,
            'atlas = ExtResource("%s")' % ext_id,
            "region = Rect2(%d, %d, %d, %d)" % (f["x"], f["y"], f["w"], f["h"]),
            "",
        ]

    frame_entries = []
    for i in range(len(frames)):
        frame_entries.append(
            '{\n"duration": 1.0,\n"texture": SubResource("AtlasTexture_%03d")\n}' % i
        )
    anim = (
        "{\n"
        '"frames": [%s],\n'
        '"loop": %s,\n'
        '"name": &"default",\n'
        '"speed": %s\n'
        "}" % (", ".join(frame_entries), "true" if loop else "false", fps)
    )
    lines += ["[resource]", "animations = [%s]" % anim, ""]

    out = out_dir / f"{name}.tres"
    out.write_text("\n".join(lines), encoding="utf-8")
    print(f"{effect_id:26} -> {out.relative_to(ROOT)}  frames={len(frames)} fps={fps:g} loop={loop}")
    return out


def main() -> int:
    ids = sys.argv[1:]
    if not ids:
        ids = ["ice/frost-breath", "ice/snowflake-burst", "ice/ice-spikes"]
    for eid in ids:
        build(eid)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
