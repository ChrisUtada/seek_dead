# BOSS · 躁怒元素使（The Manic Elementalist）设计

> 状态：**✅ 已落地（2026-08-10，Step 1-4 完成；F6 实机待验）**——`bipolar_phase_gimmick.gd`（P1 攻 ×`manic_atk_mult` + 每回合自扣 5% max HP → P2 HP<50% 一次性：切 ice 属性 + 甲重设 45 + 攻 ×0.6 + 意图 attack 50/heavy 20/jam 30 覆盖，全参数化 gimmick_params）+ `manic_elementalist.tres`（280/18/15 · fire · rotating · 冰系战利品池 T32）。**组合型新解法 4 个全部落地**（阶段数 × 2）：霜晶法杖 ice_staff / 霜晶壁垒 frost_bulwark（shield 10）/ 熔火爆裂 lava_burst_potion（assault ×3）/ 炎息 fire_breath（damage_mult ×1.3 2 回合）。属性切换 = 弱点切换先例（enemy_element + _update_enemy_element，零核心代码改动）。
> 关联：T10（BOSS 阶段化·Act2 双阶段轮替示例）、T24（gimmick_params 参数化）、T4（BOSS 池 7/12→8/12）、T25（rotating 权重 3 入 Act2 BOSS 槽 3 候选）、**T32（BOSS 主题武器掉落——弱冰掉冰系池，现状冰系仅 ice_gun，随霜晶法杖补池）**、**组合型新解法规范（2026-08-10：阶段数 × 2）**、单侧性纪律。

---

## 1. 定位与特色

**Act2 双阶段 BOSS（元素应变型）**：Act2 BOSS 槽「3 候选选 1」的 **rotating 候选**（fixed 呓语教徒权重 6 / rotating 迷宫低语者 3 / rotating 躁怒元素使 3 ≈ 25%）。双阶段 = 双相情感障碍的机制化：躁狂（不可控爆发）→ 抑郁（僵直防御）。

```
P1 躁狂发作（HP 100% → 50%）：火属性，攻击 ×2 + 每回合自扣 5% max HP → 高攻快节奏、自毁加速
P2 抑郁僵直（HP < 50% 触发一次）：切冰属性，攻击大幅下降 + 护甲大幅提升 → 顽固防御、磨血无效
```

**定位（与迷宫低语者错位）**：低语者验收「干扰抗性」（锁轮+乱权）；躁怒元素使验收「**元素应变**」——属性切换逼玩家：P1 冰武克制（×1.5）+ 护盾扛 ×2 高攻，撑过自毁窗口；P2 换火武（×1.5）+ 破甲爆发。**带错元素 = 全程 ×0.85 温和惩罚**（克制 v2 同元素），双元素备装是正解。

## 2. BOSS 数值表

| 项 | 值 | 说明 |
|---|---|---|
| 名称 | 躁怒元素使（The Manic Elementalist） | 游戏内显示名随 .tres 的 name |
| 元素 / 弱点 | **fire**（P1）/ 弱 **ice**；P2 切换 **ice** / 弱 **fire** | 克制 v2：互克对 火↔冰——P1 冰武克、P2 火武克（属性切换 = 弱点切换） |
| HP / ATK | **280 / 18**（ante 后 ≈1300 / 51，ria=7） | 血比低语者（300/16）略低、攻更高——躁狂定位；P2 攻 ×0.6 后 ≈21 低落 |
| 基础护甲 | **15** → P2 重设 **45** | P1 轻甲（躁狂无暇防御）；P2 厚甲（抑郁蜷缩） |
| 阶段 / 角色 | **双阶段**（P2 HP<50%）/ **rotating** | Act2 BOSS 槽 3 候选（fixed 6 : rotating 3 : rotating 3） |
| 意图（P1） | **attack 50 / heavy 50** | 高攻蓄力偏置——配合攻击 ×2，重击回合威胁极大 |
| 意图（P2） | **attack 50 / heavy 20 / jam 30** | 低攻 + 注废骚扰（jam purifiable，净化药剂可抵消）——抑郁期阴损 |
| 玩家侧 MISS | 带子按装备 hit_rate 聚合 MISS 格（10-22%） | 全局基本功；P1 白回合 = 白吃 ×2 重击 |

## 3. 机制（bipolar_phase 躁抑交替，全参数化 T24）

### 3.1 P1 躁狂发作（HP 100% → 50%）
- **攻击 ×`manic_atk_mult`**（默认 2.0）——配合意图 heavy 50%，重击回合理论峰值 = 18×2.0×2.0 = 72（盾/治疗压力极大）
- **每回合自扣 5% max HP**（`manic_self_damage_pct`，默认 0.05）——自毁加速：P1 是"撑住 + 输出"的竞速阶段，玩家输出 + 自扣双线削血
- 意图剖面 attack 50 / heavy 50（高攻蓄力）

