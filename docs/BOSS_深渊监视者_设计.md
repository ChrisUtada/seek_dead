# BOSS · 深渊监视者（Abyss Watcher）设计

> 状态：**✅ 已落地（2026-08-10，Step 1-5 完成；F6 实机待验）**——`abyss_erosion_gimmick.gd` 全参数化 + 三阶段：P1 注废（现状逻辑保留，base_ratio/low_hp_bonus/max_trash 迁入 gimmick_params）→ P2 闪回暴走（HP<66%：`consume_flashback()` 停轮作废强制重转（spin 流程单点挂接）+ 注废 ×1.5 + 甲 35→40 + 意图 40/30/30）→ P3 深渊吞噬（HP<33%：注废 ×2 叠乘 + 攻 ×1.3 + 甲 40→45 + 意图 50/50）；`abyss_watcher.tres` 更新（boss_role=fixed 显式 + 11 项参数 + **T32 修正：战利品火系池 → 暗系池 night_scythe/深渊巨镰/iron_sword**，abyss_relic 保留）。**组合型新解法 6 个全部落地**（阶段数 × 2）：深渊巨镰 abyss_scythe / 深渊壁垒 abyss_bulwark（盾 12）/ 梦魇屏障 nightmare_veil（buff 盾+12）/ 噩梦凝视 nightmare_gaze（buff 攻+8）/ 重铸风暴 recaster_storm（reroll ×3）/ 暗影再生 shadow_regen（首个 regen buff）。核心小改 2 处：boss_gimmick 基类 `consume_flashback()` 钩子 + `_on_spin_pressed` 停轮后结算前挂接（第一次停轮作废语义，结算只跑一次）。**池稀释对抗验收关**（Act3 三阶段终局）。
> 关联：T10（BOSS 阶段化·**Act3 三阶段固定示例**——Act1 单阶段 → Act2 双阶段 → Act3 三阶段的阶段递进验收）、T24（gimmick_params 参数化，现状硬编码 const 待迁）、T4（BOSS 池保持 10/12——三阶段化不新增角色，随 Act3 轮替/隐秘候选补齐）、T25（fixed 权重 6 / boss_role 显式化）、**T32（弱暗 BOSS 掉暗系主题——现状火系池违规，本稿修正）**、**组合型新解法规范（2026-08-10：阶段数 × 2 = 6 个）**、单侧性纪律。
> 草案原型：BOSS设计草案 §9（创伤后应激障碍「创伤侵蚀 abyss_erosion」）——本稿保留现状落地逻辑为 P1，按 2026-08-10 规范补齐三阶段。

---

## 1. 定位与特色

**Act3 三阶段固定 BOSS（池稀释对抗型）**：Act3 BOSS 槽固定候选（fixed 权重 6，无轮替/隐秘——Act3 其余候选待补）。**三阶段** = 阶段递进规范的终局验收（Act1 单阶段 → Act2 双阶段 → Act3 三阶段）：同轴机制的逐层加强（注废 → 注废+闪回 → 注废×2+高攻），区别于 Act2 各 BOSS 的「双阶段异轴转变」。

```
P1 噩梦侵袭（HP 100% → 66%）：每回合向转轮注入废铁（量 = 池大小 × 比例，残血加快）——稀释玩家转轮
P2 闪回暴走（HP < 66% 触发一次）：每次 spin 结算后有概率强制免费重转（打乱目押）+ 注废量提升 + jam 骚扰
P3 深渊吞噬（HP < 33% 触发一次）：废铁注入 ×2 + 攻击 ×1.3 + 护甲 40→45 + 意图重击偏置——终局吞噬
```

**定位（与 Act2 双阶段 BOSS 错位）**：低语者/元素使/审判官 = 双阶段**换轴**（干扰→乱权 / 元素→弱点翻转 / 规则→锁槽）；深渊监视者 = 三阶段**同轴加深**——不换机制、只加量（废铁越注越多、再叠闪回与高攻）。验收轴：**稀释对抗**（转轮池管理）——带越多武器侵蚀越狠（进池类无天花板的天然刹车），反向 build（少带武器）+ 洗盘（重转）+ 穿透（无视甲）是正解。

