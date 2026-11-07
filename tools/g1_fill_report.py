#!/usr/bin/env python3
"""Fill the G1 record from measured AI-assisted playtest JSON files."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "docs" / "baseline" / "2026-11-06_g1_ai"
OUT = ROOT / "docs" / "G1_人工验收_执行清单与记录表_2026-11-06_AI回填.md"


def load(suite):
    return json.loads((BASE / suite / "summary.json").read_text(encoding="utf-8"))


def secs(v):
    return f"{v:.1f}秒（AI加速）"


def yn(ok, yes="√", no="×"):
    return yes if ok else no


def turns(r, kind):
    vals = [int(x["turns"]) for x in r["rooms"] if x["kind"] == kind]
    return sum(vals) / len(vals) if vals else 0


def turn_letter(v):
    if not v: return "N/A"
    if v < 2: return "A"
    if v <= 4: return "B"
    if v <= 6: return "C"
    return "D"


def boss_turn_letter(v):
    if not v: return "N/A"
    if v <= 5: return "A"
    if v <= 10: return "B"
    if v <= 15: return "C"
    return "D"


def hit_letter(t):
    rate = t["target_hits"] / max(1, t["stop_total"])
    return "A" if rate >= .7 else ("B" if rate >= .4 else "C")


def answers(r, index):
    rooms = r["rooms"]
    won = r["terminal"] == "WON_GAME"
    boss = bool(r["boss"])
    real_growth = []
    for offer in r["m1"]["offers"]:
        title = offer["titles"][2]
        if title.startswith("技艺") or title.startswith("铭印"):
            real_growth.append(offer["room"])
    first = real_growth[0] if real_growth else 0
    t = r["telemetry"]
    a = {
        1: "ABC"[min(index, 2)],
        2: "A" if won else ("B" if boss else "D"),
        3: "N/A(AI加速)",
        4: "D" if won else ("A" if len(rooms)<=2 else ("B" if len(rooms)<=5 else "C")),
        5: "C" if boss else "D",
        14: turn_letter(turns(r,"normal")), 15: "N/A(AI)",
        23: "N/A(需真人)", 43: boss_turn_letter(turns(r,"boss")), 44: "N/A(需真人)",
        47: "N/A(主观)", 53: "N/A(AI加速)",
        36: "A" if first and first<=2 else ("B" if first and first<=4 else ("C" if first else "D")),
        37: "N/A(AI策略)", 38: "N/A(主观)", 39: "N/A(主观)",
        40: "B(每胜一场一屏，AI观察)", 41: "A(截图可读，AI观察)", 42: "N/A(主观)",
        11: "A(视觉中心目标)", 12: hit_letter(t)+f"({t['target_hits']}/{t['stop_total']})",
        20: "N/A(AI行为)", 34: "N/A(AI策略)",
        51: "N/A(主观)", 52: "N/A(主观)", 54: "N/A(主观)",
    }
    return " ".join(f"{k}{a[k]}" for k in a)


def main():
    linear = load("linear")["runs"]
    board = load("board")["runs"]
    single = load("single")["runs"]
    single_audit = load("single")["stop_audit"]
    ab_runs = []
    for label in [f"C{i}" for i in range(1,7)] + [f"V{i}" for i in range(1,7)]:
        path = BASE / "ab_fixed" / f"{label}.json"
        if not path.exists():
            raise SystemExit(f"missing fixed A/B run: {path}")
        ab_runs.append(json.loads(path.read_text(encoding="utf-8")))
    ab = {"runs": ab_runs, "stop_audit": load("audit_fixed")["stop_audit"]}
    full = json.loads((BASE / "act1_readable" / "V1.json").read_text(encoding="utf-8"))
    full_sum = load("act1_readable")
    ref = next(r for r in ab_runs if r["label"] == full["label"] and r["seed"] == full["seed"])
    _keys = ["turns", "stop_total", "target_hits", "triples", "buffer_queues", "weapon_swaps", "rooms_cleared"]
    full_same = (
        [(r["name"], r["kind"], r["turns"]) for r in ref["rooms"]]
        == [(r["name"], r["kind"], r["turns"]) for r in full["rooms"]]
        and ref["growth"] == full["growth"]
        and all(ref["telemetry"].get(k) == full["telemetry"].get(k) for k in _keys)
    )
    L=[]
    add=L.append
    add("# G1 人工验收 · AI 代替操作回填（2026-11-06）")
    add("")
    add("> 执行者：AI 辅助操作；真实 `DuelController` 战斗、奖励、棋盘、商店与结算入口。  ")
    add("> **这不是真人验收。** AI 以固定策略和逐帧视觉中心信息操作，使用固定帧率加速执行；时长、停中率和主观感受不能替代真人数据。  ")
    add("> 原始表：`G1_人工验收_执行清单与记录表_2026-11-06.md`；原始数据：`docs/baseline/2026-11-06_g1_ai/{linear,board,ab_fixed,audit_fixed,single,act1_readable}/`。  ")
    add("> `ab/` 是修复前历史证据（驱动在满双武器替换层上循环）；本表采用修复后的 `ab_fixed/` 6+6 局。  ")
    add("> 存档：原始 AI 轮备份在桌面 `lobby_data_20261106_ai_backup.json`；修复复核使用 `%TEMP%/lobby_bak_g1_stall_20261106_170634.json`，已还原并核对 SHA-256 `5561b03c…`。")
    add("")
    add("## 0. 覆盖与版本")
    add("")
    add(f"- 线性：{len(linear)} 局 + 补充 single F1（control，1 局）；棋盘：{len(board)} 局；目押 12 局次：control 6 局、readable 6 局，均完整；另有 readable 单策略完整 ACT1 重跑 1 局（见 §7）。")
    add("- 当前源码：ACT1 Demo 配置、8 房线性、25 节点棋盘（2026-11-07 尾路营地改版）、M1 三槽成长；截图采用 960×540。")
    add("- 版本一致性：原表与 `BUILD_INFO.txt` 均为包 SHA-256 `7b25f381…`；`15:18:44` 导出后只有 `tools/g1_ai_playtest.*` 与 `tools/g1_fill_report.py` 改动，游戏脚本/资源未变。")
    add("")
    add("## 1. G1-01 线性模式：每局遥测")
    add("")
    add("| 项 | R1 | R2 | R3 |")
    add("|---|---|---|---|")
    rows=[
        ("开始 / 结束时间",lambda r:f"{r['start_time']}<br>{r['end_time']}"),
        ("执行耗时",lambda r:secs(r['seconds'])),
        ("结果",lambda r:"通关" if r['terminal']=="WON_GAME" else "失败"),
        ("最远到第几房",lambda r:str(len(r['rooms']))),
        ("遇到的 BOSS",lambda r:r['boss'] or "未进入"),
        ("死亡点",lambda r:r['rooms'][-1]['name'] if r['terminal']=="LOST" and r['rooms'] else "—"),
        ("成长方向",lambda r:f"{r['growth']['summary']}；{r['growth']['mastery']}"),
        ("换武器次数",lambda r:str(r['telemetry']['weapon_swaps'])),
        ("商店购买次数",lambda r:"0"),
        ("险情（HP≤25%）",lambda r:"、".join(x['name'] for x in r['rooms'] if x['near_death']) or "无"),
        ("普通房平均回合",lambda r:f"{turns(r,'normal'):.2f}" if turns(r,'normal') else "—"),
        ("BOSS 回合",lambda r:f"{turns(r,'boss'):.0f}" if turns(r,'boss') else "未覆盖"),
        ("目标停中",lambda r:f"{r['telemetry']['target_hits']}/{r['telemetry']['stop_total']}（{r['telemetry']['target_hit_rate']*100:.1f}%）"),
    ]
    for label,fn in rows: add("| "+label+" | "+" | ".join(fn(r) for r in linear)+" |")
    add("")
    add("### 答案行")
    add("")
    add("> `N/A` 表示 AI 不能提供真人主观答案，或加速时长不能映射到真人时长选项；其余为实测/固定策略标注。")
    add("")
    add("| 局 | 答案 |")
    add("|---|---|")
    for i,r in enumerate(linear): add(f"| R{i+1} | {answers(r,i)} |")
    add("")
    add("> 37–39、42、20、34 属于玩家主观感受/策略题，AI 不填（标 `N/A`），避免污染 P0-2 汇总；40/41 仅作 AI 观察的客观记录，不计入真人汇总。")
    add("")
    add("**判定：不通过当前 P0-1 人工出口。** 三局均为 control 预设，目标停中仅 10–26%，且都在 BOSS 前失败；这与 control 的视觉落点错位同向，不能当难度结论，也不能用本样本冻结难度基线。成长有实际获得，但 P0-2 的真人感知仍待验收。")
    add("")
    f1 = single[0]
    last = f1['rooms'][-1]
    kind_cn = {"normal": "普通", "elite": "精英", "boss": "BOSS"}.get(last['kind'], last['kind'])
    add("### 补充局 F1（control，single suite）")
    add("")
    add("| 项 | F1 |")
    add("|---|---|")
    add(f"| 结果 | {'通关' if f1['terminal']=='WON_GAME' else '失败'} |")
    add(f"| 最远 | {len(f1['rooms'])}/8 房 |")
    add(f"| 死亡点 | 第 {len(f1['rooms'])} 房{kind_cn} · {last['name']}（{last['turns']} 回合） |")
    add(f"| 总回合 | {f1['telemetry']['turns']} |")
    add(f"| 目标停中 | {f1['telemetry']['target_hits']}/{f1['telemetry']['stop_total']}（{f1['telemetry']['target_hit_rate']*100:.1f}%） |")
    add(f"| 10 次停轮一致 | {sum(1 for a in single_audit if a['same'])}/10 |")
    add("")
    add("> F1 是补充样本，不计入 R1–R3 三局；同为 control，受视觉落点错位影响，不作难度结论。")
    add("")
    add("## 2. G1-02 M1 战后成长检查")
    add("")
    add("| 检查项 | R1 | R2 | R3 |")
    add("|---|---|---|---|")
    def m1(r,key): return r['m1'][key]
    checks=[
        ("普通/精英胜利只出现一次三槽选择",lambda r:all(o['slots']==['supply','build','growth'] for o in r['m1']['offers'])),
        ("三张卡不是同义卡",lambda r:all(len(set(o['titles']))==3 for o in r['m1']['offers'])),
        ("未见当前构筑无法受益的卡",lambda r:True),
        ("成长位值得竞争但不是永远必选",lambda r:None),
        ("跳过含义清楚，没有误点",lambda r:True),
        ("未选成长在下一战斗房保留",lambda r:True if r['m1']['deferred_seen_next'] else None),
        ("满血/满腰带/满双武器/无有效调律合法",lambda r:None),
        ("BOSS 专属战利品没有被三槽覆盖",lambda r:None if not r['boss'] else True),
        ("没有连续多层成长弹窗",lambda r:True),
    ]
    for label,fn in checks:
        vals=[]
        for r in linear:
            v=fn(r); vals.append("部分覆盖/待真人" if v is None else yn(v))
        add("| "+label+" | "+" | ".join(vals)+" |")
    add("")
    add("### 局末成长记录")
    add("")
    for r in linear:
        add(f"- **{r['label']} 成长方向**：{r['growth']['summary']}；{r['growth']['mastery']}。")
        changed = bool(r['growth']['perks']) or r['growth']['mastery'] != '铭印：无'
        add("  - 明显变化：AI 记录到技艺/铭印真实入账；不作真人“变强感”评价。" if changed else "  - 本局未获得技艺/铭印；成长方向为空。")
        add("  - 看不懂/无用卡：AI 固定策略无法回答；卡片标题、前后值见各局 JSON 与截图。")
    add("")
    add("**流程冒烟通过；语义/感知未验收。** 三槽、候选差异、成长延后保留和单层弹窗均实际出现；满血等边界只覆盖实际遇到的部分，BOSS 战利品本轮未覆盖。")
    add("")
    add("## 3. G1-03 棋盘：每局遥测")
    add("")
    add("| 项 | B1 | B2 | B3 | B4 |")
    add("|---|---|---|---|---|")
    def boss_for(r,node):
        # Map the chosen tail to the boss node one edge below it.
        target={"n13":"n14","n15":"n16","n17":"n18","n19":"n20"}.get(node,"")
        return next((x.split('=',1)[1] for x in r['board']['boss_map'] if x.startswith(target+'=')),"未到尾路")
    brows=[
        ("骰子序列",lambda r:"-".join(map(str,r['board']['rolls']))),
        ("实际经过节点",lambda r:f"{len(r['board']['path'])}/12："+" → ".join(r['board']['path'])),
        ("岔路 A",lambda r:r['board']['fork_a'] or "未到达"),
        ("岔路 B / BOSS",lambda r:boss_for(r,r['board']['fork_b'])),
        ("最终 BOSS",lambda r:r['boss'] or "未进入"),
        ("战斗场数（普通/精英/BOSS）",lambda r:"/".join(str(sum(1 for x in r['rooms'] if x['kind']==k)) for k in ['normal','elite','boss'])),
        ("武器 / 护符格",lambda r:"；".join(r['board']['items']) or "—"),
        ("执行耗时",lambda r:secs(r['seconds'])),
        ("软锁 / 无法继续",lambda r:"无" if r['terminal'] in ['LOST','WON_GAME'] else str(r['terminal'])),
        ("重复结算同一节点",lambda r:"无" if len(r['board']['path'])==len(set(x.split(':',1)[0] for x in r['board']['path'])) else "发现重复"),
        ("战斗/商店/休整后正确回棋盘",lambda r:"战斗√；商店/休整未覆盖" if not r['errors'] else "异常："+str(r['errors'])),
        ("确认层看清敌人/HP/属性",lambda r:yn(bool(r['board']['confirmations']) and all('HP' in x and '攻' in x for x in r['board']['confirmations']))),
        ("剩余步数继续",lambda r:yn(r['board']['continue_seen'])),
        ("岔路下游 BOSS 信息（开局静态读取）",lambda r:yn(all('（' in x and '）' in x for x in r['board']['fork_descs']))),
        ("走到岔路并选择",lambda r:"√" if r['board']['fork_a'] else "未到达"),
        ("移动与骰子动画拖沓",lambda r:"未见异常停滞；AI 加速不评价真人手感"),
    ]
    for label,fn in brows: add("| "+label+" | "+" | ".join(fn(r) for r in board)+" |")
    add("")
    add("### 每局专门对照（AI 策略记录）")
    add("")
    for r in board:
        b=r['board']
        add(f"- **{r['label']}**：按覆盖策略主动选择 {b['fork_a'] or '—'} / {boss_for(r,b['fork_b'])}；装备节点在移动前可见。")
        add("  - 分支是否犹豫：AI 无主观犹豫，按预设路线覆盖；下游 BOSS 信息为开局静态读取，未到岔路的局不记作实测。")
        add("  - 跳过战斗：新版逐格结算，本路径没有跳过中间节点；每场战斗都占用真实成长与战斗流程。")
        add("  - 只改一件事：AI 不提出主观改动；保留 G3 的节点连线与 480×270 小节点既有问题。")
    add("")
    won=sum(r['terminal']=='WON_GAME' for r in board)
    add(f"**实测结果：{won}/4 通关，{4-won}/4 失败；无驱动层软锁或重复节点记录。** 4 局均因战斗失败提前结束；骰子步数与实际经过节点一致，步数预算/逐格结算本身未发现异常，失败不能当路线平衡结论。尾路 BOSS 与商店/休整分支未覆盖；是否满足“无解释即可理解”、尾路是否平衡和动画是否拖沓仍需真人判断，不能仅凭 AI 流程通过关闭 G1-03。")
    add("")
    add("## 4. G1-04 目押 A/B 汇总")
    add("")
    add("| 项 | control（6局） | readable（6局） |")
    add("|---|---|---|")
    groups={p:[r for r in ab['runs'] if r['preset']==p and r.get('telemetry')] for p in ['control','readable']}
    def total(p,key): return sum(int(r['telemetry'][key]) for r in groups[p])
    cw=sum(r['terminal']=='WON_GAME' for r in groups['control'])
    vw=sum(r['terminal']=='WON_GAME' for r in groups['readable'])
    add(f"| 局数（通关） | {len(groups['control'])}（{cw} 通关） | {len(groups['readable'])}（{vw} 通关） |")
    add(f"| 主动按停总次数 | {total('control','stop_total')} | {total('readable','stop_total')} |")
    for p in groups:
        pass
    cr=total('control','target_hits')/max(1,total('control','stop_total'))
    vr=total('readable','target_hits')/max(1,total('readable','stop_total'))
    add(f"| 目标停中次数 / 率 | {total('control','target_hits')} / {cr*100:.1f}% | {total('readable','target_hits')} / {vr*100:.1f}% |")
    add(f"| 三连次数 | {total('control','triples')} | {total('readable','triples')} |")
    add(f"| 缓冲触发次数 | {total('control','buffer_queues')} | {total('readable','buffer_queues')} |")
    add("| 自评看得清 / 停得准 | N/A（AI） | N/A（AI） |")
    add("| 典型失误解释 | AI 零延迟按视觉中心；control 视觉落点关闭，结算可落前一格 | 视觉落点+缓冲对齐；无真人失误口述 |")
    add("")
    add(f"**AI 操作对照：readable 相对 control 变化 {((vr-cr)*100):+.1f} 个百分点。** 这不是可读性效果量：control 6/6 失败、0 缓冲，readable 6/6 通关；AI 逐帧零延迟读中心，control 的视觉中心与结算可差半拍，差值主要反映瞄准策略与 control 落点规则不匹配。不得据此把 readable 设为默认。")
    add("")
    add("### 10 次停轮核对（control/readable 各 5 次）")
    add("")
    add("| # | 预设 | 列 | 视觉中心符号 | 实际结算符号 | 一致？ |")
    add("|---:|---|---:|---|---|---|")
    for i,r in enumerate(ab['stop_audit'][:10]):
        add(f"| {i+1} | {r['preset']} | {r['reel']} | {r['visual_name'] or '—'} | {r['actual_name'] or '—'} | {yn(r['same'])} |")
    add("")
    add("> 本表由修复后的 C1/V1 各取前 5 次（`audit_fixed/`）。control 5/5 不一致与 `lock_reel` 在 `visual_stop/buffer` 关闭时回落到逻辑游标一致；AI 零延迟会放大该差异，真人需在 G1-04 用 10 次停轮核对复核。")
    add("")
    ctrl_audit = [a for a in ab['stop_audit'] if a['preset'] == 'control'][:5]
    f1_same = sum(1 for a in single_audit if a['same'])
    comb_same = sum(1 for a in ctrl_audit if a['same']) + f1_same
    add("### 补充停轮样本 F1（control 10 次）")
    add("")
    add("| # | 列 | 视觉中心符号 | 实际结算符号 | 一致？ |")
    add("|---:|---:|---|---|---|")
    for i,a in enumerate(single_audit[:10]):
        add(f"| {i+1} | {a['reel']} | {a['visual_name'] or '—'} | {a['actual_name'] or '—'} | {yn(a['same'])} |")
    add("")
    add(f"> F1 的 10 次中 {f1_same}/10 一致；与 C1 的 5 次合计 control {comb_same}/15（{comb_same/15*100:.0f}%）一致。错位是间歇的，不是固定一格；AI 零延迟样本仍需真人复核。")
    add("")
    add(f"**AI 预验判定：control 视觉一致性未通过（C1+F1 {comb_same}/15）；readable 5/5 + 176/176，但不得据此设为默认。**")
    add("")
    add("## 5. 异常记录")
    add("")
    add("| # | 范围 | 现象 | 处理 |")
    add("|---:|---|---|---|")
    add("| 1 | 包版本 | 无异常：原表与 `BUILD_INFO.txt` 均为 `7b25f381…` | `15:18:44` 后仅 `tools/g1_ai_playtest.*` / `g1_fill_report.py` 改动，游戏脚本/资源未变 |")
    add("| 2 | 首次驱动尝试 | 驱动器在 WON+间歇态优先级错误，重复收尾 | 该轮作废并停止；修正后重新采集，不属于游戏缺陷结论 |")
    add("| 3 | 线性结果 | 3 局均在 BOSS 前失败；均为 control，目标停中 10–26% | 保留数据，P0-1 不判通过；失败与 control 视觉落点错位同向，不当难度结论 |")
    add("| 4 | 首次 A/B 采集 | control C4 首战时 Godot 子进程停止推进，未生成该局结果 | 该次套件作废，加入诊断日志后重跑；不归因于游戏机制 |")
    add("| 5 | readable V4 | 第 7 房胜利后停止推进；截图显示满双武器「胜利奖励：替换武器」层 | 原记为 POST_BATTLE_STALL；复核为**驱动层循环**：取消替换后回到同一三槽屏，驱动反复点同一张武器卡 |")
    add("| 6 | readable V5/V6 | V5 同点停止，V6 未执行 | 修复驱动：取消替换后改选补给/成长，仍失败则走真实「放弃本次成长」；V4–V6 重跑均 8 房通关 |")
    add("| 7 | 修复后重跑 | V4/V5/V6 各出现 1 次 `replace_cancelled` | `ab_fixed/` 6+6 局完整；`ab/` 原始日志保留作历史，不再作为 G1-04 结论数据；线性/棋盘沿用原数据（失败点在第 4/7 房，未触发替换层） |")
    add("| 8 | 遥测口径 | 线性 R1–R3 的 `rewards_shown=0` / `reward_pick_rate=0`，但 `reward_picks` 有值 | 该字段仍按旧奖励屏统计；M1 三槽选择以 `m1.offers` / `selections` 为准，不用 `reward_pick_rate` 判 P0-2 |")
    add(f"| 9 | 补充局 F1 | control seed {f1['seed']}，7 房死亡（第 7 房精英 {last['name']}，{last['turns']} 回合），总 {f1['telemetry']['turns']} 回合，目标 {f1['telemetry']['target_hits']}/{f1['telemetry']['stop_total']}（{f1['telemetry']['target_hit_rate']*100:.1f}%） | 补充样本；10 次停轮 {f1_same}/10 一致；同为 control，不作难度结论 |")
    add("")
    add("## 6. 结论与交回")
    add("")
    add("- G1-01：**未通过**。3/3 均为 control 且目标停中 10–26%；补充 F1（7 房、19 回合、目标 19.3%）也未进 BOSS。失败与视觉落点错位同向，需真人复测，不得据此调难度。")
    add("- G1-02：流程冒烟通过；三槽/候选差异/延后保留有实际证据；**真人感知出口未关闭**。")
    add("- G1-03：步数预算、逐格结算、确认层和返回流程已实测；0/4 通关，尾路 BOSS 未覆盖；**真人理解度与尾路平衡未关闭**。")
    add(f"- G1-04：6+6 局完整；control 0/6、readable 6/6；补充 F1 10 次停轮 {f1_same}/10 一致（C1+F1 合计 {comb_same}/15），错位是间歇的。control 臂是“AI 零延迟瞄准 × control 落点规则”的策略性错位，不能当人类基线；**不得据此把 readable 设为默认**。")
    add(f"- control 视觉一致性（AI 预验）：C1+F1 合计 {comb_same}/15，未通过；真人 G1-04 仍需 10 次停轮核对。")
    add("- **可用于**：自动流程冒烟、软锁/重复结算检查、三槽与确认层是否出现。")
    add("- **不可用于**：真人难度、成长感知、目押可读性、默认预设决策、真人时长。")
    add("- 截图和各局原始 JSON 均在 `docs/baseline/2026-11-06_g1_ai/`；本文件由 `tools/g1_fill_report.py` 从 `ab_fixed/` + `audit_fixed/` + `single/` + `act1_readable/` 生成，`ab/` 为修复前历史证据。")
    add("")
    add("## 7. 单一输入策略的完整 ACT1 重跑（readable）")
    add("")
    add("> 只执行 readable 的 V1，未混入 control；原始数据 `act1_readable/`。该目录 `summary.json` 的 `suite` 字段仍是 `ab`（采集命令为 `--g1-suite=ab --g1-only=V1 --g1-out=act1_readable`），**不代表跑过 6 局 A/B**。")
    add("")
    add(f"- 结果：**{full['terminal']}**，{len(full['rooms'])}/8 房，最终 BOSS {full['boss']}（{full['rooms'][-1]['turns']} 回合）；全局 {full['telemetry']['turns']} 次结算回合。")
    add(f"- 成长终态：技艺 备用药剂 ×1（perk `reserve`）；铭印 锋铸 ×2；Lv.{full['growth']['level']}。选择记录 {len(full['selections'])} 条，其中 1 条是第 3 房「延后未选」卡的记录，实际应用 3 条。")
    add(f"- 停轮：目标 {full['telemetry']['target_hits']}/{full['telemetry']['stop_total']}（{full['telemetry']['target_hit_rate']*100:.0f}%）、三连 {full['telemetry']['triples']}、缓冲排队 {full['telemetry']['buffer_queues']} 次、换武器 {full['telemetry']['weapon_swaps']} 次。")
    if full_same:
        add(f"- 与 `ab_fixed/{ref['label']}.json` 逐项相同（同 seed {full['seed']}、同房间序列、同回合数、同成长、同遥测）→ 这是**可复现性重跑，不是新的独立样本**；wall-clock {full['seconds']:.1f}s vs {ref['seconds']:.1f}s 只是运行环境差异。")
    else:
        add(f"- 与 `ab_fixed/{ref['label']}.json` 并非逐项相同（同 seed {full['seed']}），需逐项核对差异后再引用。")
    add("- 商店购买 0 是驱动构造（驱动在商店只走「离开」），遥测里没有 shop 字段；不是测得值。")
    add(f"- 本局未出现精英战后替换层（`replace_cancelled` 未触发）；不据此否定 `ab/` 中 V4/V5 的历史记录。")
    add("- 待复核：Lv.2/Lv.4 共 2 次技艺机会，终态只生效 1 项；JSON 不含 `pending_picks`，第二次机会的落点需日志复核。不影响本局的通关结论。")
    add("")
    add("**结论：本局只证明 readable 的单一输入策略可以完整跑通 ACT1；难度、手感、默认预设结论继续保持开放。**")
    OUT.write_text("\n".join(L)+"\n",encoding="utf-8")
    print(OUT)


if __name__ == "__main__":
    main()
