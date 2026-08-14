# BOSS 设计规范（总纲）

> 状态：**现行规范（2026-08-10 整合）**——汇总 [已完成]BOSS_设计_执行方案 / BOSS机制扩展指南 / 各 BOSS 定稿文档 / 内容规格化_总量清单的现行规则，作为"新 BOSS 设计"的唯一入口规范。
> 设计哲学：**BOSS 先行**——武器/技能/护符全部围绕"如何克制 BOSS 的谜题轴"展开；出题（BOSS）→ 解题（克制动词 × 工具）闭环。
> 关联文档：各 BOSS 定稿文档（冰封铁瓮/碎裂石像鬼/酸蚀恶鬼/茧居石雕/迷宫低语者）为**格式范例**；BOSS机制扩展指南为**实现细节**；本文档只管规范本身。

---

## 1. 一局结构与 BOSS 槽

一局 = 3 幕 × 每幕 8 房（5 普通 + 2 精英 + 1 常规 BOSS 战）+ 真·最终（通关 Act3 后独立战）= 24+ 房。

**每幕 BOSS 槽 =「每幕 ≥4 候选选 1」**（池不全时剩余候选撑权重；Act2 实际 5 候选；当前进度见 §11）：

| 角色（boss_role） | 权重 | 定位 |
|---|---|---|
| fixed 固定首领 | 6 | 默认高权重，教学位（Act1 铁瓮、Act2 呓语教徒） |
| rotating 轮替 | 3 | 随机出现，同解的验收变体（Act1 石像鬼/酸蚀、Act2 迷宫低语者/元素使/审判官） |
| hidden 隐秘 | 2 | 幕内全清后开启（BOSS 槽恒为幕内最后一房，条件恒满足）；预告显示？？？不剧透（Act1 茧居石雕） |
| 真·最终 | 独立 | `final_boss=true`，通关 Act3 追加（勇者的阴影已落地） |

抽取实现：`_pick_boss` 按 `BALANCE.run_boss_weights`（fixed 6 / rotating 3 / hidden 2）加权。

## 2. 阶段化规范（T10）

| 幕 | 阶段 | 说明 |
|---|---|---|
| Act1 | **单阶段** | 教学位（铁瓮教破甲、石像鬼教克制、酸蚀教净化） |
| Act2 | **双阶段** | 阶段化验收（迷宫低语者：P1 干扰教学 → P2 HP<50% 乱权+锁轮加速） |
| Act3 | **三阶段** | 深渊监视者：P1 注废 / P2 闪回暴走（强制重转）/ P3 深渊吞噬（废铁翻倍 + 高攻厚甲，2026-08-10 落地） |

**阶段切换规范**：用 `on_damaged` 钩子检测 HP 阈值（`enemy_hp <= enemy_hp_max * ratio`）一次性触发；参数进 `gimmick_params`（`phase2_*` 缺省 = 单阶段，教学位零改动——迷宫低语者范例）。

## 3. 数值规范

| 项 | 规范 |
|---|---|
| HP/ATK/护甲 | 房内写 `hp/atk/armor`（0 = 取 archetype 基准）；ante 缩放自动（幕间 ×1.75/×1.46 × 幕内 ×1.15/×1.10） |
| 血攻配比 | 干扰/消耗型 BOSS 血多攻低（茧居 200/13、低语者 300/16）；爆发型可攻高血低（石像鬼 165/22 已落地） |
| 护甲 | 扁平池（先破甲后掉血），25 为 Act2 基线；叠加机制见 gimmick |
| 意图剖面 | `RoomData.intents`（IntentData 权重）优先 > archetype.intent_weights > kind 默认表；干扰类（jam/lock/chaos）须含可净化项供对策 |
| 元素/弱点 | 按 **元素克制 v2**（互克对+同元素+毒链）：冰→弱火、暗→弱光（毒备选）、光→弱暗（毒备选）、毒→弱火·光、火→弱冰 |
| 玩家侧 MISS | 全局 10-22%，非 BOSS 专属 |

**BOSS 血量参考**（ante 后，F6 复核；BOSS 恒为幕内第 8 房 → 幕内序号 ria=7）：幕一 ≈ 基础 ×1.15⁷ ≈ 基础×2.66；幕二 ≈ 基础 ×1.75×1.15⁷ ≈ 基础×4.66；幕三 ≈ 基础 ×1.75²×1.15⁷ ≈ 基础×8.14（ante 实现见 duel_controller._ante_scale，参数在 BALANCE.ante_act_step_hp / ante_room_step_hp）。

