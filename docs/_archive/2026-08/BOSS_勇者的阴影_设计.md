# BOSS · 勇者的阴影（The Hero's Projection / Shadow）设计

> 状态：**✅ 已落地（2026-08-10，Step 1-5 完成；F6 实机待验）**——`shadow_projection_gimmick.gd`（P1 每 2 回合随机复刻 8 个 BOSS 机制（gimmick 实例复用：实例化既有 gimmick 脚本调 on_turn_begin，零复制代码，不调 on_room_start 避免房级副作用）→ P2 HP<66% 深渊镜像：投影池追加注废/人格裂变 + 每回合镜像玩家停轮符号（×1+base×0.05）+ 意图 40/30/30 chaos → P3 HP<20% 终极和解：HP 锁 1 无法击杀 + 意图 none + 三条件通关（任意三连 on_special_triple / 转出 heal 符号 on_turn_resolved / 使用 heal/purify/cleanse 消耗品 on_consumable_used），全参数化 gimmick_params）+ `hero_shadow.tres`（600/30/40 · none · final_boss · 无战利品池——通关即整局胜利）。核心小改 3 处：`on_consumable_used` 基类钩子（consumable_system 使用后调用）+ `resolve_peaceful_win` 公开方法（训练点+奖励屏+元进度+spin 流程 early return）+ HP 锁 1 兜底。**非暴力和解结局验收关**（BOSS 池 12/12 齐 + 真·最终落地；组合型新解法规范豁免——复刻验收）。
> 关联：T10（阶段化终局：三阶段·全机制投影）、T4（BOSS 池 **12/12 齐 + 真·最终落地**）、T25（final_boss 标记）、**组合型新解法规范豁免**（真·最终 = 复刻验收，其「解法」= 前 11 个 BOSS 全部组合型新解法的总和，不新增内容——见 §5.2）、单侧性纪律。
> 草案原型：BOSS设计草案 §12（荣格阴影：你无需战胜心理疾病，只需学会与它握手言和）——本稿按 2026-08-10 规范细化定稿（P3 转轮改造（光/暗/心形符号池）简化为「锁 HP 1 + 杀伤意图消失 + 和解条件检测」——非暴力目标等价达成，零转轮改造风险）。

---

## 1. 定位与特色

**真·最终 BOSS（终局验收 + 非暴力结局）**：独立战（final_boss 标记，不在候选池），通关 Act3 后追加为整局最后一间。三阶段 = 心理治疗叙事的机制化：直面投影（复习全部 BOSS 机制）→ 镜像对峙（直面自己的输出）→ 终极和解（放下武器）。

```
P1 躯体与焦虑的投影（HP 100% → 66%）：每 2 回合随机复刻前 8 个 BOSS 机制之一（铁瓮叠甲/石像鬼反弹/酸蚀毒/茧居节律/低语锁轮/元素使躁抑/审判官律法/虚空剥夺）
P2 深渊与创伤的镜像（HP 66% → 20%）：复刻 Act3 机制（注废/三元素切换）+ 每回合镜像玩家转轮符号回敬
P3 终极和解（HP < 20% 触发）：敌人 HP 锁 1、杀伤意图消失——达成和解（三连匹配 / 治疗符号 / 恢复净化消耗品）即通关
```

**定位**：全游戏终局——P1/P2 是 11 个 BOSS 机制的随机「期末考」（对策复盘：破甲/抗扰/净化/冰火克制/目押/洗盘/装备独立），P3 是叙事结局（非暴力解法，HP 锁 1 无法击杀）。**通关不是杀死它，而是理解它**。

## 2. BOSS 数值表

