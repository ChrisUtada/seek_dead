#!/usr/bin/env python3
"""把新绘制的符号图标接入 resources/symbols/*.tres。

两类改动：
  1) 14 个原本没有 icon_tex 的符号：补 Texture2D ext_resource + icon_tex 字段，
     load_steps +1（原本没写 load_steps 的补成 3）。
  2) axe_slash / gold：原本指向旧 16px 目录 assets/icons/16/，改指 symbols/16/，
     这样 battle_hud.gd 的 _cell_icon() 才能把 16px 升级成 32px 同名版本。

工程铁律：icon_tex 必须写在 `script = ExtResource("1")` **之后**，写在前面会被
Godot 静默丢弃。本脚本按行插入，不改动其它字段顺序。

用法：
  py -3.15 tools/attach_symbol_icons.py --check   # 只列出将要改动的文件，不写入
  py -3.15 tools/attach_symbol_icons.py           # 写入
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(ROOT, "resources/symbols")

NEW_ICONS = [
    "arrow_shot", "bolt_shot", "pistol_shot", "plague_bolt", "ice_shot", "dawn_bolt",
    "shadow_chain", "viper_lash", "dagger_slash", "shadow_guillotine_slash",
    "corrosive_spray", "abyss_bite", "holy_mace_smash", "flame_special",
]
REPOINT = ["axe_slash", "gold"]

TEX_LINE = '[ext_resource type="Texture2D" path="res://assets/icons/symbols/16/{n}.png" id="2_icon"]'
ICON_LINE = 'icon_tex = ExtResource("2_icon")'


def add_icon(name: str, text: str) -> str:
    assert "icon_tex" not in text, f"{name}: 已有 icon_tex，跳过以免重复"
    lines = text.splitlines()
    # 1) load_steps +1；缺失则补 3
    for i, line in enumerate(lines):
        if line.startswith("[gd_resource"):
            m = re.search(r"load_steps=(\d+)", line)
            if m:
                lines[i] = line.replace(f"load_steps={m.group(1)}",
                                        f"load_steps={int(m.group(1)) + 1}")
            else:
                lines[i] = line.replace(" format=3]", " load_steps=3 format=3]")
            break
    # 2) Texture2D ext_resource 紧跟 Script 行
    for i, line in enumerate(lines):
        if line.startswith('[ext_resource type="Script"'):
            lines.insert(i + 1, TEX_LINE.format(n=name))
            break
    else:
        raise RuntimeError(f"{name}: 找不到 Script ext_resource")
    # 3) icon_tex 必须写在 script 赋值之后
    for i, line in enumerate(lines):
        if line.strip() == 'script = ExtResource("1")':
            lines.insert(i + 1, ICON_LINE)
            break
    else:
        raise RuntimeError(f"{name}: 找不到 script = ExtResource(\"1\")")
    return "\n".join(lines) + ("\n" if text.endswith("\n") else "")


def repoint(name: str, text: str) -> str:
    old = f"res://assets/icons/16/{name}.png"
    new = f"res://assets/icons/symbols/16/{name}.png"
    assert old in text, f"{name}: 找不到旧路径 {old}"
    return text.replace(old, new)


def main() -> None:
    check = "--check" in sys.argv
    for name in NEW_ICONS:
        p = os.path.join(DIR, name + ".tres")
        with open(p, encoding="utf-8") as f:
            text = f.read()
        out = add_icon(name, text)
        assert 'script = ExtResource("1")\nicon_tex' in out, f"{name}: 顺序校验失败"
        if not check:
            with open(p, "w", encoding="utf-8", newline="\n") as f:
                f.write(out)
        print(f"  add  {name:28s} load_steps+1 / icon_tex")
    for name in REPOINT:
        p = os.path.join(DIR, name + ".tres")
        with open(p, encoding="utf-8") as f:
            text = f.read()
        out = repoint(name, text)
        if not check:
            with open(p, "w", encoding="utf-8", newline="\n") as f:
                f.write(out)
        print(f"  move {name:28s} assets/icons/16/ -> symbols/16/")
    print("CHECK ONLY（未写入）" if check else f"已写入 {len(NEW_ICONS) + len(REPOINT)} 个 .tres")


if __name__ == "__main__":
    main()
