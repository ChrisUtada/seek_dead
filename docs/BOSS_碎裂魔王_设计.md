# BOSS · 碎裂魔王（The Shattered King）设计

> 状态：**✅ 已落地（2026-08-10，Step 1-4 完成；F6 实机待验）**——`split_ego_gimmick.gd`（P1 愤怒：火属性 + 攻 ×1.15 + 意图 40/60 → P2 恐惧 HP<66%：切 ice + 每回合叠甲 +6（上限 45）+ 攻 ×0.9 + 意图 60/40 → P3 悲伤 HP<33%：切 poison + 每回合挂毒 2 层（enemy_deal_damage 闸口护盾可挡、清净可解、蚀毒壁垒减层）+ 意图 50/30/20，全参数化 gimmick_params）+ `shattered_king.tres`（440/24/20 · fire→ice→poison · rotating · 双主题战利品池 T32 变体）。**组合型新解法 6 个全部落地**（阶段数 × 2）：寒冰刃 frost_blade / 灵魂安抚 soul_soothe（heal 10/回合）/ 寒渊长枪 frost_lance（pierce 复用 ice_shot）/ 余烬 ember（burn DoT 跨阶段削血）/ 净厄圣水 purge_water（cleanse ×2）/ 圣辉审判 holy_verdict（light 技能）。属性切换/叠甲/玩家侧毒/意图切换全走先例，零核心代码改动。**三元素三阶段人格切换验收关**（元素应变终极形态）。
> 关联：T10（BOSS 阶段化·**Act3 三阶段轮替示例**——元素应变的终极验收）、T24（gimmick_params 参数化）、T4（BOSS 池 10/12→11/12）、T25（rotating 权重 3 入 Act3 BOSS 槽 2 候选）、**T32（BOSS 主题武器掉落——三弱点 BOSS 特殊处理：双主题池对应 P1/P2 主克）**、**组合型新解法规范（2026-08-10：阶段数 × 2 = 6 个）**、单侧性纪律。
> 草案原型：BOSS设计草案 §10（解离性身份障碍「人格裂变 split_ego」）——本稿按 BOSS 设计规范 2026-08-10 重置版细化定稿（元素按克制 v2 修正：草案「毒/暗 弱 火/光」为旧双向表述，v2 单向推导为 P1 fire 弱冰 / P2 ice 弱火 / P3 poison 弱光）。

---

## 1. 定位与特色

**Act3 三阶段轮替 BOSS（元素应变终极型）**：Act3 BOSS 槽「2 候选选 1」的 **rotating 候选**（fixed 深渊监视者权重 6 / rotating 碎裂魔王 3 ≈ 33%）。三阶段 = 解离性身份障碍的机制化：人格碎片逐层浮现——愤怒（火·高攻）→ 恐惧（冰·厚防）→ 悲伤（毒·控场）。

```
P1 愤怒人格（HP 100% → 66%）：火属性，攻击 ×1.15 + 意图重击偏置——高攻直压
P2 恐惧人格（HP < 66% 触发一次）：切冰属性（弱火），每回合叠甲 + 低攻——顽固防御
P3 悲伤人格（HP < 33% 触发一次）：切毒属性（弱光），每回合挂毒 + 注废——控场磨血
```

**定位（与躁怒元素使/深渊监视者错位）**：躁怒元素使 = 双元素切换（P1 火 → P2 冰）；碎裂魔王 = **三元素三阶段切换**（火→冰→毒）——元素应变的终极形态，每人格还带专属机制（高攻/叠盾/挂毒）。深渊监视者 = 三阶段**同轴**加深（池稀释）；碎裂魔王 = 三阶段**换轴**递进（属性+机制双换）。**带单元素 build 全程 ×0.85 温和惩罚**，三换克制武器 + DoT 跨阶段削血（burn 无视护甲）是正解。

## 2. BOSS 数值表

| 项 | 值 | 说明 |
|---|---|---|
| 名称 | 碎裂魔王（The Shattered King） | 游戏内显示名随 .tres 的 name |
| 元素 / 弱点 | **fire（P1）→ ice（P2）→ poison（P3）**；弱 **ice / fire / light** | 克制 v2：互克对 火↔冰、毒链 光>毒——P1 冰武 / P2 火武 / P3 光武克制 |
| HP / ATK | **440 / 24**（ante 后 ≈2000 / 110，ria=3） | Act3 rotating 略低于 fixed（深渊监视者 460/27） |
| 基础护甲 | **20** → P2 每回合叠甲（+6/回合，上限 45） | 恐惧人格「不断叠盾」= 节奏压力（rust_armor 先例），破甲/穿透价值回升 |
| 阶段 / 角色 | **三阶段**（P2 HP<66% / P3 HP<33%）/ **rotating** | Act3 BOSS 槽 2 候选（fixed 6 : rotating 3） |
| 意图（P1） | **attack 40 / heavy 60** | 愤怒重击偏置——配合攻 ×1.15，重击回合 ≈ 24×1.15×2 = 55 |
| 意图（P2） | **attack 60 / heavy 40** | 恐惧龟缩（低攻，压力在叠甲） |
| 意图（P3） | **attack 50 / heavy 30 / jam 20** | 悲伤控场（低攻 + 毒 + 注废，jam purifiable） |
| 玩家侧 MISS | 带子按装备 hit_rate 聚合 MISS 格（10-22%） | P1 白回合 = 白吃 ×1.15 重击；P3 白回合 = 白吃毒 |