| 项 | 值 | 说明 |
|---|---|---|
| 名称 | 勇者的阴影（The Hero's Shadow） | 游戏内显示名随 .tres 的 name |
| 元素 / 弱点 | **none**（混沌/全元素适应） | 克制恒中性（×1.0）——纯输出验收，无克制捷径 |
| HP / ATK | **600 / 30**（ante 后 ≈5600 / 143，ria=8） | 终局大血池（深渊监视者 460 之上）——P3 后锁 1 不可击杀 |
| 基础护甲 | **40** | 厚甲（P2/P3 穿透价值） |
| 阶段 / 角色 | **三阶段**（P2 HP<66% / P3 HP<20%）/ **final_boss** | 独立战（不在候选池） |
| 意图（P1） | **attack 40 / heavy 40 / jam 20** | 复刻机制为主，普通攻击辅助 |
| 意图（P2） | **attack 40 / heavy 30 / chaos 30** | 镜像期 + 乱权（chaos purifiable） |
| 意图（P3） | **none**（杀伤意图消失） | 和解期——敌人不再攻击 |
| 玩家侧 MISS | 带子按装备 hit_rate 聚合 MISS 格（10-22%） | 期末考基本功——MISS 即白吃复刻机制 |

## 3. 机制（shadow_projection 万象投影，全参数化 T24）

### 3.1 P1 躯体与焦虑的投影（HP 100% → 66%）

- **机制复刻**：每 `projection_every` 回合（默认 2）从投影池随机抽 1 个既有 gimmick 实例，调用其 `on_turn_begin(ctrl)`——直接复用 8 个已落地 BOSS 机制（零复制代码）：
  `rust_armor`（叠甲）/ `glass_cannon`（反弹）/ `acid_bomb`（玩家毒层）/ `cocoon_cycle`（周期甲节律）/ `whisper_lock`（锁轮）/ `bipolar_phase`（躁抑·仅 P1 行为）/ `compulsion_rule`（律法）/ `emotional_vacuum`（**注意：复刻仅调 on_turn_begin，不调 on_room_start——剥离/注废等房级副作用不触发**）。
- 日志「🌘 投影：复刻【X 机制】！」——玩家识别机制即对策（期末考）。
- 意图 attack 40 / heavy 40 / jam 20。

### 3.2 P2 深渊与创伤的镜像（HP < 66% 触发，一次性）

- **复刻升级**：投影池追加 Act3 机制（`abyss_erosion` 注废 / `split_ego` 人格切换——**仅 P1 愤怒行为**）。
- **镜像回敬**：每回合从玩家当前符号池随机抽 1 符号，敌人本回合伤害额外 ×（1 + 符号 base × `mirror_base_per`，默认 0.05）——「你用什么，它就还你什么」（镜像 = 玩家的输出反噬）。
- 意图 attack 40 / heavy 30 / chaos 30（乱权，可净化）。
- 触发瞬间日志 + 飘字「🌗 深渊镜像：你的符号被回敬」。

### 3.3 P3 终极和解（HP < 20% 触发，一次性，非暴力）

- **HP 锁 1**：此后所有伤害结算后 `enemy_hp = maxi(1, enemy_hp)`——**无法击杀**（on_damaged 强制）。
- **杀伤意图消失**：`enemy_intent = none`（每回合保持，敌人不再攻击）；日志「🌕 勇者放下武器，走向投影」。
- **和解条件**（任一达成即通关，`resolve_peaceful_win`）：
  a) 任意符号三连匹配（`on_special_triple` 钩子，同元素三连亦可）；
  b) 本回合转轮打出治疗（heal）符号（`on_turn_resolved` 检测 grid）；
  c) 使用恢复/净化类消耗品（`on_consumable_used` 新钩子：heal/purify/cleanse）。
- 达成 → 日志「🤝 你与阴影握手言和」+ 飘字 + 通关（训练点 + 奖励屏 + 元进度——`resolve_peaceful_win` 公开方法）。

### 3.4 与已有 BOSS 的差异化

| BOSS | 阶段机制 | 正解轴 |
|---|---|---|
| 前 11 个 BOSS | 各验收单轴 | 各专项对策 |
| 勇者的阴影（真·最终） | **全机制投影 + 镜像 + 非暴力和解** | **全对策综合 + 放弃击杀** |

