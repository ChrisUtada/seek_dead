# BOSS · 无名虚空（The Nameless Void）设计

> 状态：**✅ 已落地（2026-08-10，Step 1-5 完成；F6 实机待验）**——`emotional_vacuum_gimmick.gd`（P1 进房即 `deprived_level=1`：护符全失效 + 开局盾扣回；P2 HP<50% 一次性 `deprived_level=2`：player_buffs 清空 + 下一回合重建条带技能符号出池 + 甲 20→32 + 攻 ×0.85 + 意图 40/30/30，全参数化 gimmick_params）+ `nameless_void.tres`（320/18/20 · dark · hidden · 光系战利品池 T32）。**组合型新解法 4 个全部落地**（阶段数 × 2，品类纪律：避开被剥夺的护符/技能）：晨曦之刃 dawn_blade / 圣光圣杯 holy_grail（heal 60）/ 圣光爆裂 holy_burst（assault ×2×2 次）/ 圣光钉锤 holy_mace（pierce 穿透）。核心小改：`deprived_level` 聚合层开关（controller/state 字段 + agg_*×4/抗扰/破甲/元素/状态/开局盾/`_build_pool` 技能两处循环 ~8 个消费点单点判断，零结算改动；`_apply_charms` 每房重算天然复位）。**装备独立性验收关**（茧居=节奏、无名虚空=装备）。
> 关联：T10（BOSS 阶段化·Act2 双阶段隐秘示例）、T24（gimmick_params 参数化）、T4（BOSS 池 9/12→10/12）、T25（hidden 权重 2 入 Act2 BOSS 槽 5 候选）、**T32（BOSS 主题武器掉落——弱光掉光系，光系已有 3 把无需补池，随晨曦之刃增强）**、**组合型新解法规范（2026-08-10：阶段数 × 2）**、单侧性纪律。
> 草案原型：BOSS设计草案 §8（述情障碍与情感解离「情感剥离 emotional_vacuum」）——本稿按 BOSS 设计规范 2026-08-10 重置版细化定稿（剥离落地为 `deprived_level` 聚合层开关：P1 禁护符 / P2 护符+技能全禁）。

---

## 1. 定位与特色

**Act2 双阶段 BOSS（装备剥夺型）**：Act2 BOSS 槽「5 候选选 1」的 **hidden（隐秘）候选**（fixed 呓语教徒权重 6 / rotating 迷宫低语者 3 / rotating 躁怒元素使 3 / rotating 天平审判官 3 / hidden 无名虚空 2 ≈ 11.8%）。幕内全清后开启（BOSS 槽恒为幕内最后一房，条件恒满足），预告显示？？？不剧透（T25 先例：茧居石雕）。双阶段 = 述情障碍的机制化：情感剥离（护符无效，无法感知加成）→ 全面麻木（技能也无，彻底虚无）。

```
P1 情感剥离（HP 100% → 50%）：玩家护符效果全部失效——只剩武器 / 技能 / 消耗品 / 目押基本功
P2 全面麻木（HP < 50% 触发一次）：技能符号不再入池 + 已挂增益清空——只剩武器 + 消耗品的纯数值拉锯
```

**定位（与茧居石雕/审判官错位）**：茧居石雕（Act1 隐秘）验收「节奏管理」（周期甲窗口）；无名虚空（Act2 隐秘）验收「**装备独立性**」——护符/技能逐层剥离后，高 base 武器（战斧 50 / 夜幕镰刀 50）+ 光武克制（×1.5）+ 消耗品管理成为唯一解法轴。**依赖护符乘区的 build 在这里被打回原形**，纯武器 build 全程不受影响。

## 2. BOSS 数值表

| 项 | 值 | 说明 |
|---|---|---|
| 名称 | 无名虚空（The Nameless Void） | 游戏内显示名随 .tres 的 name |
| 元素 / 弱点 | **dark** / 弱 **light** | 克制 v2：互克对 光↔暗——光武克制（holy_sword / holy_lance / dawn_bow / #1 晨曦之刃） |
| HP / ATK | **320 / 18**（ante 后 ≈1490 / 51，ria=7） | Act2 最高血（隐秘位晚解锁）——威胁不在单发而在「剥夺后的长线」 |
| 基础护甲 | **20** → P2 重设 **32** | P1 中甲；P2 厚甲（全面麻木蜷缩） |
| 阶段 / 角色 | **双阶段**（P2 HP<50%）/ **hidden** | Act2 BOSS 槽 5 候选（fixed 6 : rotating 3×3 : hidden 2） |
| 意图（P1） | **attack 60 / heavy 40** | 朴素攻击剖面——威胁 = 玩家被剥后的输出下降，而非敌人花招 |
| 意图（P2） | **attack 40 / heavy 30 / jam 30** | 低攻 + 注废骚扰（jam purifiable，净化药剂可抵消）——麻木期的阴损 |
| 玩家侧 MISS | 带子按装备 hit_rate 聚合 MISS 格（10-22%） | 装备剥离后 MISS 更致命（白回合 = 白吃 + 白无输出） |