## 3. 机制（split_ego 人格裂变，全参数化 T24）

### 3.1 P1 愤怒人格（HP 100% → 66%）

- **火属性**（弱 ice——冰武克制 ×1.5）；**攻击 ×`anger_atk_mult`**（默认 1.15）；意图 attack 40 / heavy 60（重击偏置）。
- 开场日志 + 飘字「🔥 愤怒人格：烈焰暴怒」。

### 3.2 P2 恐惧人格（HP < 66% 触发，一次性）

`on_damaged` 检测 `enemy_hp <= enemy_hp_max * phase2_hp_ratio` 且未触发过 → 切人格：
- **属性切换**：`enemy_element = "ice"`（弱 fire——火武克制 ×1.5）+ `hud._update_enemy_element()` 刷新 HUD。
- **叠甲**：每回合 `enemy_armor += fear_armor_step`（默认 6，上限 `fear_armor_cap` 45）——恐惧不断加固（节奏压力：破甲只清当前层、下回合又叠）。
- **攻击回落**：×`fear_atk_mult`（默认 0.9）；意图 attack 60 / heavy 40。
- 触发瞬间日志 + 飘字「❄️ 恐惧人格：寒冰壁垒层层加固」。

### 3.3 P3 悲伤人格（HP < 33% 触发，一次性）

- **属性切换**：`enemy_element = "poison"`（弱 light——光武克制 ×1.5）+ HUD 刷新。
- **挂毒**：每回合玩家侧 `player_status["poison"] += grief_dot_per_turn`（默认 2）——毒伤 = 层数 × `grief_dot_base`（默认 1），走 `enemy_deal_damage` 闸口（**护盾可挡**）、层数不衰减、清净药剂可清零（**acid_bomb 玩家侧 DoT 支点先例，gimmick 内自结算**）。
- **注废骚扰**：意图 attack 50 / heavy 30 / jam 20（jam purifiable）。
- 触发瞬间日志 + 飘字「☣ 悲伤人格：毒泪弥漫——每回合挂毒」。

### 3.4 与已有 BOSS 的差异化

| BOSS | 阶段机制 | 正解轴 |
|---|---|---|
| 躁怒元素使（Act2 双） | 双元素切换（火→冰） | 双元素应变 + 破甲 |
| 深渊监视者（Act3 三） | 三阶段同轴加深（池稀释） | 洗盘 + 少带 + 穿透 |
| 碎裂魔王（Act3 三） | **三元素三人格切换**（火→冰→毒 + 高攻/叠盾/挂毒） | **三换克制武器** + DoT 跨阶段削血 + 清净解毒 |

- **元素应变终极形态**：三阶段 = 三元素 = 三弱点翻转——P1 冰武 → P2 火武 → P3 光武（玩家需备齐三元素或靠 DoT/穿透旁路）。
- **DoT 跨阶段削血**（草案克制解）：burn DoT 无视护甲（赤焰弯刀先例）——P2 叠盾期/拖杀期照常磨血。
- 三弱点 → T32 战利品特殊处理：**双主题池**（P1 冰 + P2 火 + 通用），见 §5.1。

### 3.5 参数化（gimmick_params）
```json
{"phase2_hp_ratio": 0.66, "phase3_hp_ratio": 0.33,
 "anger_atk_mult": 1.15,
 "fear_atk_mult": 0.9, "fear_armor_step": 6, "fear_armor_cap": 45,
 "grief_dot_per_turn": 2, "grief_dot_base": 1}
```

## 4. 对策与联动（解法矩阵）

