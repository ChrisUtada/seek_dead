# -*- coding: utf-8 -*-
"""G7 门禁可归因 A/B 分析（方案 §4.1 四条门槛）。

输入：四个档位目录（no_growth / forge / tune / mixed）各自的 summary.json。
输出：按幕输出中位/TTK/承伤/低分位 + 门槛①~④ 判定。
"""
import json
import os
import statistics
import sys

ACTS = {"ACT1": range(0, 8), "ACT2": range(8, 16), "ACT3": range(16, 24)}
MODES = ["no_growth", "forge", "tune", "mixed"]


def load(base, mode):
    p = os.path.join(base, mode, "summary.json")
    d = json.load(open(p, encoding="utf-8"))
    return d["runs"]


def act_stats(runs, rng):
    outs, turns, dmg = [], [], []
    for run in runs:
        for idx, room in enumerate(run.get("rooms", [])):
            if idx not in rng:
                continue
            out = sum(int(t.get("enemy_hp", 0)) - int(t.get("enemy_hp_end", 0))
                      for t in room.get("turn_log", []))
            outs.append(out)
            turns.append(int(room.get("turns", 0)))
            # 承伤：该房 hp_start - hp_end（近似）
            dmg.append(int(room.get("hp_start", 0)) - int(room.get("hp_end", 0)))
    if not outs:
        return None
    s = sorted(outs)
    return {
        "n": len(outs),
        "median": statistics.median(outs),
        "p10": s[max(0, len(s) // 10 - 1)],
        "min": s[0],
        "ttk": statistics.median(turns) if turns else 0,
        "dmg": statistics.median(dmg) if dmg else 0,
    }


def max_room_reached(runs):
    return max((len(r.get("rooms", [])) for r in runs), default=0)


def main(base):
    data = {m: load(base, m) for m in MODES if os.path.exists(os.path.join(base, m, "summary.json"))}
    print("=== G7 可归因 A/B 分析 ===")
    print("档位        局数  最远房  成长注入")
    for m, runs in data.items():
        grown = sum(1 for r in runs if "forge" in str(r.get("growth_applied", "")) and "forge\": 2" in str(r.get("growth_applied", "")))
        print(f"{m:<12}{len(runs):>4}{max_room_reached(runs):>8}{grown:>8}")

    print("\n=== 门槛①: bot 活过 ACT1 覆盖 ACT2/3 ===")
    for m, runs in data.items():
        reached3 = sum(1 for r in runs if len(r.get("rooms", [])) >= 16)
        print(f"{m:<12} 到达 ACT3 局数 {reached3}/{len(runs)}")

    print("\n=== 门槛③: 按幕输出中位 / TTK / 承伤中位 / 低分位(p10) ===")
    print(f"{'档位':<12}{'幕':<6}{'样本':>6}{'输出中位':>10}{'TTK':>7}{'承伤':>7}{'p10':>7}{'min':>7}")
    for m, runs in data.items():
        for act, rng in ACTS.items():
            st = act_stats(runs, rng)
            if st is None:
                print(f"{m:<12}{act:<6}{'无样本':>6}")
                continue
            print(f"{m:<12}{act:<6}{st['n']:>6}{st['median']:>10.0f}{st['ttk']:>7.1f}{st['dmg']:>7.0f}{st['p10']:>7}{st['min']:>7}")

    print("\n=== 门槛④: 量化旧成长贡献（相对 no_growth 的输出中位变化）===")
    if "no_growth" in data:
        base_act1 = act_stats(data["no_growth"], ACTS["ACT1"])
        if base_act1:
            for m in ["forge", "tune", "mixed"]:
                if m not in data:
                    continue
                st = act_stats(data[m], ACTS["ACT1"])
                if st:
                    delta = st["median"] - base_act1["median"]
                    pct = (delta / base_act1["median"] * 100) if base_act1["median"] else 0
                    print(f"{m:<12} ACT1 输出中位 {st['median']:.0f} vs 无成长 {base_act1['median']:.0f} → {delta:+.0f} ({pct:+.1f}%)")
    print("\n注：门槛②「领取率100%无结算失败」需检查注入是否生效（growth_applied 字段）与 errors 是否为空。")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("用法: py -3.15 tools/g7_gate_analyze.py docs/baseline/G7_2026-11-20_attribution_ab")
        sys.exit(1)
    main(sys.argv[1])
