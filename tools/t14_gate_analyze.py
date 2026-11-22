# -*- coding: utf-8 -*-
"""T1.4 ACT2 安全门分析：输出中位 + 生存指标 + 精英奖励总量（同种子/策略口径 A/B 对照）。

用法：python tools/t14_gate_analyze.py <summary.json> [<summary2.json> ...]
口径与 docs/G5-5_安全门验收报告 一致：
- 单房输出 = 该房所有回合 turn_log 的 (enemy_hp - enemy_hp_end) 之和
- 分幕：room index 0-7=ACT1 / 8-15=ACT2 / 16-23=ACT3
- 安全门：ACT2 中位 >= 396（历史 422 的 90% 线）
"""
import json
import statistics
import sys

GATE = {"ACT1": 166, "ACT2": 396, "ACT3": 356}
ACTS = {"ACT1": range(0, 8), "ACT2": range(8, 16), "ACT3": range(16, 24)}


def analyze(path):
    d = json.load(open(path, encoding="utf-8"))
    out = {k: [] for k in ACTS}
    surv = []
    for run in d.get("runs", []):
        rooms = run.get("rooms", [])
        for idx, room in enumerate(rooms):
            o = sum(int(t.get("enemy_hp", 0)) - int(t.get("enemy_hp_end", 0))
                    for t in room.get("turn_log", []))
            for a, rng in ACTS.items():
                if idx in rng:
                    out[a].append(o)
                    break
        surv.append(run)
    return out, surv


def show(label, path):
    out, surv = analyze(path)
    print(f"=== {label} ({path}) ===")
    for a in ("ACT1", "ACT2", "ACT3"):
        v = out[a]
        med = statistics.median(v) if v else None
        gate = GATE[a]
        verdict = "无样本" if med is None else ("通过" if med >= gate else "未通过")
        ms = f"{med:.0f}" if med is not None else "-"
        print(f"  {a}: 输出中位={ms}  样本={len(v)}  门槛={gate}  {verdict}")
    dt = [r.get("damage_taken", 0) for r in surv]
    turns = [r.get("turns", 0) for r in surv]
    rooms = [len(r.get("rooms", [])) for r in surv]
    print(f"  生存: 承伤中位={statistics.median(dt) if dt else '-'} "
          f"回合中位={statistics.median(turns) if turns else '-'} "
          f"到达房数={rooms}")
    print(f"  终点: {[r.get('terminal') for r in surv]}")
    print(f"  护符持有: {[r.get('charms_owned') for r in surv]}")
    print()
    return out, surv


def main():
    if len(sys.argv) < 2:
        print("用法: python tools/t14_gate_analyze.py <summary.json> [summary2.json ...]")
        return
    results = [show(f"组{i+1}", p) for i, p in enumerate(sys.argv[1:])]
    if len(results) == 2:
        (a_out, _), (b_out, _) = results
        print("=== A/B 对照（B 相对 A）===")
        for act in ("ACT1", "ACT2", "ACT3"):
            am = statistics.median(a_out[act]) if a_out[act] else None
            bm = statistics.median(b_out[act]) if b_out[act] else None
            if am and bm:
                print(f"  {act}: {am:.0f} -> {bm:.0f} ({(bm-am)/am*100:+.1f}%)")


if __name__ == "__main__":
    main()
