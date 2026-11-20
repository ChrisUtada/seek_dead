# -*- coding: utf-8 -*-
"""G5 安全门对比：新输出曲线 vs G0 旧基线（同种子/策略/口径）。

口径（与 G0_3a 完全一致）：
- 单房输出 = 该房所有回合 turn_log 的 (enemy_hp - enemy_hp_end) 之和
- 分幕：room index 0-7 = ACT1 / 8-15 = ACT2 / 16-23 = ACT3
- 各幕单房输出取中位数；安全门 = 各幕中位 >= 旧基线 * 0.90
"""
import json
import statistics
import sys

OLD = {"ACT1": 184, "ACT2": 440, "ACT3": 396}
ACT_RANGE = {"ACT1": range(0, 8), "ACT2": range(8, 16), "ACT3": range(16, 24)}


def per_act_rooms(summary_path):
    d = json.load(open(summary_path, encoding="utf-8"))
    acts = {"ACT1": [], "ACT2": [], "ACT3": []}
    for run in d["runs"]:
        rooms = run.get("rooms", [])
        for idx, room in enumerate(rooms):
            out = 0
            for t in room.get("turn_log", []):
                out += int(t.get("enemy_hp", 0)) - int(t.get("enemy_hp_end", 0))
            for act, rng in ACT_RANGE.items():
                if idx in rng:
                    acts[act].append(out)
                    break
    return acts


def median_of(vals):
    return statistics.median(vals) if vals else None


def main(old_path, new_path):
    old = per_act_rooms(old_path)
    new = per_act_rooms(new_path)
    print("=== G5 安全门对比（同口径 tactical / 6 种子）===")
    print(f"{'幕':<6}{'旧基线':>8}{'新曲线':>8}{'样本(旧/新)':>12}{'90%门槛':>10}{'结论':>8}")
    all_pass = True
    for act in ("ACT1", "ACT2", "ACT3"):
        om = median_of(old[act])
        nm = median_of(new[act])
        gate = OLD[act] * 0.90
        if nm is None:
            verdict = "无样本"
            all_pass = False
        elif nm >= gate:
            verdict = "通过"
        else:
            verdict = "未通过"
            all_pass = False
        oms = f"{om:.0f}" if om is not None else "-"
        nms = f"{nm:.0f}" if nm is not None else "-"
        print(f"{act:<6}{oms:>8}{nms:>8}{f'{len(old[act])}/{len(new[act])}':>12}{gate:>10.0f}{verdict:>8}")
    print(f"\n总体：{'✅ 安全门通过' if all_pass else '❌ 安全门未通过（需继续补新系统，不删旧成长）'}")
    print("\n注：ACT3 样本通常不足（G0 仅 9 房/2 局），方案规定 ACT3 样本不足时用 ACT1+ACT2 主判断。")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("用法: py -3.15 tools/g5_gate_compare.py <旧summary.json> <新summary.json>")
        sys.exit(1)
    main(sys.argv[1], sys.argv[2])