## 3. 机制（emotional_vacuum 情感剥离，全参数化 T24）

### 3.1 P1 情感剥离（HP 100% → 50%）

- **进房即剥离**：`deprived_level = 1`（护符禁）——护符被动全部失效，聚合层中性化：
  - `charm_damage_mult`（×1.2 等乘区）→ 视为 ×1.0；`charm_power_bonus` → 0；`charm_shield_trickle` / `charm_heal_trickle`（每回合盾/回血）→ 0
  - `charm_interf_resist`（抗扰）→ 视为 0（意图折扣取消）；`charm_pierce_chance`（破甲概率）→ 0；`charm_element_boost`（元素加成）→ 0；`charm_status_boost` → ×1.0；`charm_dot_reduce`（蚀毒壁垒）→ 0
  - `charm_room_shield`（守望开局盾）：进房时已入账的 `player_shield` 部分**扣除**（剥离彻底，日志明示）
- 开场日志 + 飘字「⚫ 情感剥离：护符效果失效」——HUD 护符乘区概览同步隐藏（`charm_damage_mult` 显示回落 1.0）。
- 玩家仍保留：武器符号、技能符号、消耗品、已挂回合增益（player_buffs）。

### 3.2 P2 全面麻木（HP < 50% 触发，一次性）

`on_damaged` 检测 `ctrl.enemy_hp <= ctrl.enemy_hp_max * phase2_hp_ratio` 且未触发过 → `deprived_level = 2`：
- **技能失效**：`_build_pool` 技能符号段跳过（下次 `build_strips` 起技能符号不再入池）+ **已挂增益清空**（`player_buffs.clear()`，P2 触发瞬间剥离）——玩家只剩武器符号 + 消耗品。
- **护甲重设**：`enemy_armor_max = p2_armor`（32）补满。
- **攻击回落**：`boss_atk_mult` ×`p2_atk_mult`（0.85）——麻木期低攻。
- **意图切换**：attack 40 / heavy 30 / jam 30（低攻 + 注废骚扰，jam 可净化）。
- 触发瞬间日志 + 飘字「⚫ 全面麻木：技能失效——回归本源」。

### 3.3 与已有 BOSS 的差异化

| BOSS | 阶段机制 | 正解轴 |
|---|---|---|
| 茧居石雕（Act1 隐秘） | 周期甲开合节律 | 节奏管理 + 穿透 |
| 无名虚空（Act2 隐秘） | **装备剥夺**（护符 → 技能逐层剥离） | **裸输出**（高 base 武器 + 光武克制 + 消耗品） |
| 天平审判官 | 律法惩罚（未达成重击 + 锁槽） | 目押停轮 |
| 迷宫低语者 | P2 干扰增强（锁轮/乱权） | 抗干扰 + 目押 |

- 与茧居石雕（同为隐秘位）错位：一个管「敌人防御节奏」，一个管「玩家装备剥夺」——隐秘位双验收轴（节奏 / 独立性）。
- **剥离实现 = 聚合层开关**（F-0 统一查询入口设计哲学）：`deprived_level` 在 agg_* 与消费点单点判断，新增护符 effect 自动被覆盖（不进 `_apply_charms` 外的任何特殊分支）。

### 3.4 参数化（gimmick_params）
```json
{"phase2_hp_ratio": 0.5, "deprive_charms": true, "deprive_skills": true,
 "p2_atk_mult": 0.85, "p2_armor": 32}
```

## 4. 对策与联动（解法矩阵）

| 对策轴 | 具体 | 联动 |
|---|---|---|
| **克制·主解** | holy_sword 45 / holy_lance 40 / dawn_bow 28 / **晨曦之刃（组合型 #1，light）**（×1.5） | 光武克制全程（dark 弱 light，P1/P2 同元素克制不变） |
| **裸输出·P1** | 高 base 无元素武器（战斧 50 / 夜幕镰刀 50）硬刚 | 装备剥离下 base_power 成为主输出轴（草案克制解：高基础面板） |
| **生存·P1** | **圣光圣杯（组合型 #2，heal 60）** + 治疗药剂 + 清净药剂 | 护符禁期唯一的恢复来源 = 消耗品——腰带管理成为生存轴 |
| **爆发·P2** | **圣光爆裂（组合型 #3，assault ×2 ×2 次）** + 元素充能核爆 | 技能被禁后唯一乘区爆发（消耗品），P2 裸输出窗口兑击杀 |
| **破甲·P2** | **圣光钉锤（组合型 #4，pierce 符号）** + 穿甲重弩 / 破甲武器三连 | P2 厚甲 32 穿透直击（护符破甲概率已被剥，穿透符号/武器不受影响） |
| **净化·P2** | 净化药剂（抵消 jam 注废） | P2 骚扰应对 |
| **基础功** | MISS 按停规避 | 装备剥落后白回合代价最高 |