## 4. 机制规范（gimmick）

**零核心代码改动铁律**：新 BOSS = 新 gimmick 脚本 + 房间 .tres 挂载，不碰战斗核心。

| 钩子 | 时机 | 用途范例 |
|---|---|---|
| `on_room_start(ctrl)` | 进房一次 | 读 gimmick_params、开场日志 |
| `on_turn_begin(ctrl)` | 每回合开始 | 锁轮/叠盾/回血/乱权 |
| `on_damaged(ctrl, dmg)` | 敌人受伤 | HP 阈值阶段切换 |
| `on_turn_resolved(ctrl)` | 玩家结算后、敌人行动前（空转/MISS 也触发） | 律法判定/空转记罪/和解检测（compulsion_rule / shame_counter / shadow_projection） |
| `consume_flashback() -> bool` | 停轮后、结算前（返回 true 本次停轮作废强制重转） | 闪回暴走（abyss_erosion P2） |
| `on_consumable_used(ctrl, effect)` | 使用消耗品后（effect = 消耗品 effect 字段） | 消耗品触发响应（shadow_projection P3 和解） |
| `on_special_triple(ctrl)` | 任意同符号三连（不限 special 符号） | BOSS 自定义响应 |

**参数化（T24）**：所有数值进 `RoomData.gimmick_params`（`{"interval": 3, "amount": 15, ...}`），gimmick 内 `p.get(key, 默认)`——调参零代码。
**单侧性纪律**：gimmick 只操作"该 BOSS 自己的"资源（敌人侧/本房），不得跨玩家/敌人侧共享新状态；资源文件单侧归属。
**ICON**：gimmick 内 `const ICON := "emoji"`（HUD 预告读取）。
**防御**：非 BOSS 房 `current_gimmick=null`，钩子调用处判空（既有）。

## 5. 克制动词矩阵（设计时必查：BOSS 谜题只能用这些动词，且每类须有工具）

| 克制动词 | 解法来源 | 当前覆盖 |
|---|---|---|
| 元素克制 ×1.5 | 武器元素（v2 矩阵） | ✓ 五元素全闭环 |
| 破甲·穿透 | 破甲三连清甲 / 穿透符号直击 / 破甲符 25% | ✓ |
| 抗干扰 | 抗扰护符 / 净化药剂（purifiable） | ✓ |
| 状态叠加 | 灼烧/中毒/霜符号 + 状态符强化 | ✓ |
| 数值碾压 | 护盾/回血/伤害护符 + 体魄/回复/壁垒轨道 | ✓ |

> **设计铁律**：新 BOSS 的谜题轴必须落在上述动词内，且该动词有对应工具（否则先补工具，T4 联动）。

## 6. 战利品规范（T32 + 信物）

| 项 | 规范 |
|---|---|
| 主题武器池 | `boss_reward_weapons`：**弱 X 的 BOSS 掉 X 系主题武器**（2 主题 + 1 通用；例：茧居石雕弱火 → fire_sword/flame_staff/iron_sword；迷宫低语者弱光 → holy_sword/dawn_bow/iron_sword） |
| 专属信物 | `boss_relic_path`：护符位 1/3；与 BOSS 同系（复用或新增，遵循单侧性） |
| 解法·基线 | **现有物品框架内必须可解**（对策工具已存在，玩家用现有武器/护符/消耗品能通关——基线不依赖新内容） |
| 解法·组合型新解法 | **必须引入新内容**（新武器 / 新护符 / 新技能 / 新消耗品等，≥1 类）形成的**组合式解法**，**数量 = 阶段数 × 2**（2026-08-10 拍板：单阶段 2 个 / 双阶段 4 个 / 三阶段 6 个，每个阶段各 2 个，不多不少）；新内容如何组合、新增哪些品类自由发挥，但解法个数固定（阶段数 × 2）；作为该 BOSS 的特色解法/奖励导向；须符合 §8 自由度（单侧性纪律、克制动词矩阵内、元素不变量）与 T4 内容规模锚点 |

## 7. 课程化衍生（每幕 = 1 个 BOSS 原型 + 它的衍生产品）

