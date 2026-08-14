# BOSS · 天平审判官（The Inquisitor of Order）设计

> 状态：**✅ 已落地（2026-08-10，Step 1-5 完成；F6 实机待验）**——`compulsion_rule_gimmick.gd`（每 2 回合宣告 1 条律法（纯律/清规/杀律，基于停轮后 grid/grid_elem 判定）——达成 → 敌方攻击 ×0.5 安全窗口；未达成 → 重击 ×2（P2 额外锁 1 个消耗品槽 1 回合）；HP<50% 一次性进 P2：甲 20→35 + 攻 ×0.9 + 意图 40/30/30 + 惩罚升级锁槽，全参数化 gimmick_params）+ `scale_inquisitor.tres`（300/17/20 · light · rotating · 暗系战利品池 T32）。**组合型新解法 4 个全部落地**（阶段数 × 2）：暗影铡刀 shadow_guillotine / 审判天平 scales_of_judgment（×1.2）/ 赦免令 absolution_decree（reroll ×2）/ 秩序光环 aura_of_order（buff 盾 +10）。核心小改两处：`on_turn_resolved` 钩子（combat.evaluate 玩家结算完成后通知，空转回合也判定，零结算改动）+ `locked_consumable_slot` 锁槽（controller 字段 + HUD 腰带禁用 1 回合，回合开始复位）；`use_reroll` 循环 value 次支持赦免令连转。**规则应变验收关**（低语者=干扰、元素使=元素、审判官=目押律法）。
> 关联：T10（BOSS 阶段化·Act2 双阶段轮替示例）、T24（gimmick_params 参数化）、T4（BOSS 池 8/12→9/12）、T25（rotating 权重 3 入 Act2 BOSS 槽 4 候选）、**T32（BOSS 主题武器掉落——弱暗掉暗系池，随暗影铡刀补池）**、**组合型新解法规范（2026-08-10：阶段数 × 2）**、单侧性纪律。
> 草案原型：BOSS设计草案 §7（强迫症与完美主义「律法强迫 compulsion_rule」）——本稿按 BOSS 设计规范 2026-08-10 重置版细化定稿（规则池落地为 3 条可判定律法、惩罚升级落地为「重击 + 锁消耗品槽」）。

---

## 1. 定位与特色

**Act2 双阶段 BOSS（规则应变型）**：Act2 BOSS 槽「4 候选选 1」的 **rotating 候选**（fixed 呓语教徒权重 6 / rotating 迷宫低语者 3 / rotating 躁怒元素使 3 / rotating 天平审判官 3 ≈ 18.5%）。双阶段 = 强迫症的机制化：规则宣告（必须达成秩序，否则受罚）→ 严刑惩戒（未达成者被记录、被剥夺）。

```
P1 规则宣告（HP 100% → 50%）：每回合宣告 1 条「律法」——达成 → 本回合敌人攻击 ×0.5；未达成 → 重击 ×2
P2 严刑惩戒（HP < 50% 触发一次）：护甲 20→35、攻击 ×0.9、惩罚升级 = 重击 + 锁 1 个消耗品槽 1 回合 + 注废骚扰（jam 可净化）
```

**定位（与低语者/元素使错位）**：低语者验收「干扰抗性」（锁轮+乱权）、元素使验收「元素应变」（属性切换）、审判官验收「**目押规则应变**」——转轮三列不再只按「输出/克制」停，而是按「律法条件」停：达成条件 = 输出窗口（敌方攻击减半），违反 = 白吃重击。**带错停法 = 高额惩罚**，目押基本功与转轮条带结构（传统 slots 档位制）双重验收。

**规则达成率设计意图**：3 条律法覆盖不同条带结构（同元素 / 全异 / 全攻击），任意条带总有 ≥1 条可目押达成（MISS/废铁格算「异/非攻击」——清规、杀律天然被废铁格助成），惩罚是「选择」而非「陷阱」：输出与遵从不可兼得时，玩家主动取舍。

## 2. BOSS 数值表