## 2. BOSS 数值表

| 项 | 值 | 说明 |
|---|---|---|
| 名称 | 深渊监视者（Abyss Watcher） | 游戏内显示名随 .tres 的 name |
| 元素 / 弱点 | **light** / 弱 **dark** | 克制 v2：互克对 光↔暗——暗武克制（night_scythe / shadow_dagger / 暗影铡刀 / #1 深渊巨镰） |
| HP / ATK | **460 / 27**（ante 后 ≈2100 / 125，ria=3） | Act3 终局基准（规范 §45：幕三 ≈2100）——保留现状数值 |
| 基础护甲 | **35** → P2 **40** → P3 **45** | 三阶段逐层加固（终局厚甲，穿透/破甲价值回升） |
| 阶段 / 角色 | **三阶段**（P2 HP<66% / P3 HP<33%）/ **fixed** | Act3 BOSS 槽固定候选（fixed 权重 6） |
| 意图（P1） | **attack 60 / heavy 40** | 现状 kind 默认表（boss 60/40）——注废即威胁，攻击朴素 |
| 意图（P2） | **attack 40 / heavy 30 / jam 30** | 闪回期 + 注废骚扰（jam purifiable，净化药剂可抵消） |
| 意图（P3） | **attack 50 / heavy 50** | 终局重击偏置——配合攻 ×1.3，重击回合理论峰值 ≈ 27×1.3×2 = 70 |
| 玩家侧 MISS | 带子按装备 hit_rate 聚合 MISS 格（10-22%） | 与注废叠加 = 转轮废格占比飙升——洗盘/少带武器对冲 |

## 3. 机制（abyss_erosion 深渊侵蚀·三阶段，全参数化 T24）

### 3.1 P1 噩梦侵袭（HP 100% → 66%）

- **每回合注入废铁**（现状落地逻辑保留）：`boss_trash`（每列废铁格数，上限 `max_trash`）= 池大小 ×（`base_ratio` + (1 - HP 比例) × `low_hp_bonus`）——池越大注越多（稀释刹车）、血越低注越快。
- 意图 attack 60 / heavy 40（现状默认表）。

### 3.2 P2 闪回暴走（HP < 66% 触发，一次性）

`on_damaged` 检测 `enemy_hp <= enemy_hp_max * phase2_hp_ratio` 且未触发过 → 进入 P2：
- **强制重转**（核心新机制）：玩家每次 spin 结算完成后，以 `phase2_flashback_chance`（默认 0.5）概率被强制免费重转一次——系统自动重新旋转，**玩家需再次按停**，以第二次结果结算（第一次停轮作废）——打乱目押预判（PTSD 闪回语义）。
- **注废加速**：`base_ratio` ×`phase2_trash_mult`（默认 1.5）。
- **护甲 +5**（35→40）；意图 attack 40 / heavy 30 / jam 30。
- 触发瞬间日志 + 飘字「🕳 闪回暴走：噩梦闪回——停轮将被强制重转」。

### 3.3 P3 深渊吞噬（HP < 33% 触发，一次性）

- **废铁注入 ×`phase3_trash_mult`**（默认 2.0，与 P2 加速叠乘 = 现状 LOW_HP_BONUS 之上再加倍）。
- **攻击 ×`phase3_atk_mult`**（默认 1.3）——高攻终局。
- **护甲 +5**（40→45）；意图 attack 50 / heavy 50（重击偏置）。
- 触发瞬间日志 + 飘字「🕳 深渊吞噬：废铁翻倍，攻击强化——终局降临」。

### 3.4 与已有 BOSS 的差异化