| 房间角色 | 设计规则 |
|---|---|
| 普通 A | **同源元素**、无 gimmick（纯教学小怪） |
| 普通 B | **off-theme 异源调色**（避免整幕同元素单调） |
| 精英 | **机制-lite**：同源元素 + BOSS gimmick 弱化版（小护甲 + 1 项干扰意图） |
| BOSS | **合成**：元素 + 完整 gimmick + 全意图组合 |

> 反模式：所有房都复制 BOSS 机制 → 单调。用"普通 B 异源"破局。

## 8. 内容自由度与设计不变量

**可变（鼓励扩展，数据驱动零代码）**：
- **武器 / 护符 / 消耗品 / 技能**：自由新增——放 `.tres` 即入池（ResourceScan 扫描），不要求改代码、不要求改克制表：
  - 武器：元素（限 `ELEMENTS` 五元素内）/ 符号组合 / 稀有度强度档自由组合
  - 护符：现有 `effect` 枚举内自由组合（新增 effect 类型属系统扩展，走 T 编号评审）
  - 消耗品：新战术品（对策 / 增益 / 风味）自由加
  - 技能：新符号承载自由加
- **敌人**：自由新增（房间 `.tres`：行为族 × 元素 × 数值 × 意图）；BOSS 走 §9 设计流程
- 约束：单侧性纪律（不跨玩家/敌人侧共享状态）、克制动词矩阵内"基线可解"（§6：现有物品框架必须可解；**组合型新解法 = 阶段数 × 2 个，须引入新内容（≥1 类）形成组合式解法，组合方式/品类自由**）

**不可变（设计不变量）**：
- **元素克制基础（v2 矩阵）**：互克对（火↔冰、光↔暗）+ 同元素 ×0.85 + 毒链（火→毒、光→毒、毒→暗）+ 无属性恒中性——**任何新武器/新敌人/新内容不得要求修改此矩阵**
  - 新武器/敌人只能从 `ELEMENTS` 五元素取元素，弱/抗由 `ElementCounter` 自动推导（不存冗余字段）
  - **新增元素** = 克制体系变更，须整体设计评审（当前五元素闭环已定稿，不做）
- **克制动词矩阵（§5）**：BOSS 谜题轴只能在这四类动词 + 元素内出题
- **基础数值框架**：ante 缩放 / 乘区结构（连线/护符/克制/暴击）/ 三连规则为全局基线，单内容不得绕过

## 9. 设计流程（新 BOSS 走完此链）

```
① 定位（fixed/rotating/hidden + 阶段数 + 教学位/验收位）
② 谜题轴（克制动词矩阵内选 1-2 个 + 元素/弱点）
③ 数值（HP/ATK/护甲基线 + 意图剖面 + gimmick_params 初值）
④ 验证可解（现有物品框架内基线可解？；**组合型新解法 = 阶段数 × 2 个（每阶段各 2）** = 必须引入新内容（新武器/护符/消耗品/技能等 ≥1 类）形成的组合式解法，组合方式/品类自由，随 BOSS 引入——§6）
⑤ gimmick 脚本（钩子 + 参数化 + ICON）
⑥ 房间 .tres（archetype?/intents/gimmick_params/战利品/信物）
⑦ 设计文档（格式照 §11 范例文档，含数值表/机制/解法矩阵/验证清单）
⑧ 总清单登记（T4 BOSS 池进度）
⑨ F6 验证（§9 清单）
```

## 10. F6 验证清单（每个 BOSS 落地必查）

- [ ] 进入 BOSS 槽（fixed/rotating/hidden 抽取分布与权重吻合；hidden 预告？？？）
- [ ] 各阶段触发正确（阈值/一次性/不重复），阶段日志与飘字
- [ ] 意图剖面生效，干扰意图可净化
- [ ] 克制武器 ×1.5 生效、充能核爆/破甲/穿透等对应解法成立
- [ ] 战利品主题武器池正确（T32）、信物可拾取
- [ ] 通关 → 训练点 +1 → 训练房 → 下一房/商店衔接正常
- [ ] 教学位回归：同 gimmick 的单阶段房表现不变（参数缺省兼容）

## 11. 已确立的 gimmick 原型库