**节奏参考**：P1 护符被剥——以武器输出 + 消耗品治疗撑过，攒充能/资源（技能符号仍在池，P1 是「技能最后的窗口」）→ HP 过半切 P2：技能也出池 + 甲 32——光武克制 + 穿透/爆发窗口内兑击杀（拖杀 = 纯白无资源）。

## 5. 内容清单

### 5.1 房间与战利品

| 房间 | kind | 元素 | hp/atk/甲 | 角色 | 战利品 | 状态 |
|---|---|---|---|---|---|---|
| 无名虚空 | boss | dark | 320/18/20（P2 32） | hidden | **光系主题武器池**（holy_sword / 晨曦之刃 / iron_sword） | ✅ 已落地 |

> 战利品遵循 **T32**（弱光 BOSS 掉光系主题武器——光系已有 3 把，池 = 2 主题 + 1 通用，随组合型 #1 晨曦之刃增强）；专属信物暂不挂（随 T4/T7，同元素使/审判官）。

### 5.2 解法·基线可解 + 组合型新解法（规范 §6：阶段数 × 2——双阶段 4 个）

> **品类纪律**：本 BOSS 剥离护符（P1）与技能（P2）——被剥夺的品类不能作为解法，组合型新解法刻意避开护符/技能，以**武器 + 消耗品**为主（品类自由，规范 §8）。

| 阶段 | 类型 | 内容 | 状态 |
|---|---|---|---|
| — | **基线可解** | 现有物品框架内可通关：P1 光武（holy_sword 已有）×1.5 + 高 base 武器（战斧）+ 治疗药剂/清净药剂撑线；P2 穿透武器（穿甲重弩 bolt_shot pierce）+ 破甲三连 + 强袭药剂爆发 + 净化抵消 jam 全为既有内容 | ✅ 成立 |
| P1 | **组合型新解法 #1** | 「晨曦之刃」dawn_blade（**新武器**，light，rare 48/0.84，符号 圣辉斩（holy_slash）+ 晨曦之光（damage light）w2）——P1 主解：光武 ×1.5 克制 + 高 base 裸输出双轴，同时增强 T32 光系池 | ✅ 已落地 |
| P1 | **组合型新解法 #2** | 「圣光圣杯」holy_grail（**新消耗品**，rare，heal 60 charges 1——覆盖治疗药剂 30 的高档恢复）——护符禁期唯一恢复来源强化，P1 长线生存轴 | ✅ 已落地 |
| P2 | **组合型新解法 #3** | 「圣光爆裂」holy_burst（**新消耗品**，rare，assault ×2 charges 2——与强袭 ×2×1 次 / 熔火爆裂 ×3×1 次错位：双次小爆发）——技能被禁后唯一乘区爆发，P2 裸输出长线窗口 | ✅ 已落地 |
| P2 | **组合型新解法 #4** | 「圣光钉锤」holy_mace（**新武器**，light，rare 42/0.84，符号 圣锤（pierce）w3 + 圣辉斩 w2）——P2 厚甲 32 穿透直击（护符破甲概率被剥，穿透符号免疫剥夺） | ✅ 已落地 |

## 6. 实现步骤（聚合层开关 `deprived_level`：0=正常 / 1=护符禁 / 2=护符+技能禁；~8 处消费点单点判断，均走现有 F-0 聚合层与消费点，零结算逻辑改动；gimmick 动态访问 controller 字段，恢复 = `_apply_charms` 每房重算天然复位）