| BOSS | 阶段机制 | 正解轴 |
|---|---|---|
| 迷宫低语者（Act2 双） | P2 干扰增强（锁轮/乱权） | 抗干扰 + 目押 |
| 躁怒元素使（Act2 双） | P2 属性切换（弱点翻转） | 双元素应变 |
| 天平审判官（Act2 双） | P2 惩罚升级（规则+锁槽） | 目押律法 |
| 无名虚空（Act2 双） | P2 装备剥夺（护符+技能） | 裸输出 |
| 深渊监视者（Act3 三） | **三阶段同轴加深**（注废→闪回→吞噬） | **池稀释对抗**（洗盘 + 少带 + 穿透） |

- **三阶段 = 不换轴只加量**（与 Act2 全双阶段换轴错位）：同一注废机制逐层加重，P2 叠闪回（强制重转）、P3 叠高攻厚甲——考验「资源管理」而非「机制应变」。
- **强制重转 = 全项目首个「结算后自动重转」**（spin 流程单点挂接），后续 BOSS 的条件式重转可复用。

### 3.5 参数化（gimmick_params，现状硬编码 const 迁入）
```json
{"base_ratio": 0.10, "low_hp_bonus": 0.30, "max_trash": 24,
 "phase2_hp_ratio": 0.66, "phase2_trash_mult": 1.5, "phase2_flashback_chance": 0.5, "phase2_armor": 40,
 "phase3_hp_ratio": 0.33, "phase3_trash_mult": 2.0, "phase3_atk_mult": 1.3, "phase3_armor": 45}
```

## 4. 对策与联动（解法矩阵）