| 项 | 值 | 说明 |
|---|---|---|
| 名称 | 天平审判官（The Inquisitor of Order） | 游戏内显示名随 .tres 的 name |
| 元素 / 弱点 | **light** / 弱 **dark** | 克制 v2：互克对 光↔暗——暗武克制（night_scythe / shadow_dagger / #1 暗影铡刀） |
| HP / ATK | **300 / 17**（ante 后 ≈1400 / 48，ria=7） | Act2 基准（教徒 290/20、低语者 300/16、元素使 280/18）——均衡型，惩罚即输出 |
| 基础护甲 | **20** → P2 重设 **35** | P1 轻甲（律法威慑）；P2 厚甲（严刑固防） |
| 阶段 / 角色 | **双阶段**（P2 HP<50%）/ **rotating** | Act2 BOSS 槽 4 候选（fixed 6 : rotating 3 : rotating 3 : rotating 3） |
| 意图（P1） | **attack 60 / heavy 40** | 规则回合意图栏被「⚖ 律法·X」覆盖（见 §3.1）；平时攻击 60 权重为主 |
| 意图（P2） | **attack 40 / heavy 30 / jam 30** | 低攻 + 注废骚扰（jam purifiable，净化药剂可抵消）——惩戒期阴损 |
| 玩家侧 MISS | 带子按装备 hit_rate 聚合 MISS 格（10-22%） | 全局基本功；MISS 格 = 清规/杀律的「天然助成格」也 = 白转回合 |

## 3. 机制（compulsion_rule 律法强迫，全参数化 T24）

### 3.1 P1 规则宣告（HP 100% → 50%）

- **每 rule_every 回合宣告 1 条律法**（默认 2：宣告回合与自由回合交替，自由回合走意图表——P1: RoomData.intents attack 60/heavy 40；P2: attack 40/heavy 30/jam 30，jam 有出场节奏）：从 `rule_pool` 随机抽 1 条，覆盖 `enemy_intent` 显示（构造临时 IntentData：`type="rule"` + `display_name="律法·纯律/清规/杀律"` + `icon="⚖"`，HUD 意图栏 `_:` 分支已兼容）——**玩家在 spin 前看到本回合规则**。
- **判定**（玩家停轮结算完成后，`on_turn_resolved` 钩子，基于停轮后三列顶格 `grid[0..2][0]`）：
  | 律法 | id | 达成条件 |
  |---|---|---|
  | 纯律 | same_element | 三格有效元素全部相同（含 none 元素，同元素 ×0.85 惩罚也计「相同」） |
  | 清规 | all_distinct | 三格符号 `resource_path` 互不相同 |
  | 杀律 | all_damage | 三格 `kind` 全部为 damage（攻击符号） |
- **达成** → 本回合敌人攻击 ×`rule_reward_atk_mult`（默认 0.5，安全窗口）+ 日志「⚖ 律法遵从：敌方攻击减半」。
- **未达成** → 重击惩罚：`enemy_intent` 覆盖为 heavy（value = atk ×2）+ `boss_atk_mult = rule_punish_mult`（默认 2.0）+ 日志「⚖ 律法违逆：重击惩戒！」。
- 达成/未达成判定只影响本回合敌人行动，下一回合重新宣告（cocoon_cycle「每回合重掷」节奏先例）。

### 3.2 P2 严刑惩戒（HP < 50% 触发，一次性）

`on_damaged` 检测 `ctrl.enemy_hp <= ctrl.enemy_hp_max * phase2_hp_ratio` 且未触发过 → 进入 P2：
- **护甲重设**：`enemy_armor_max = p2_armor`（35）补满——严刑固防，破甲/穿透价值回升（同铁瓮/元素使 P2）。
- **攻击回落**：`boss_atk_mult` 基准 ×`p2_atk_mult`（0.9）——惩戒型非暴走。
- **意图切换**：attack 40 / heavy 30 / jam 30（低攻 + 注废骚扰，jam 可净化）——规则回合仍由律法宣告覆盖。
- **惩罚升级**：未达成律法 → 重击 ×2 **且额外锁 1 个消耗品槽**（`p2_lock_consumable` 默认 true：随机锁 1 格腰带按钮 1 回合禁用，日志指明「第 N 格被律法封印」）——强制玩家在「达成律法」与「用消耗品补救」间取舍。
- 触发瞬间日志 + 飘字「⚖ 严刑惩戒：律法升级——违逆者将被封印」。