### 3.2 P2 抑郁僵直（HP < 50% 触发，一次性）
`on_damaged` 检测 `ctrl.enemy_hp <= ctrl.enemy_hp_max * phase2_hp_ratio` 且未触发过 → 进入 P2：
- **属性切换**：`ctrl.enemy_element = "ice"`（弱火——克制 v2 互克对 火↔冰）+ `hud._update_enemy_element()` 刷新 HUD 弱点显示——**玩家必须从冰武切火武**
- **防御重设**：`enemy_armor_max = 45` 补满（厚甲）；攻击倍率回落 ×`depressed_atk_mult`（默认 0.6）
- **意图切换**：attack 50 / heavy 20 / jam 30（低攻 + 注废骚扰，jam 可净化）
- 触发瞬间日志 + 飘字「🌊 情绪坠入深渊：冰封防御展开」

### 3.3 与已有 BOSS 的差异化

| BOSS | 阶段机制 | 正解轴 |
|---|---|---|
| 迷宫低语者 | P2 干扰增强（锁轮/乱权） | 抗干扰 + 目押 |
| 躁怒元素使 | **P2 属性切换**（火→冰，弱点翻转） | 双元素应变 + 破甲 |

- P1 冰武克制（×1.5）→ P2 冰武变同元素（×0.85 温和惩罚）→ 换火武（×1.5）——元素应变教学闭环
- 破甲三连/穿透在 P2 厚甲 45 下价值回升（同铁瓮）

### 3.4 参数化（gimmick_params）
```json
{"manic_atk_mult": 2.0, "manic_self_damage_pct": 0.05, "phase2_hp_ratio": 0.5,
 "depressed_atk_mult": 0.6, "p2_armor": 45}
```

## 4. 对策与联动（解法矩阵）

| 对策轴 | 具体 | 联动 |
|---|---|---|
| **克制·P1 主解** | ice_gun 30/88% / **霜晶法杖（组合型 #1，冰武）**（×1.5）+ frost 减攻 debuff | P1 冰武双压制：克制伤害 + frost 减攻（敌人侧 debuff ×0.2/层） |
| **克制·P2 主解** | fire_sword 45/88% / flame_staff 40/86% / 赤焰弯刀（×1.5） | P2 属性切冰后火武克制 + 充能喂给核爆 |
| **防御·P1 窗口** | 守备/铁壁/反击之盾 + **霜晶壁垒（组合型 #2，每回合盾+10）** + 治疗 | P1 ×2 重击窗口的核心生存 |
| **破甲·P2 窗口** | 破甲武器三连 / 破甲符 / 碎甲之印 + **熔火爆裂（组合型 #3，assault ×3）** | P2 厚甲 45 强开直击窗口兑击杀 |
| **爆发·P2** | **炎息（组合型 #4，buff damage_mult 1.3）** + 元素充能核爆 + 三连暴击 | 火武窗口内全乘区叠加 |
| **净化·P2** | 净化药剂（抵消 jam 注废） | P2 骚扰应对（与低语者衔接） |
| **基础功** | MISS 按停规避 | P1 白回合 = 白吃重击 + 白浪费自毁窗口 |

**节奏参考**：P1 躁狂（攻 ×2 + 自扣 5%/回合）——冰武 + 护盾撑过 3-5 回合竞速 → HP 过半切 P2：属性翻冰 + 甲 45，玩家切火武 + 破甲/穿透爆发 → 厚甲窗口内击杀（拖杀 = 注废骚扰 + 磨血无效）。

## 5. 内容清单

### 5.1 房间与战利品

| 房间 | kind | 元素 | hp/atk/甲 | 角色 | 战利品 | 状态 |
|---|---|---|---|---|---|---|
| 躁怒元素使 | boss | fire（P2→ice） | 280/18/15（P2 45） | rotating | **冰系主题武器池**（ice_gun / 霜晶法杖 / iron_sword） | ✅ 已落地 |

> 战利品遵循 **T32**（弱冰 BOSS 掉冰系主题武器——现状冰系仅 ice_gun，随组合型 #1 霜晶法杖补池，2 主题 + 1 通用）；专属信物暂不挂（随 T4/T7）。

### 5.2 解法·基线可解 + 组合型新解法（规范 §6：阶段数 × 2——双阶段 4 个）

| 阶段 | 类型 | 内容 | 状态 |
|---|---|---|---|
| — | **基线可解** | 现有物品框架内可通关：P1 冰武（ice_gun）+ 护盾 + 治疗撑窗口；P2 火武（fire_sword 等）+ 破甲/穿透爆发 全为既有内容 | ✅ 成立 |
| P1 | **组合型新解法 #1** | 「霜晶法杖」ice_staff（**新武器**，ice，rare 38/0.86，符号 冰霜晶弹 + frost w3）——P1 主解强化：冰武 ×1.5 + frost 减攻双压制，同时补 T32 冰系战利品池 | ✅ 已落地 |
| P1 | **组合型新解法 #2** | 「霜晶壁垒」frost_bulwark（**新护符**，rare，effect=`shield` value=10——每回合护盾 +10，覆盖铁壁 8 的高档常驻盾）——P1 ×2 重击窗口核心生存，与治疗/守备叠加 | ✅ 已落地 |
| P2 | **组合型新解法 #3** | 「熔火爆裂」lava_burst_potion（**新消耗品**，rare，assault ×3——覆盖强袭 ×2 的爆发强化版）——P2 厚甲 45 破甲窗口内三连/核爆全乘区叠加兑击杀 | ✅ 已落地 |
| P2 | **组合型新解法 #4** | 「炎息」fire_breath（**新技能**，buff damage_mult ×1.3 持续 2 回合——中档增伤，与 rage ×1.5 区分）——P2 火武窗口增伤，与熔火爆裂/充能组合拳 | ✅ 已落地 |