| 步骤 | 内容 | 改动文件 | 验证点（F6） |
|---|---|---|---|
| Step 1 · 核心小改 | duel_controller 加 `deprived_level: int = 0`（battle_state 同步）；消费点接入：agg_damage_mult / agg_power_flat / agg_shield / agg_regen（combat_system，charm 参数 suppressed 时中性化）、roll_intent 抗扰（status_system，suppressed 用 1.0）、破甲/元素/状态加成（combat_system 3 处）、开局盾（duel_controller 856：suppressed 不加）、`_build_pool` 技能符号两处循环跳过（duel_controller 387/418：level≥2） | `scripts/battle/duel_controller.gd` / `scripts/battle/combat_system.gd` / `scripts/battle/status_system.gd` / `scripts/battle/battle_state.gd` | 无护符/技能房零影响（deprived_level=0）；本 BOSS 房 P1 护符全失效、P2 技能符号出池 |
| Step 2 · gimmick 脚本 | `emotional_vacuum_gimmick.gd`：on_room_start 设 deprived_level=1 + 扣回开局盾（player_shield -= charm_room_shield）+ 开场日志飘字「⚫ 情感剥离」；on_damaged HP<50% 一次性：deprived_level=2 + player_buffs.clear() + 甲 32 + 攻 ×0.85 + 意图 attack 40/heavy 30/jam 30 覆盖 + 日志飘字「⚫ 全面麻木」；参数读 gimmick_params（T24）；ICON ⚫ | `scripts/battle/gimmicks/emotional_vacuum_gimmick.gd` | P1 护符失效（HUD 乘区概览回落）、P2 技能符号出池 + 增益清空 |
| Step 3 · 房间 .tres | 无名虚空：320/18/20 · dark · kind=boss · act=2 · boss_role=hidden · intents(P1 attack 60/heavy 40 内联) · gimmick_params · 光系战利品池（T32） | `resources/rooms/` 新增（nameless_void.tres） | Act2 BOSS 槽 5 候选可抽到、预告？？？、P2 触发 |
| Step 4 · 组合型新解法（阶段数 × 2 = 4 个） | #1 晨曦之刃（晨曦之光符号 + 武器 .tres）；#2 圣光圣杯（消耗品 .tres）；#3 圣光爆裂（消耗品 .tres）；#4 圣光钉锤（圣锤 pierce 符号 + 武器 .tres）——放入资源目录即入池 | `resources/` 对应目录 | 整备可选、进转轮、数值正确、pierce 生效 |
| Step 5 · 文档回写 | 总清单 T4 BOSS 池 9/12→10/12；规范 §12 进度表同步 | `docs/未完成任务_总清单.md` / `docs/BOSS设计规范.md` / `docs/项目概览_状态与内容.md` | — |
| Step 6 · F6 验证 | 见 §7 清单 | — | 全绿 |

## 7. F6 验证清单

- [ ] 无名虚空以 hidden 候选进入 Act2 BOSS 槽（5 候选抽取分布 ≈ 6:3:3:3:2），预告？？？
- [ ] P1：进房即剥离——护符乘区概览回落 ×1.0、每回合盾/回血/抗扰/破甲概率/元素加成/状态加成全部失效（HUD 显示与结算双查）
- [ ] 开局盾（守望护符）入账部分被扣除
- [ ] P1 期间技能符号正常入池可打（技能是 P1 最后窗口）
- [ ] HP<50% 一次性触发 P2（日志/飘字「⚫ 全面麻木」），不重复触发
- [ ] P2：技能符号出池（build_strips 后转轮无技能符号）+ 已挂增益清空（player_buffs 空）
- [ ] P2：护甲重设 32、攻击 ×0.85、意图 attack 40/heavy 30/jam 30（jam 可净化）
- [ ] 光武克制 ×1.5 + 充能核爆；P2 穿透符号（穿甲重弩/圣光钉锤）直击厚甲
- [ ] 非本 BOSS 房零影响（deprived_level=0 回归——教学位/其他 BOSS 无感知）
- [ ] 晨曦之刃（#1）/圣光圣杯（#2）入池；圣光爆裂（#3）双次 ×2；圣光钉锤（#4）pierce 生效
- [ ] 通关 → 训练点 +1 → 训练房 → 商店/下一房衔接正常

## 8. 关联

- 总清单 **T10**（阶段化·Act2 双阶段隐秘示例：茧居=节奏应变、无名虚空=装备应变）、**T24**（gimmick 参数化）、**T4**（BOSS 池 9/12→10/12）、**T25**（hidden 权重 2 / RoomData.boss_role）、**T32**（弱光 BOSS 掉光系主题——光系已有 3 把无需补池）、**组合型新解法规范（阶段数 × 2 = 4 个）**
- 结构参照：BOSS_茧居石雕_设计.md（Act1 隐秘范例）；本 BOSS 为 **Act2 隐秘位双阶段·装备剥夺型**
- 机制先例：P2 一次性触发（on_damaged + 参数阈值，whisper_lock/元素使/审判官先例）、厚甲（enemy_armor_max/enemy_armor）、意图切换覆盖（元素使 P2 表覆盖）、开局盾（charm_room_shield）；**无先例（新增）**：`deprived_level` 聚合层开关（护符/技能剥离——消费点 ~8 处单点判断，走 F-0 聚合层设计）
- 后续 Act3 三阶段 BOSS（耻辱审判官 shame_counter 罪业清算——「记录失误转化为伤害乘区」）可复用聚合层开关体系（剥夺/弱化类机制）
