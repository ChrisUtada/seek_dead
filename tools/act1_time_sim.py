# -*- coding: utf-8 -*-
"""ACT1 单轮通关流程时长模拟（2026-08-14）
基于真实资源（rooms/archetypes）+ 代码常量（reel_system 旋转/结算间隔）推算。
说明：人类目押速度/读文本/思考不可模拟——输出"机器底线"与"人类区间"两档，最终以 F6 实测为准。
用法：python tools/act1_time_sim.py
"""
import io, os, re, math

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOMS = os.path.join(ROOT, "resources", "rooms")
ARCH = os.path.join(ROOT, "resources", "archetypes")

def read_tres(p):
    d = {}
    ext = {}
    with io.open(p, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            m = re.match(r'\[ext_resource type="Resource" (?:uid="[^"]*" )?path="([^"]+)" id="([^"]+)"\]', line)
            if m:
                ext[m.group(2)] = m.group(1)
                continue
            m = re.match(r'^([a-z_0-9]+)\s*=\s*(.+)$', line)
            if m:
                d[m.group(1)] = m.group(2).strip().strip('"')
    if "archetype" in d:
        m = re.match(r'ExtResource\("([^"]+)"\)', d["archetype"])
        if m and m.group(1) in ext:
            d["archetype_path"] = ext[m.group(1)]
    return d

# ---- 读取 archetype 基准（hp=0 的房间走族基准）----
arch_base = {}
for f in os.listdir(ARCH):
    if not f.endswith(".tres"):
        continue
    d = read_tres(os.path.join(ARCH, f))
    arch_base[d.get("id", f)] = {
        "hp": float(d.get("hp_base", 0) or 0),
        "atk": float(d.get("atk_base", 0) or 0),
    }

# ---- 读取 ACT1 房间（act=1）----
rooms = []
for f in os.listdir(ROOMS):
    if not f.endswith(".tres"):
        continue
    p = os.path.join(ROOMS, f)
    t = io.open(p, encoding="utf-8").read()
    if "act = 1" not in t:
        continue
    d = read_tres(p)
    arch_id = d.get("archetype_path", "").split("/")[-1].replace(".tres", "")
    hp = float(d.get("hp", 0) or 0)
    atk = float(d.get("atk", 0) or 0)
    if hp == 0 and arch_id in arch_base:
        hp = arch_base[arch_id]["hp"]
    if atk == 0 and arch_id in arch_base:
        atk = arch_base[arch_id]["atk"]
    rooms.append({
        "name": d.get("name", f), "kind": d.get("kind", "normal"),
        "element": d.get("element", "none"), "hp": hp, "atk": atk,
    })

normals = [r for r in rooms if r["kind"] == "normal"]
elites = [r for r in rooms if r["kind"] == "elite"]
bosses = [r for r in rooms if r["kind"] == "boss"]

# ---- 玩家 DPS 模型（典型构筑：fire_sword 18 + iron_sword 12 + 3 技能 + 护符）----
PLAYER_DMG_MULT = 1.5
def player_dps_vs(elem):
    """每回合期望输出（简化：目押每转命中 1.5 个攻击符号，含克制期望）"""
    flat_avg = 15.0            # 双武器符号平均 flat
    crit_e = 1.10              # 独立暴击期望（20% × 1.5 倍率档）
    adv = 1.5 if elem in ("ice", "poison") else 1.0   # 火克冰/光克毒；对冰系/毒系敌人有克制
    hits = 1.5
    return hits * flat_avg * adv * crit_e * PLAYER_DMG_MULT

# ---- 时长常量（reel_system/combat_system）----
SPIN_BASE = 0.15          # 旋转起始每跳间隔
TICK_COUNT = 18           # 平均每转跳动次数（目押）
SETTLE = 0.25 + 0.35      # 结算两段等待
ENEMY_TURN = 0.20 + 0.35  # 敌人行动两段等待

def human_turn_sec():     # 人类每回合（目押+思考）
    return SPIN_BASE * TICK_COUNT / 2 + SETTLE + ENEMY_TURN + 2.5   # 目押反应 ~2.5s

def machine_turn_sec():   # 机器底线（不停轮直接结算）
    return SPIN_BASE * 2 + SETTLE + ENEMY_TURN

# ---- ante（act1：无幕间台阶，ria=0..7）----
def hp_scale(ria): return 1.15 ** ria

LAYOUT = ["normal"] * 3 + ["elite"] + ["normal"] * 2 + ["elite"] + ["boss"]

print("=" * 88)
print("ACT1 单轮结构（run_act_layout）：3 普通 → 精英 → 2 普通 → 精英 → BOSS")
print("=" * 88)
total_h, total_m = 0.0, 0.0
total_turns = 0
for slot, kind in enumerate(LAYOUT):
    pool = normals if kind == "normal" else (elites if kind == "elite" else bosses)
    r = pool[slot % len(pool)]
    ria = slot
    hp = r["hp"] * hp_scale(ria)
    dps = player_dps_vs(r["element"])
    turns = max(1, math.ceil(hp / dps))
    h_sec = turns * human_turn_sec()
    m_sec = turns * machine_turn_sec()
    total_h += h_sec; total_m += m_sec; total_turns += turns
    print("%-2d %-6s %-10s elem=%-6s baseHP=%-6.0f anteHP=%-7.0f DPS=%5.0f 回合=%-3d 人类=%5.1fs 机器=%5.1fs" % (
        slot + 1, kind, r["name"], r["element"], r["hp"], hp, dps, turns, h_sec, m_sec))

print("-" * 88)
print("纯战斗：回合 %d ｜ 人类 %d 分 %.0f 秒 ｜ 机器底线 %d 分 %.0f 秒" % (
    total_turns, total_h // 60, total_h % 60, total_m // 60, total_m % 60))
overhead = 8 * 25 + 90   # 每房整备/商店/奖励/读文本 ~25s + 开场整备 90s
print("非战斗开销（整备/商店/奖励/铁砧/读文本）：约 %d 分 %.0f 秒" % (overhead // 60, overhead % 60))
total = total_h + overhead
print("单轮 ACT1 预计总时长：约 %d 分 %.0f 秒（人类中速）" % (total // 60, total % 60))
print("新手轮（含死亡重开）预估：12-15 分钟")
print("4-5 轮（1 小时 demo 目标）：约 %d 分 %.0f 秒" % (total * 4 // 60, total * 4 % 60))