## 6. 实现步骤（零核心代码改动：攻击倍率走 boss_atk_mult、属性切换走 enemy_element + _update_enemy_element、厚甲走 enemy_armor、意图切换走覆盖——均有先例）

| 步骤 | 内容 | 改动文件 | 验证点（F6） |
|---|---|---|---|
| Step 1 · gimmick 脚本 | `bipolar_phase_gimmick.gd`：on_room_start 开场日志；on_turn_begin P1 攻击 ×manic_atk_mult + 每回合自扣 5% max HP；on_damaged HP<50% 一次性切 P2（enemy_element=ice + _update_enemy_element + 甲重设 45 + 攻击 ×0.6 + 意图覆盖 attack 50/heavy 20/jam 30）；参数读 gimmick_params（T24）；ICON 🌊 | `scripts/battle/gimmicks/bipolar_phase_gimmick.gd` | P1 攻 ×2、自扣 5%/回合；P2 属性翻冰 HUD 刷新、甲 45、攻 ×0.6、意图覆盖 |
| Step 2 · 房间 .tres | 躁怒元素使：280/18/15 · fire · kind=boss · act=2 · boss_role=rotating · intents(P1 attack 50/heavy 50 内联) · gimmick_params · 冰系战利品池（T32） | `resources/rooms/` 新增 | Act2 BOSS 槽 3 候选可抽到、P2 触发 |
| Step 3 · 组合型新解法（阶段数 × 2 = 4 个） | #1 霜晶法杖（ice_staff 符号 + 武器 .tres）；#2 霜晶壁垒（护符 .tres）；#3 熔火爆裂（消耗品 .tres）；#4 炎息（buff 符号 + 技能 .tres）——放入资源目录即入池 | `resources/` 对应目录 | 整备可选、进转轮、数值正确 |
| Step 4 · 文档回写 | 总清单 T4 BOSS 池 7/12→8/12；规范 §12 进度表同步 | `docs/未完成任务_总清单.md` / `docs/BOSS设计规范.md` | — |
| Step 5 · F6 验证 | 见 §7 清单 | — | 全绿 |

## 7. F6 验证清单

- [ ] 躁怒元素使以 rotating 候选进入 Act2 BOSS 槽（3 候选抽取分布 ≈ 6:3:3）
- [ ] P1：攻击 ×2、每回合自扣 5% max HP、意图 attack 50/heavy 50
- [ ] HP<50% 一次性触发 P2（日志/飘字），不重复触发
- [ ] P2：属性翻 ice 且 HUD 弱点显示刷新（弱火）、护甲重设 45、攻击 ×0.6、意图 attack 50/heavy 20/jam 30（jam 可净化）
- [ ] P1 冰武克制 ×1.5 + frost 减攻；P2 火武克制 ×1.5（属性切换后冰武变 ×0.85 温和惩罚）
- [ ] 霜晶法杖（#1）入池、冰系战利品池完整（T32）
- [ ] 霜晶壁垒（#2）：每回合盾 +10、P1 高攻窗口生效
- [ ] 熔火爆裂（#3）：assault ×3、P2 破甲窗口叠加核爆/三连
- [ ] 炎息（#4）：buff damage_mult ×1.3、与熔火爆裂/充能组合拳
- [ ] 通关 → 训练点 +1 → 训练房 → 商店/下一房衔接正常

## 8. 关联

- 总清单 **T10**（阶段化·Act2 双阶段轮替示例：低语者=干扰应变、躁怒元素使=元素应变）、**T24**（gimmick 参数化）、**T4**（BOSS 池 7/12→8/12）、**T25**（rotating 权重 3 / RoomData.boss_role）、**T32**（弱冰 BOSS 掉冰系主题——补冰系池缺口）、**组合型新解法规范（阶段数 × 2 = 4 个）**
- 结构参照：BOSS_迷宫低语者_设计.md（双阶段范例）；本 BOSS 为 **rotating 位双阶段·元素应变型**
- 机制先例：意图覆盖（cocoon_cycle 开合强制重击）、属性切换（无先例，走 enemy_element + _update_enemy_element 字段刷新——零核心改动）；P2 意图切换走 RoomData.intents 双相（P1 内联表 + gimmick 覆盖 P2）
- 后续 Act3 三阶段 BOSS（split_ego 人格裂变）可直接复用「属性切换」机制加第三段