- **期末考**：P1/P2 复刻 = 前 11 个 BOSS 机制的随机组合——破甲/抗扰/净化/克制/目押/洗盘/装备独立全部可能被考。
- **和解结局**：P3 非暴力——常规 BOSS 的「击杀」逻辑在此反转（HP 锁 1），通关 = 达成理解（三连/治疗/净化）。

### 3.5 参数化（gimmick_params）
```json
{"projection_every": 2, "mirror_base_per": 0.05,
 "phase2_hp_ratio": 0.66, "phase3_hp_ratio": 0.2}
```

## 4. 对策与联动（解法矩阵）

| 对策轴 | 具体 | 联动 |
|---|---|---|
| **综合·P1/P2** | 前 11 个 BOSS 的全部解法（破甲/抗扰/净化/冰火克制/目押/洗盘/裸输出）——随机抽考 | 期末考 = 全对策复习 |
| **镜像·P2** | 镜像 = 玩家符号反噬——输出越高镜像越痛（×1+base×0.05）→ **降速蓄力**（攒充能/三连一击，少散打） | 镜像期节奏管理 |
| **和解·P3** | 三连匹配（任意符号）/ 治疗符号（heal）/ 恢复净化消耗品 | 非暴力通关——任何一项即可 |
| **基础功** | MISS 按停规避 | 期末考基本功（MISS = 白吃复刻） |

**节奏参考**：P1/P2 随机复刻机制——识别 + 对症（如投影锁轮 → 净化/目押；投影叠甲 → 破甲/穿透）→ HP<20% 敌人放下武器：达成任意和解条件即通关（不再输出击杀）。

## 5. 内容清单

### 5.1 房间与战利品

| 房间 | kind | 元素 | hp/atk/甲 | 角色 | 战利品 | 状态 |
|---|---|---|---|---|---|---|
| 勇者的阴影 | boss | none | 600/30/40 | final_boss | **无主题池**（通关即整局胜利 → 元进度 + 铁砧） | 【新增】 |

> 真·最终无常规战利品（通关即结算：训练点 +1 → 训练房 → 元进度三选一 → 铁砧，与整局结束衔接）。

### 5.2 解法·基线可解 + 组合型新解法（规范 §6 **豁免**）

| 阶段 | 类型 | 内容 | 状态 |
|---|---|---|---|
| — | **基线可解** | 前 11 个 BOSS 的既有对策框架内可通关（复刻 = 复习）；P3 三连/治疗符号/消耗品全为既有内容 | ✅ 成立 |
| — | **组合型新解法豁免** | 真·最终位**不新增内容**——P1/P2 复刻 = 前 11 个 BOSS 全部组合型新解法（约 50 件）的**随机总和**，新内容对「复习考」无意义；其「新解法」即全部既有内容。豁免理由：组合型新解法规范（§6）服务于「该 BOSS 特色解法」，真·最终特色 = 复刻验收而非新内容（2026-08-10 拍板） | ✅ 豁免 |

## 6. 实现步骤（P1/P2 复刻 = gimmick 实例复用（实例化既有 gimmick 脚本调 on_turn_begin，统一 BossGimmick 签名，零复制代码；注意不调 on_room_start——房级副作用不触发）；P3 和解 = 三处核心小改）