| 对策轴 | 具体 | 联动 |
|---|---|---|
| **克制·主解** | night_scythe 50/78% / shadow_dagger / 暗影铡刀 / **深渊巨镰（组合型 #1，dark）**（×1.5） | 暗武克制全程（light 弱 dark，三阶段同元素克制不变） |
| **洗盘·注废** | 重转卷轴 / 赦免令 / **重铸风暴（组合型 #5，reroll ×3）**——转出废铁重转洗掉 | P1/P3 废铁稀释的直接对冲（草案克制解） |
| **反向 build·注废** | 少带武器（稀释刹车）——武器越少注入基数越小 | 「进池类无天花板」的反向解（池稀释对抗的核心策略） |
| **穿透·厚甲** | 穿甲重弩 / 破甲三连 / **深渊巨镰 pierce 符号** | P2/P3 护甲 40→45 强开直击（注废期输出不打折） |
| **生存·闪回/高攻** | 守备/铁壁/**深渊壁垒（#2，盾 12/回合）** + **梦魇屏障（#3，buff 盾+12）** + **暗影再生（#6，buff 回血）** | P2 闪回白转期 / P3 高攻窗口的生存底线 |
| **输出·闪回** | **噩梦凝视（#4，buff power+8）** + 元素充能核爆 | P2 闪回期照样输出（打不中就靠乘区） |
| **净化·P2** | 净化药剂（抵消 jam 注废） | P2 骚扰应对 |
| **基础功** | MISS 按停规避 + 闪回第二次按停 | 闪回 = 二次目押机会（惩罚转奖励的手感） |

**节奏参考**：P1 注废稀释 + 暗武克制压线（洗盘保输出）→ HP<66% 闪回（停轮可能作废重来——护盾/乘区撑过）→ HP<33% 吞噬（废铁×2 + 重击威胁——重铸风暴洗盘 + 穿透打厚甲 + 盾/回血保命，拖杀 = 被稀释致死）。

## 5. 内容清单

### 5.1 房间与战利品（T32 修正）

| 房间 | kind | 元素 | hp/atk/甲 | 角色 | 战利品 | 状态 |
|---|---|---|---|---|---|---|
| 深渊监视者 | boss | light | 460/27/35（P2 40 / P3 45） | fixed | **暗系主题武器池**（night_scythe / 深渊巨镰 / iron_sword） | ✅ 已落地（三阶段化） |

> ⚠️ **T32 修正**：现状 `boss_reward_weapons` = flame_staff / fire_sword / battle_axe（火系池）——**弱暗 BOSS 应掉暗系主题武器**（克制 v2：弱 X 掉 X 系），随本稿落地改为 night_scythe / 深渊巨镰 / iron_sword（2 主题 + 1 通用）。专属信物 `abyss_relic.tres` 保留（深渊之瞳，damage_mult ×1.15）。

### 5.2 解法·基线可解 + 组合型新解法（规范 §6：阶段数 × 2——三阶段 6 个）

| 阶段 | 类型 | 内容 | 状态 |
|---|---|---|---|
| — | **基线可解** | 现有物品框架内可通关：P1 暗武（night_scythe 已有）×1.5 + 重转卷轴（洗废铁）+ 少带武器；P2 净化抵消 jam + 护盾吃闪回；P3 破甲/穿透打厚甲 + 治疗全为既有内容 | ✅ 成立 |
| P1 | **组合型新解法 #1** | 「深渊巨镰」abyss_scythe（**新武器**，dark，rare 48/0.82，符号 暗斩 + 深渊撕咬（pierce）w2）——克制主解 + 穿透双轴，同时补 T32 暗系池 | ✅ 已落地 |
| P1 | **组合型新解法 #2** | 「深渊壁垒」abyss_bulwark（**新护符**，rare，effect=`shield` value=12/回合——覆盖霜晶壁垒 10 的顶级常驻盾）——P1/P3 注废期长线生存 | ✅ 已落地 |
| P2 | **组合型新解法 #3** | 「梦魇屏障」nightmare_veil（**新技能**，buff shield +12 持续 2 回合——覆盖秩序光环 10）——P2 闪回白转期生存窗口 | ✅ 已落地 |
| P2 | **组合型新解法 #4** | 「噩梦凝视」nightmare_gaze（**新技能**，buff power +8 持续 2 回合——覆盖蓄势 +6 的顶级增伤）——P2 闪回期输出补强 | ✅ 已落地 |
| P3 | **组合型新解法 #5** | 「重铸风暴」recaster_storm（**新消耗品**，rare，effect=`reroll` value=3——覆盖赦免令 ×2 的顶级洗盘）——P3 废铁翻倍期高频洗盘 | ✅ 已落地 |
| P3 | **组合型新解法 #6** | 「暗影再生」shadow_regen（**新技能**，buff regen +6 持续 2 回合——首个 regen buff 符号）——P3 高攻窗口持续恢复 | ✅ 已落地 |

## 6. 实现步骤（P1 现状逻辑保留；P2/P3 增量：强制重转 = spin 流程单点挂接（evaluate 完成后、敌人行动前检测 gimmick 消费标志），废铁/倍率/意图走 gimmick_params（T24）与现有字段——零结算改动）

| 步骤 | 内容 | 改动文件 | 验证点（F6） |
|---|---|---|---|
| Step 1 · 核心小改 | duel_controller `_on_spin_pressed` 阶段 3 前挂接：`current_gimmick` 若声明 `consume_flashback()` 为真 → 强制免费重转一次（自动 begin_spin + await 玩家按停 + 重新 evaluate，第一次结果作废；本次重转不重复触发闪回）；boss_gimmick 基类加 `func consume_flashback() -> bool: return false` | `scripts/battle/duel_controller.gd` / `scripts/battle/gimmicks/boss_gimmick.gd` | P2 触发后 spin 结算后有概率强制重转、玩家二次按停生效 |
| Step 2 · gimmick 脚本 | `abyss_erosion_gimmick.gd` 参数化（base_ratio/low_hp_bonus/max_trash/phase2_* /phase3_* 读 gimmick_params）+ 三阶段：on_room_start 读参；on_turn_begin 按阶段倍率注入废铁（P1 base / P2 ×1.5 / P3 ×2）+ P2/P3 意图覆盖（roll_intent P2/P3 表）；on_damaged HP<66% 一次性进 P2（日志飘字「闪回暴走」）、HP<33% 一次性进 P3（「深渊吞噬」）；P2 起 `consume_flashback()` 按概率返回真（每回合重置计数）；ICON 🕳 | `scripts/battle/gimmicks/abyss_erosion_gimmick.gd` | 三阶段触发/废铁注入倍率/闪回概率/意图切换 |
| Step 3 · 房间 .tres | abyss_watcher.tres：保留 460/27/35 · light · boss · act=3 · **boss_role=fixed 显式** · intents(P1 attack 60/heavy 40 内联) · gimmick_params · **战利品池改暗系（T32 修正）** | `resources/rooms/abyss_watcher.tres` | Act3 槽抽取、三阶段触发、战利品暗系 |
| Step 4 · 组合型新解法（阶段数 × 2 = 6 个） | #1 深渊巨镰（深渊撕咬符号 + 武器 .tres）；#2 深渊壁垒（护符 .tres）；#3 梦魇屏障（buff 符号 + 技能 .tres）；#4 噩梦凝视（buff 符号 + 技能 .tres）；#5 重铸风暴（消耗品 .tres）；#6 暗影再生（regen buff 符号 + 技能 .tres）——放入资源目录即入池 | `resources/` 对应目录 | 整备可选、进转轮、数值正确、reroll ×3 连转、regen 生效 |
| Step 5 · 文档回写 | 总清单 T4 装备 57→63、BOSS 池保持 10/12（三阶段化不新增角色）；规范 §12 进度表同步（Act3 三阶段落地） | `docs/未完成任务_总清单.md` / `docs/BOSS设计规范.md` / `docs/项目概览_状态与内容.md` | — |
| Step 6 · F6 验证 | 见 §7 清单 | — | 全绿 |

## 7. F6 验证清单

- [ ] 深渊监视者以 fixed 候选进入 Act3 BOSS 槽（现状单阶段回归：无 gimmick_params 时行为与现状一致——参数缺省兼容）
- [ ] P1：每回合注废（池 × 比例，残血加快，上限 max_trash）与现状一致
- [ ] HP<66% 一次性触发 P2（日志/飘字「🕳 闪回暴走」），不重复触发
- [ ] P2：spin 结算后 ~50% 概率强制免费重转（玩家二次按停、以第二次结果结算、不触发敌人回合、不重复闪回）
- [ ] P2：注废 ×1.5、护甲 35→40、意图 attack 40/heavy 30/jam 30（jam 可净化）
- [ ] HP<33% 一次性触发 P3（日志/飘字「🕳 深渊吞噬」）
- [ ] P3：注废 ×2（与 P2 叠乘）、攻击 ×1.3、护甲 40→45、意图 attack 50/heavy 50
- [ ] 暗武克制 ×1.5 + 充能核爆；P2/P3 穿透/破甲直击厚甲
- [ ] 战利品暗系池生效（T32 修正）、abyss_relic 信物保留
- [ ] 深渊巨镰（#1）/深渊壁垒（#2）/梦魇屏障（#3）/噩梦凝视（#4）/重铸风暴（#5 reroll ×3）/暗影再生（#6 regen）入池生效
- [ ] 通关 → 训练点 +1 → 训练房 → 元进度/铁砧衔接正常

## 8. 关联

- 总清单 **T10**（阶段化：Act1 单 → Act2 双 → **Act3 三阶段终局验收**）、**T24**（gimmick 参数化——现状硬编码 const 迁入）、**T4**（BOSS 池保持 10/12）、**T25**（fixed 权重 6 / boss_role 显式化）、**T32**（弱暗 BOSS 掉暗系——**现状火系池违规修正**）、**组合型新解法规范（阶段数 × 2 = 6 个）**
- 结构参照：BOSS_无名虚空_设计.md（双阶段范例）；本 BOSS 为 **Act3 三阶段固定·池稀释对抗型**
- 机制先例：注废（现状 boss_trash + _build_strips 落实）、意图切换覆盖（元素使/审判官 P2 表覆盖）、P2/P3 一次性触发（on_damaged + 参数阈值）、厚甲（enemy_armor_max/enemy_armor）；**无先例（新增）**：强制重转（consume_flashback 消费标志 + spin 流程单点挂接）
- 后续真·最终 BOSS（勇者的阴影·万象投影）的「随机复刻机制组合」可直接复用三阶段钩子与消费标志体系