| 原型 | gimmick | 幕 | 阶段 | 参数化示例（gimmick_params） |
|---|---|---|---|---|
| 熔铸护甲 | rust_armor | 1 | 单 | interval/per_stack/max_stacks |
| 封闭壁垒 | cocoon_cycle | 1 | 单 | 开合节律（v2 已落地 2026-08-10）：cycle_period/shell_armor/open_armor/heal_per_turn/open_heavy_mult（v1 cocoon_sentinel 叠盾版保留可回退） |
| 玻璃大炮 | glass_cannon | 1 | 单 | 高 atk 低 hp（已落地）：reflect_ratio/reflect_cap |
| 状态炸弹 | acid_bomb | 1 | 单 | 玩家侧 DoT + 层数爆炸（已落地）：dot_per_turn/dot_base/bomb_stacks/bomb_dmg |
| 呓语锁轮 | whisper_lock | 2 | 单/双 | lock_every/attack_mult/phase2_* |
| 躁抑交替 | bipolar_phase | 2 | 双 | manic_atk_mult/manic_self_damage_pct/phase2_*/depressed_atk_mult/p2_armor（2026-08-10） |
| 律法强迫 | compulsion_rule | 2 | 双 | rule_pool/rule_every/rule_reward_atk_mult/rule_punish_mult/phase2_*/p2_armor/p2_lock_consumable（2026-08-10，含 on_turn_resolved 钩子与锁消耗品槽） |
| 情感剥离 | emotional_vacuum | 2 | 双 | phase2_hp_ratio/deprive_charms/deprive_skills/p2_atk_mult/p2_armor（2026-08-10，含 deprived_level 聚合层装备剥夺开关） |
| 深渊侵蚀 | abyss_erosion | 3 | 三 | base_ratio/low_hp_bonus/max_trash/phase2_*/phase3_*（2026-08-10 三阶段化，含 consume_flashback 强制重转钩子） |
| 人格裂变 | split_ego | 3 | 三 | phase2_hp_ratio/phase3_hp_ratio/anger_atk_mult/fear_atk_mult/fear_armor_step/fear_armor_cap/grief_dot_per_turn/grief_dot_base（2026-08-10，三元素三人格切换） |
| 罪业清算 | shame_counter | 3 | 三 | sin_atk_per/phase2_*/phase3_*/low_hp_ratio/low_hp_mult（2026-08-10，失误问责：受击/空转记罪） |
| 万象投影 | shadow_projection | 3 | 三 | projection_every/mirror_base_per/phase2_*/phase3_*（2026-08-10 真·最终，gimmick 实例复用 + 镜像 + 非暴力和解） |

## 12. BOSS 池进度（T4：目标每幕 4 候选 × 3 幕 + 真·最终 = 12，当前 **12/12 齐 + 真·最终落地**）

| 幕 | 已落地 | 角色 |
|---|---|---|
| Act1 | 冰封铁瓮（rust_armor）、碎裂石像鬼（glass_cannon）、酸蚀恶鬼（acid_bomb）、茧居石雕（cocoon_cycle 开合节律 v2 已落地） | fixed / rotating / rotating / hidden |
| Act2 | 呓语教徒（whisper_lock 单）、迷宫低语者（whisper_lock 双）、躁怒元素使（bipolar_phase 躁抑交替）、天平审判官（compulsion_rule 律法强迫）、无名虚空（emotional_vacuum 情感剥离，2026-08-10） | fixed / rotating / rotating / rotating / hidden |
| Act3 | 深渊监视者（abyss_erosion 三阶段：注废 → 闪回暴走 → 深渊吞噬，2026-08-10）、碎裂魔王（split_ego 人格裂变：愤怒/恐惧/悲伤三元素切换，2026-08-10）、耻辱审判官（shame_counter 罪业清算：失误问责 → 剥盾 → 血线，2026-08-10） | fixed / rotating / hidden |
| 真·最终 | 勇者的阴影（shadow_projection 万象投影：复刻全机制 + 镜像 + 非暴力和解，2026-08-10） | final_boss 独立 |

**待补**：常规 BOSS 池已齐（12/12）；真·最终已落地；后续 = 数值打磨 / 内容扩充（T4 装备 125 缺口）。

## 13. 关联与维护约定

- 实现细节：BOSS机制扩展指南（T2 钩子系统）；数值基线：数值膨胀与策略深度设计框架
- 新 BOSS 设计文档命名：`BOSS_名称_设计.md`，格式照 §10 范例（茧居石雕/迷宫低语者）
- 每次落地后：本文档 §11 进度、总清单 T4、项目概览同步回写
- 元素体系变更时：本文档 §3 元素/弱点表须同步（当前 = 克制 v2）