### 3.3 与已有 BOSS 的差异化

| BOSS | 阶段机制 | 正解轴 |
|---|---|---|
| 迷宫低语者 | P2 干扰增强（锁轮/乱权） | 抗干扰 + 目押 |
| 躁怒元素使 | **P2 属性切换**（火→冰，弱点翻转） | 双元素应变 + 破甲 |
| 天平审判官 | **P2 惩罚升级**（规则 + 锁槽 + 厚甲） | **目押停轮达成律法** + 暗武克制 + 破甲 |

- 与元素使错位：元素使惩罚是「被动承受」（攻 ×2 每回合在），审判官惩罚是「选择」（达成 = 安全回合，未达成 = 自选重击）——同样是双阶段，一个验元素、一个验目押。
- 规则判定 = 全项目首个「玩家转轮结算后」钩子（`on_turn_resolved`），后续 Act3 三阶段 BOSS 的「条件式机制」可直接复用。

### 3.4 参数化（gimmick_params）
```json
{"rule_pool": ["same_element", "all_distinct", "all_damage"], "rule_every": 2,
 "rule_reward_atk_mult": 0.5, "rule_punish_mult": 2.0,
 "phase2_hp_ratio": 0.5, "p2_atk_mult": 0.9, "p2_armor": 35, "p2_lock_consumable": true}
```

## 4. 对策与联动（解法矩阵）

