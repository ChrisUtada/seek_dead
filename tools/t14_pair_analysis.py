# -*- coding: utf-8 -*-
"""T1.4 扩大样本 A/B 逐种子配对分析（用户口径：不只中位数）。

用法: python tools/t14_pair_analysis.py <A_summary.json> <B_summary.json>
输出每个种子的 ACT2 输出/相对A变化、到达/死亡节点/剩余HP、精英奖励总量、Draft选择，
以及每组中位/平均与逐种子正负方向。
"""
import json
import statistics
import sys

ACTS = {"ACT1": range(0, 8), "ACT2": range(8, 16), "ACT3": range(16, 24)}


def load(path):
    d = json.load(open(path, encoding="utf-8"))
    runs = {}
    for r in d.get("runs", []):
        runs[int(r["seed"])] = r
    return runs


def act2_out(run):
    total = 0
    for room in run.get("rooms", [])[8:16]:
        for t in room.get("turn_log", []):
            total += int(t.get("enemy_hp", 0)) - int(t.get("enemy_hp_end", 0))
    return total


def death_info(run):
    rooms = run.get("rooms", [])
    if not rooms:
        return (0, "-", 0)
    last = rooms[-1]
    return (len(rooms), str(last.get("kind", "-")), int(last.get("hp_end", 0)))


def elite_reward_total(run):
    # 精英保底护符（A）或精英强化Draft（B）的总量代理：护符持有 + 本局武器/技艺成长计数
    g = run.get("growth", {})
    charm = run.get("charms_owned", 0)
    summary = str(g.get("summary", "")) + str(g.get("mastery", ""))
    return f"charms={charm}, growth={summary}"


def main(a_path, b_path):
    A, B = load(a_path), load(b_path)
    seeds = sorted(set(A) & set(B))
    print(f"配对种子数: {len(seeds)}")
    print(f"{'种子':<6}{'A_ACT2':>8}{'B_ACT2':>8}{'变化%':>8}{'A到达':>7}{'B到达':>7}{'B死亡':>8}{'B剩HP':>7}{'方向':>6}")
    a_out, b_out, a_rooms, b_rooms = [], [], [], []
    pos = neg = flat = 0
    for s in seeds:
        ao, bo = act2_out(A[s]), act2_out(B[s])
        br, bk, bh = death_info(B[s])
        aa, _, _ = death_info(A[s])
        chg = (bo - ao) / ao * 100 if ao else 0
        direction = "+" if bo > ao else ("-" if bo < ao else "=")
        if bo > ao: pos += 1
        elif bo < ao: neg += 1
        else: flat += 1
        a_out.append(ao); b_out.append(bo); a_rooms.append(aa); b_rooms.append(br)
        print(f"{s:<6}{ao:>8}{bo:>8}{chg:>+8.1f}{aa:>7}{br:>7}{bk:>8}{bh:>7}{direction:>6}")
    print()
    print(f"{'指标':<14}{'A中位':>9}{'B中位':>9}{'A平均':>9}{'B平均':>9}")
    for name, av, bv in [("ACT2输出", a_out, b_out), ("到达节点", a_rooms, b_rooms)]:
        print(f"{name:<14}{statistics.median(av):>9.0f}{statistics.median(bv):>9.0f}"
              f"{statistics.mean(av):>9.1f}{statistics.mean(bv):>9.1f}")
    print(f"\n逐种子方向(ACT2输出): +{pos} / -{neg} / ={flat}")
    print("\n--- 精英奖励总量/Draft 选择（B组）---")
    for s in seeds:
        print(f"  种子{s}: A[{elite_reward_total(A[s])}]  B[{elite_reward_total(B[s])}]")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("用法: python tools/t14_pair_analysis.py <A_summary.json> <B_summary.json>")
    else:
        main(sys.argv[1], sys.argv[2])