| 步骤 | 内容 | 改动文件 | 验证点（F6） |
|---|---|---|---|
| Step 1 · 核心小改 | boss_gimmick.gd 基类加 `on_consumable_used(ctrl, effect: String)`（pass）；consumable_system 使用后调用（显式判空）；duel_controller 加 `func resolve_peaceful_win()`（game_state=WON + 训练点 + 奖励屏 + _busy 复位——和解通关走此入口） | `scripts/battle/gimmicks/boss_gimmick.gd` / `scripts/systems/consumable_system.gd` / `scripts/battle/duel_controller.gd` | 消耗品使用通知、和解通关流程（训练点+奖励屏） |
| Step 2 · gimmick 脚本 | `shadow_projection_gimmick.gd`：preload 10 个既有 gimmick 脚本实例化（不调 on_room_start）；on_room_start 读参 + 开场日志；on_turn_begin P1/P2 按 projection_every 随机抽 1 实例调 on_turn_begin(ctrl)（日志「🌘 投影：X」）+ P2 镜像（池随机符号 → boss_atk_mult ×(1+base×mirror_base_per)）+ P3 保持意图 none + 意图覆盖（P2 表 roll_intent）；on_damaged HP<66%/20% 一次性切 P2/P3（P3：日志飘字「🌕 放下武器」）；on_special_triple P3 且未和解 → resolve_peaceful_win；on_turn_resolved P3 检测 grid 含 heal 符号 → resolve_peaceful_win；on_consumable_used P3 且 effect ∈ heal/purify/cleanse → resolve_peaceful_win；P3 时 on_damaged 强制 hp=maxi(1,hp)；ICON 🌘 | `scripts/battle/gimmicks/shadow_projection_gimmick.gd` | 复刻随机抽考、镜像加成、P3 锁 1/意图 none/三条件和解 |
| Step 3 · 房间 .tres | 勇者的阴影：600/30/40 · none · kind=boss · act=3 · final_boss=true · boss_role=fixed · intents(P1 attack 40/heavy 40/jam 20 内联) · gimmick_params · 无战利品池 | `resources/rooms/` 新增（hero_shadow.tres） | 通关 Act3 后追加、P2/P3 触发 |
| Step 4 · 文档回写 | 总清单 T4 BOSS 池 **12/12 + 真·最终落地**；规范 §12 进度表同步；项目概览 BOSS 表 | `docs/未完成任务_总清单.md` / `docs/BOSS设计规范.md` / `docs/项目概览_状态与内容.md` | — |
| Step 5 · F6 验证 | 见 §7 清单 | — | 全绿 |

## 7. F6 验证清单

- [ ] 通关 Act3 后勇者的阴影追加为整局最后一间（final_boss 独立战）
- [ ] P1：每 2 回合随机复刻 8 个 BOSS 机制之一（日志「🌘 投影：X」），机制行为与原型一致
- [ ] 复刻不触发房级副作用（不剥护符/不重置 boss_trash——emotional_vacuum/abyss_erosion 仅 on_turn_begin 行为）
- [ ] HP<66% 一次性触发 P2（日志/飘字「🌗 深渊镜像」）
- [ ] P2：投影池追加 Act3 机制（注废/人格切换）、每回合镜像玩家符号（伤害 ×1+base×0.05）、意图 attack 40/heavy 30/chaos 30（chaos 可净化）
- [ ] HP<20% 一次性触发 P3（日志/飘字「🌕 放下武器」），不重复触发
- [ ] P3：enemy_hp 锁 1（无法击杀）、意图 none（敌人不攻击）
- [ ] P3 三条件和解：a) 任意三连 → 通关；b) 转出 heal 符号 → 通关；c) 使用 heal/purify/cleanse 消耗品 → 通关
- [ ] 和解通关：训练点 +1 → 奖励屏 → 元进度 → 铁砧衔接正常（resolve_peaceful_win）
- [ ] 普通 BOSS 房零影响（on_consumable_used 显式判空、resolve_peaceful_win 仅被调才生效）

## 8. 关联

- 总清单 **T10**（阶段化终局：三阶段·全机制投影验收）、**T24**（gimmick 参数化）、**T4**（BOSS 池 **12/12 齐 + 真·最终落地**）、**T25**（final_boss 标记）、**组合型新解法豁免**（真·最终 = 复刻验收，不新增内容，2026-08-10 拍板）
- 结构参照：BOSS_深渊监视者_设计.md（三阶段范例）；本 BOSS 为 **真·最终·投影验收 + 非暴力和解型**
- 机制先例：三阶段一次性触发（on_damaged + 参数阈值）、意图切换覆盖（roll_intent）、on_turn_resolved（天平审判官）、gimmick 实例复用（**新**：实例化既有 gimmick 脚本直接调用——零复制代码）；**无先例（新增）**：on_consumable_used 钩子、resolve_peaceful_win 和解通关、HP 锁 1