| 对策轴 | 具体 | 联动 |
|---|---|---|
| **克制·主解** | night_scythe 50/78% / shadow_dagger / **暗影铡刀（组合型 #1，dark）**（×1.5） | 暗武克制全程（light 弱 dark，P1/P2 同元素克制不变） |
| **目押·规则** | 三列按律法停轮（纯律留同类列 / 清规停异号 / 杀律停攻击）——MISS/废铁格天然助成清规/杀律 | 达成 = 攻击减半安全回合，惩罚与输出不可兼得时的主动取舍 |
| **洗盘·规则** | **赦免令（组合型 #3，reroll ×2）** + 重转卷轴（已有）——转歪即时重转博规则 | 未达成前的最后补救（P2 锁槽期尤甚） |
| **防御·惩戒窗口** | 守备/铁壁/**霜晶壁垒** + **秩序光环（组合型 #4，buff 盾+10）** + 治疗 | P2 重击 + 锁槽期的生存窗口 |
| **破甲·P2** | 破甲三连 / 破甲符 / 碎甲之印 + **审判天平（组合型 #2，×1.2）** | P2 厚甲 35 强开直击窗口兑击杀 |
| **净化·P2** | 净化药剂（抵消 jam 注废） | P2 骚扰应对（与低语者/元素使衔接） |
| **基础功** | MISS 按停规避 | 白转回合 = 白吃律法重击 |

**节奏参考**：P1 每回合在「遵从律法（攻 ×0.5）+ 暗武输出」中二选一，攒充能/破甲资源 → HP 过半切 P2：甲 35 + 惩罚升级锁槽——玩家按律法停轮为主、破甲/穿透打厚甲窗口、净化抵消注废，拖杀 = 被封印消耗品 + 磨血无效。

## 5. 内容清单

### 5.1 房间与战利品

| 房间 | kind | 元素 | hp/atk/甲 | 角色 | 战利品 | 状态 |
|---|---|---|---|---|---|---|
| 天平审判官 | boss | light | 300/17/20（P2 35） | rotating | **暗系主题武器池**（night_scythe / 暗影铡刀 / iron_sword） | ✅ 已落地 |

> 战利品遵循 **T32**（弱暗 BOSS 掉暗系主题武器——现状暗系 night_scythe/shadow_dagger，随组合型 #1 暗影铡刀补池，2 主题 + 1 通用）；专属信物暂不挂（随 T4/T7，同躁怒元素使）。

### 5.2 解法·基线可解 + 组合型新解法（规范 §6：阶段数 × 2——双阶段 4 个）

| 阶段 | 类型 | 内容 | 状态 |
|---|---|---|---|
| — | **基线可解** | 现有物品框架内可通关：P1 目押停轮（基本功）+ 暗武（night_scythe 已有）+ 重转卷轴（洗盘）+ 护盾撑重击；P2 破甲/穿透打厚甲 + 净化抵消 jam 全为既有内容 | ✅ 成立 |
| P1 | **组合型新解法 #1** | 「暗影铡刀」shadow_guillotine（**新武器**，dark，rare 42/0.86，符号 暗影斩 + 暗影锁链（pierce）w2）——P1 主解强化：暗武 ×1.5 克制 + 穿透直击厚甲，同时补 T32 暗系战利品池 | ✅ 已落地 |
| P1 | **组合型新解法 #2** | 「审判天平」scales_of_judgment（**新护符**，rare，effect=`damage_mult` mult_value=1.2——介于锋锐 ×1.10 / 深渊之瞳 ×1.15 与狂怒 ×1.5 之间的中高档全局乘区）——P1/P2 全程输出强化 | ✅ 已落地 |
| P2 | **组合型新解法 #3** | 「赦免令」absolution_decree（**新消耗品**，rare，effect=`reroll` value=2——一次连转 2 次，覆盖重转卷轴单次）——律法未达成前的洗盘补救，P2 锁槽期反制 | ✅ 已落地 |
| P2 | **组合型新解法 #4** | 「秩序光环」aura_of_order（**新技能**，buff shield +10 持续 2 回合——覆盖定心 8/不屈战旗 6 的高档护盾 buff）——P2 重击 + 锁槽期生存窗口，与赦免令/充能组合拳 | ✅ 已落地 |

## 6. 实现步骤（主逻辑零核心改动：规则宣告走 enemy_intent 覆盖、重击走 boss_atk_mult、厚甲走 enemy_armor、意图切换走覆盖——均有先例；两处单点小改：① `on_turn_resolved` 钩子——combat.evaluate 玩家结算完成后通知 gimmick（空转/MISS 回合也判定），不动任何结算逻辑；② P2 锁消耗品槽——controller `locked_consumable_slot` 字段 + HUD 腰带按钮禁用 1 回合）

| 步骤 | 内容 | 改动文件 | 验证点（F6） |
|---|---|---|---|
| Step 1 · 核心小改 | boss_gimmick.gd 基类加 `on_turn_resolved` 钩子（pass）；combat_system.evaluate 攻击结算后（on_damaged 之后、回合末递减前）调用 `current_gimmick.on_turn_resolved(_ctrl)`（显式判空）；duel_controller 加 `locked_consumable_slot: int = -1`（回合末复位 -1）；battle_hud `_refresh_consumable_panel` 对锁定格按钮 `disabled = true`（回合内不可用） | `scripts/battle/gimmicks/boss_gimmick.gd` / `scripts/battle/combat_system.gd` / `scripts/battle/duel_controller.gd` / `scripts/ui/battle_hud.gd` | 空转/MISS 回合钩子照常触发；锁槽按钮禁用一回合后恢复 |
| Step 2 · gimmick 脚本 | `compulsion_rule_gimmick.gd`：on_room_start 开场日志（读 rule_pool/rule_every）；on_turn_begin 按 rule_every 宣告律法（抽规则 → 覆盖 enemy_intent：临时 IntentData type=rule/display_name=「律法·X」/icon=⚖）+ P2 时覆盖意图表 attack 40/heavy 30/jam 30；on_turn_resolved 读 ctrl.grid 判定律法——达成：boss_atk_mult ×rule_reward_atk_mult（日志）；未达成：覆盖 enemy_intent 为 heavy + boss_atk_mult ×rule_punish_mult，P2 且 p2_lock_consumable 时额外设 locked_consumable_slot（随机 1 格 + hud._refresh_consumable_panel）；on_damaged 检测 HP<50% 一次性进 P2（甲 35 + 日志飘字「⚖ 严刑惩戒」）；参数读 gimmick_params（T24）；ICON ⚖ | `scripts/battle/gimmicks/compulsion_rule_gimmick.gd` | 律法宣告显示、三规则判定正确、达成减攻/未达成的重击与锁槽 |
| Step 3 · 房间 .tres | 天平审判官：300/17/20 · light · kind=boss · act=2 · boss_role=rotating · intents(P1 attack 60/heavy 40 内联) · gimmick_params · 暗系战利品池（T32） | `resources/rooms/` 新增（scale_inquisitor.tres） | Act2 BOSS 槽 4 候选可抽到、P2 触发 |
| Step 4 · 组合型新解法（阶段数 × 2 = 4 个） | #1 暗影铡刀（暗影斩 + 暗影锁链符号 + 武器 .tres）；#2 审判天平（护符 .tres）；#3 赦免令（消耗品 .tres + use_reroll 循环 value 次）；#4 秩序光环（buff 符号 + 技能 .tres）——放入资源目录即入池 | `resources/` 对应目录 | 整备可选、进转轮、数值正确、赦免令连转 2 次 |
| Step 5 · 文档回写 | 总清单 T4 BOSS 池 8/12→9/12；规范 §12 进度表同步 | `docs/未完成任务_总清单.md` / `docs/BOSS设计规范.md` / `docs/项目概览_状态与内容.md` | — |
| Step 6 · F6 验证 | 见 §7 清单 | — | 全绿 |

## 7. F6 验证清单

- [ ] 天平审判官以 rotating 候选进入 Act2 BOSS 槽（4 候选抽取分布 ≈ 6:3:3:3）
- [ ] 规则宣告：意图栏显示「⚖ 律法·纯律/清规/杀律」（spin 前可见），每回合重掷
- [ ] 三规则判定正确（纯律=三格同元素 / 清规=三格全异 / 杀律=三格全攻击；MISS/废铁格按清规/杀律助成）
- [ ] 达成 → 本回合敌方攻击 ×0.5（日志）；未达成 → 重击 ×2（意图变 heavy 数值正确）
- [ ] HP<50% 一次性触发 P2（日志/飘字「⚖ 严刑惩戒」），不重复触发
- [ ] P2：护甲重设 35、攻击 ×0.9、意图 attack 40/heavy 30/jam 30（jam 可净化）
- [ ] P2 未达成律法 → 重击 + 随机锁 1 个消耗品槽按钮 1 回合（锁定格禁用、回合末恢复）
- [ ] 空转/MISS 回合：on_turn_resolved 照常判定（无伤害也判定律法）
- [ ] 暗武克制 ×1.5 + 充能核爆；P2 破甲/穿透直击厚甲生效
- [ ] 暗影铡刀（#1）入池、暗系战利品池完整（T32）
- [ ] 审判天平（#2）：伤害 ×1.2 全局生效；赦免令（#3）：reroll 连转 2 次；秩序光环（#4）：buff 盾 +10 2 回合
- [ ] 通关 → 训练点 +1 → 训练房 → 商店/下一房衔接正常
- [ ] 教学位回归：非 BOSS 房钩子零影响（on_turn_resolved 显式判空，其它 BOSS 无感知）

## 8. 关联

- 总清单 **T10**（阶段化·Act2 双阶段轮替示例：低语者=干扰应变、元素使=元素应变、审判官=规则应变）、**T24**（gimmick 参数化）、**T4**（BOSS 池 8/12→9/12）、**T25**（rotating 权重 3 / RoomData.boss_role）、**T32**（弱暗 BOSS 掉暗系主题——补暗系池缺口）、**组合型新解法规范（阶段数 × 2 = 4 个）**
- 结构参照：BOSS_躁怒元素使_设计.md（Act2 轮替双阶段范例，2026-08-10）；本 BOSS 为 **rotating 位双阶段·规则应变型**
- 机制先例：意图覆盖显示（cocoon_cycle 强制重击 + HUD `_:` 分支读 data.display_name）、重击倍率（boss_atk_mult）、厚甲（enemy_armor_max/enemy_armor）、P2 一次性触发（on_damaged + 参数阈值，whisper_lock/元素使先例）、意图切换覆盖（元素使 P2 表覆盖）；**无先例（新增）**：`on_turn_resolved` 钩子（玩家结算完成通知）、锁消耗品槽（P2 惩罚升级）
- 后续 Act3 三阶段 BOSS（碎裂魔王 split_ego 人格裂变 / 耻辱审判官 shame_counter 罪业清算）的「条件式 / 计数式」机制可直接复用 `on_turn_resolved` 钩子