| 对策轴 | 具体 | 联动 |
|---|---|---|
| **克制·P1** | ice_gun / 霜晶法杖 / **寒冰刃（#1，ice）**（×1.5）+ frost 减攻 debuff（敌人侧 ×0.2/层） | P1 冰武双压制（克制伤害 + 减攻） |
| **克制·P2** | fire_sword / flame_staff / 赤焰弯刀（×1.5） | P2 切冰后火武克制 + 充能核爆 |
| **克制·P3** | holy_sword / 晨曦之刃 / **圣辉审判（#6，light 技能）**（×1.5） | P3 切毒后光武克制 |
| **破甲·P2** | 破甲三连 / 破甲符 / **寒渊长枪（#3，pierce）** | P2 叠盾（+6/回合）穿透直击——节奏压力对冲 |
| **DoT·跨阶段** | **余烬（#4，burn 技能）** + 赤焰弯刀——burn 无视护甲 | P2/P3 叠盾挂毒期的旁路削血（草案克制解） |
| **生存·P1/P3** | 守备/铁壁/**灵魂安抚（#2，回血 10/回合）** + 治疗 | P1 高攻 / P3 毒层期的生存底线 |
| **解毒·P3** | 清净药剂 / **净厄圣水（#5，cleanse ×2）** | P3 毒层清零（毒层不衰减，越拖越痛） |
| **净化·P3** | 净化药剂（抵消 jam 注废） | P3 骚扰应对 |
| **基础功** | MISS 按停规避 | 白回合 = 白吃重击/白吃毒 |

**节奏参考**：P1 冰武压火（克制 + 减攻双压制）→ HP<66% 切冰叠甲：火武克制 + 穿透/破甲打叠甲、burn DoT 旁路磨血 → HP<33% 切毒：光武克制 + 清净解层 + 速杀（拖杀 = 毒层越叠越痛）。

## 5. 内容清单

### 5.1 房间与战利品（T32 三弱点特殊处理）

| 房间 | kind | 元素 | hp/atk/甲 | 角色 | 战利品 | 状态 |
|---|---|---|---|---|---|---|
| 碎裂魔王 | boss | fire→ice→poison | 440/24/20（P2 叠甲至 45） | rotating | **双主题武器池**（ice_gun / fire_sword / iron_sword） | ✅ 已落地 |

> 战利品遵循 **T32 变体**：弱 X 掉 X 系规则对三弱点 BOSS 取「**P1/P2 主克双主题 + 1 通用**」（ice_gun 对应 P1 弱冰、fire_sword 对应 P2 弱火、iron_sword 通用）——开场两阶段即需的克制优先入池；专属信物暂不挂（随 T4/T7，同元素使/审判官/无名虚空）。

### 5.2 解法·基线可解 + 组合型新解法（规范 §6：阶段数 × 2——三阶段 6 个）

| 阶段 | 类型 | 内容 | 状态 |
|---|---|---|---|
| — | **基线可解** | 现有物品框架内可通关：P1 冰武（ice_gun 已有）+ 护盾；P2 火武（fire_sword 已有）+ 破甲三连；P3 光武（holy_sword 已有）+ 清净药剂 + 净化药剂全为既有内容 | ✅ 成立 |
| P1 | **组合型新解法 #1** | 「寒冰刃」frost_blade（**新武器**，ice，rare 44/0.84，符号 冰刃（damage ice）+ frost w3）——P1 主解：冰武 ×1.5 + frost 减攻双压制（同霜晶法杖定位，近战形态错位） | ✅ 已落地 |
| P1 | **组合型新解法 #2** | 「灵魂安抚」soul_soothe（**新护符**，rare，effect=`heal` value=10/回合——覆盖回春 6 的高档常驻回血）——P1 高攻 / P3 毒层期生存底线 | ✅ 已落地 |
| P2 | **组合型新解法 #3** | 「寒渊长枪」frost_lance（**新武器**，ice，rare 40/0.84，符号 冰弹（pierce）+ frost w2）——P2 叠盾穿透直击（P1 冰克双用） | ✅ 已落地 |
| P2 | **组合型新解法 #4** | 「余烬」ember（**新技能**，符号 damage fire + burn status）——burn DoT 无视护甲跨阶段削血（草案克制解：P2 叠盾期旁路） | ✅ 已落地 |
| P3 | **组合型新解法 #5** | 「净厄圣水」purge_water（**新消耗品**，rare，effect=`cleanse` charges 2——覆盖清净药剂单次）——P3 毒层清零双保险 | ✅ 已落地 |
| P3 | **组合型新解法 #6** | 「圣辉审判」holy_verdict（**新技能**，符号 damage light 高 base）——P3 光克输出窗口（技能位光武） | ✅ 已落地 |

## 6. 实现步骤（属性切换走 enemy_element + _update_enemy_element（元素使先例）、叠盾走 enemy_armor（rust_armor 先例）、玩家侧毒复刻 acid_bomb 自结算（enemy_deal_damage 闸口）、意图切换走覆盖——全部有先例，零核心代码改动）

| 步骤 | 内容 | 改动文件 | 验证点（F6） |
|---|---|---|---|
| Step 1 · gimmick 脚本 | `split_ego_gimmick.gd`：on_room_start 读参 + P1 火属性/攻 ×1.15 + 开场日志；on_turn_begin 按人格：P1 攻 ×1.15、P2 叠甲（+step 上限 cap）+ 攻 ×0.9、P3 挂毒（先结算旧毒再挂新层，enemy_deal_damage 闸口）+ 攻 ×1.0 + 意图覆盖（P2/P3 表 roll_intent）；on_damaged HP<66% 一次性切 P2（enemy_element=ice + _update_enemy_element + 日志飘字「❄️ 恐惧人格」）、HP<33% 一次性切 P3（enemy_element=poison + 日志飘字「☣ 悲伤人格」）；参数读 gimmick_params（T24）；ICON 💔 | `scripts/battle/gimmicks/split_ego_gimmick.gd` | 三人格切换/属性刷新/叠甲/挂毒/意图切换 |
| Step 2 · 房间 .tres | 碎裂魔王：440/24/20 · fire · kind=boss · act=3 · boss_role=rotating · intents(P1 attack 40/heavy 60 内联) · gimmick_params · 双主题战利品池（T32 变体） | `resources/rooms/` 新增（shattered_king.tres） | Act3 BOSS 槽 2 候选可抽到、P2/P3 触发 |
| Step 3 · 组合型新解法（阶段数 × 2 = 6 个） | #1 寒冰刃（冰刃符号 + 武器 .tres）；#2 灵魂安抚（护符 .tres）；#3 寒渊长枪（冰弹 pierce 符号 + 武器 .tres）；#4 余烬（burn 符号 + 技能 .tres）；#5 净厄圣水（消耗品 .tres）；#6 圣辉审判（光符号 + 技能 .tres）——放入资源目录即入池 | `resources/` 对应目录 | 整备可选、进转轮、数值正确、burn/pierce/cleanse 生效 |
| Step 4 · 文档回写 | 总清单 T4 BOSS 池 10/12→11/12、装备 63→69；规范 §12 进度表同步 | `docs/未完成任务_总清单.md` / `docs/BOSS设计规范.md` / `docs/项目概览_状态与内容.md` | — |
| Step 5 · F6 验证 | 见 §7 清单 | — | 全绿 |

## 7. F6 验证清单

- [ ] 碎裂魔王以 rotating 候选进入 Act3 BOSS 槽（2 候选抽取分布 ≈ 6:3）
- [ ] P1：火属性（弱冰 HUD 显示）、攻 ×1.15、意图 attack 40/heavy 60
- [ ] HP<66% 一次性触发 P2（日志/飘字「❄️ 恐惧人格」），不重复触发
- [ ] P2：属性翻 ice 且 HUD 弱点刷新（弱火）、每回合叠甲 +6（上限 45）、攻 ×0.9、意图 attack 60/heavy 40
- [ ] HP<33% 一次性触发 P3（日志/飘字「☣ 悲伤人格」）
- [ ] P3：属性翻 poison 且 HUD 弱点刷新（弱光）、每回合挂毒 2 层（毒伤 = 层数 ×1，护盾可挡）、层数不衰减、清净药剂清零、意图 attack 50/heavy 30/jam 20（jam 可净化）
- [ ] P1 冰武 ×1.5 + frost 减攻；P2 火武 ×1.5；P3 光武 ×1.5（克制切换后旧元素武变 ×0.85）
- [ ] burn DoT 无视护甲跨阶段削血（P2 叠盾期生效）
- [ ] 战利品双主题池（ice_gun/fire_sword/iron_sword）生效（T32 变体）
- [ ] 寒冰刃（#1）/灵魂安抚（#2）/寒渊长枪（#3 pierce）/余烬（#4 burn）/净厄圣水（#5 cleanse ×2）/圣辉审判（#6）入池生效
- [ ] 通关 → 训练点 +1 → 训练房 → 元进度/铁砧衔接正常

## 8. 关联

- 总清单 **T10**（阶段化：Act1 单 → Act2 双 → **Act3 三阶段轮替示例**）、**T24**（gimmick 参数化）、**T4**（BOSS 池 10/12→11/12）、**T25**（rotating 权重 3 / RoomData.boss_role）、**T32 变体**（三弱点 BOSS：双主题池对应 P1/P2 主克）、**组合型新解法规范（阶段数 × 2 = 6 个）**
- 结构参照：BOSS_躁怒元素使_设计.md（元素切换范例）；本 BOSS 为 **Act3 三阶段轮替·人格裂变型**
- 机制先例：属性切换（enemy_element + _update_enemy_element，元素使）、叠甲（enemy_armor，rust_armor/cocoon_cycle）、玩家侧毒（player_status + enemy_deal_damage 闸口，acid_bomb）、P2/P3 一次性触发（on_damaged + 参数阈值，深渊监视者）、意图切换覆盖（元素使/审判官）；**无先例（新增）**：三元素三阶段人格切换组合（每人格带专属机制）
- 后续真·最终 BOSS（勇者的阴影·万象投影）的「随机复刻机制组合」可复用三阶段钩子体系
