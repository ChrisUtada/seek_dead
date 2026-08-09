# BOSS · 酸蚀恶鬼（The Acidic Ghoul）设计

> 状态：**✅ 已落地（2026-08-09，Step 1-8 完成）**——`player_status` 玩家侧 DoT 支点（battle_state 镜像 + 房清零）+ `acid_bomb_gimmick.gd`（on_turn_begin 先 tick 旧毒再挂新层：毒伤走 `enemy_deal_damage` 闸口护盾可挡、≥10 层爆炸 30 清零、`gimmick_params` 参数化 + ICON）+ **清净药剂（cleanse）**（解冻+解毒合并为玩家侧状态专职药水，净化药剂回归意图单一职责）+ HUD 状态行（☣酸蚀×N，≥阈值警示色）+ 蚀毒壁垒护符（`dot_reduce` 聚合 `charm_dot_reduce`，挂毒量 -1/回合）+ `acid_ghoul.tres`（170/12/10 · poison · rotating · 意图 70/30 · 光系战利品池 T32）。F6 已验：挂毒节奏 2/4/6…层、毒伤逐层扣血、爆炸 10 层 → 10+30 伤清零、清净解层、护符减层 2→1/回合、爆炸阈值镜像；实机手感与 4 选 1 抽取/光系克制待 F6 复核。
> 关联：T10（BOSS 阶段化·Act1 单阶段轮替示例）、T24（gimmick_params 新规落地）、T4（BOSS 池 4/12→5/12）、T25（rotating 权重 3 入 4 选 1）、**T20 延伸（净化职责拆分 → 清净药剂，2026-08-09）**、**T32（BOSS 主题武器掉落规则——本 BOSS 战利品遵循）**、**蚀毒壁垒护符（2026-08-09 拍板：减层 -1/回合）**。

---

## 1. 定位与特色

**轮替 BOSS（重玩性内容）**：与固定首领铁瓮（教学位）错位——Act1 BOSS 槽「4 候选选 1」的轮替候选（`boss_role=rotating`，权重 3），出场时替代铁瓮，提供差异化节奏。

```
① 酸蚀挂毒：每回合叠玩家 poison DoT（层数累积，清净药剂才解）→ 磨血压力随时间放大
② 层数爆炸：≥10 层触发高额爆炸 → 清净/速杀是硬性节奏闸门
③ 低攻平压：单次攻击低，伤害重心在 DoT → 「打快 vs 打稳」的取舍
```

## 2. BOSS 数值表

| 项 | 值 | 说明 |
|---|---|---|
| 名称 | 酸蚀恶鬼（The Acidic Ghoul） | 游戏内显示名随 .tres 的 name |
| 元素 / 弱点 | poison / 弱 **light** | 光克毒（五元环：火>冰>毒>光>暗>火，`BEATS[light]=poison`） |
| HP / ATK | **170 / 12**（ante 后 ≈452 / 23，ria=7） | 血量居中、攻击显著低于铁瓮 15——DoT 是主伤害源；数值待 F6 复核 |
| 基础护甲 | **10** | 低甲快破（毒系刺客定位，无叠甲机制） |
| 阶段 / 角色 | 单阶段 / **rotating** | Act1 BOSS 槽 4 选 1 候选（权重 3） |
| 意图 | **attack 70 / heavy 30**（覆盖默认 60/40） | 平压为主：低攻蓄力无意义，重击低频 |
| 玩家侧 MISS | 带子按装备 hit_rate 聚合 MISS 格（10-22%） | 全局基本功 |

## 3. 机制

### 3.1 酸蚀挂毒（status_bomb · 核心，玩家侧 DoT）
- **每回合玩家回合开始时挂毒**：`player_status["poison"] += dot_per_turn`（参数化，默认 2 层/回合）
- **层数不衰减**（decay=0）：毒累积型 DoT——只有清净药剂（cleanse）能清零（与 frost 的 decay=1 每回合自减形成对比：frost 是"短痛"，毒是"长压"）
- **DoT tick**：玩家回合开始先结算毒伤再挂新层：每层每回合 `dot_base`（默认 1）点伤害，走 `combat.enemy_deal_damage` 唯一闸口——**护盾可挡**（守备/铁壁通用防御仍有效）、飘字/受击动画/日志自动
- **层数爆炸**：DoT ≥ `bomb_stacks`（默认 10）层 → 触发 `bomb_dmg`（默认 30）高额伤害（走同一闸口，护盾可挡）+ 层数清零
- **玩家侧状态**：新增 `player_status` 字段（与 `player_frost` 并列；本房清零、不跨房）
- 与 frost 冻结（功能状态）区分：毒是纯伤害累积状态；与敌人侧 poison（debuff 减攻）区分：玩家侧毒 = 自伤

### 3.2 层数节奏（压迫感曲线）
- 前 3 回合：1-6 层，每回合 1-6 伤——可忽视
- 第 5 回合：10 层触发第一次爆炸（30 伤）——玩家首次体验"爆炸"概念
- 此后每 5 回合一次爆炸循环（若不清毒）——清净/治疗/速杀的压力位
- **蚀毒壁垒护符**（2026-08-09 拍板）：挂毒量 -1/回合（2→1），爆炸回合 5→10 延后——压力保留、窗口拉宽（预防维度，与清净主动解互补）
- **教学链不承担**（轮替位）：但"看到层数累积 → 使用清净药剂"是自解释的（HUD 状态行 + 日志）

### 3.3 意图剖面
- attack 70 / heavy 30（重击 ×2.0 低频）——低攻平压，伤害重心在 DoT
- 无干扰意图：净化药剂（意图对策）在本战无用武之地，清净药剂专职解毒

## 4. 对策与联动（解法矩阵）

| 对策轴 | 具体 | 联动 |
|---|---|---|
| **清净·主解** | 清净药剂（cleanse，清玩家 DoT；2026-08-09 净化职责拆分） | **腰带必留位**——防爆炸的硬闸门 |
| **预防·护符** | 蚀毒壁垒（uncommon：挂毒层数 -1/回合，2026-08-09 拍板） | 爆炸窗口 5→10 回合拉宽；与清净主动解互补；槽位 3 格取舍 |
| **光系·克制** | holy_sword 45/88% / dawn_bow 28/84% / magic_bolt（光技能） | 克制 ×1.5，元素契印 → ×1.7；克制命中喂充能 |
| **抢杀·爆发** | 强袭×2 / 元素充能核爆 / 三连暴击 / 重转凑三连 | 少回合 = 少 DoT tick = 少爆炸次数 |
| **防御** | 守备/铁壁（盾可挡 DoT）/ 治疗药剂（容错）/ 回春（血线对冲） | 稳字流：盾+治疗硬抗毒伤 |
| **技能** | recovery（容错）/ rage（增伤） | 共用池 |
| **基础功** | MISS 按停规避 | 停歪 = 白挨毒 + 白白浪费回合 |

**节奏参考**：开局 attack 平压 + 毒层缓慢累积（前 3 回合无压力）→ 第 5 回合首爆（30 伤）玩家意识到威胁 → 清净/治疗/光系速杀三选一 → 中后期"毒层+爆炸"双线施压，速杀或稳解。

## 5. 内容清单

> 状态列约定同铁瓮/石像鬼文档。本 BOSS 武器 12 / 技能 5 全「原」共用；**新增消耗品「清净药剂」（cleanse）+ 1 护符「蚀毒壁垒」（预防维度）**；**新增玩家侧 DoT 支点**（核心代码，见 §6 Step 1）。

| 房间 | kind | 元素 | hp/atk/甲 | 角色 | 战利品 | 状态 |
|---|---|---|---|---|---|---|
| 酸蚀恶鬼 | boss | poison | 170/12/10 | rotating | 光系主题武器池（holy_sword / dawn_bow / iron_sword） | 【新增】 |

| 护符 | 稀有度 | 效果 | 酸蚀恶鬼/Act1 用途 | 状态 |
|---|---|---|---|---|
| 蚀毒壁垒 | uncommon | 挂毒层数每回合 -1（effect=`dot_reduce`, value=1） | 预防维度：爆炸窗口 5→10 回合拉宽（与清净主动解互补） | 【新增】 |

| 消耗品 | 效果 | 酸蚀恶鬼/Act1 用途 | 状态 |
|---|---|---|---|
| 清净药剂（cleanse） | 清玩家侧状态：frost 解冻 + 毒层清零 | **关键对策**（防爆炸硬闸门；净化职责拆分 2026-08-09） | 【新增】 |
| 净化药剂 | 抵消敌人干扰意图 | 本战无干扰意图（attack/heavy），不做对策 | 原 |

> 调整说明：酸蚀恶鬼入 Act1 BOSS 槽 4 选 1 候选（rotating 权重 3，fixed 6）；专属信物暂不挂（随 T4/T7）；**战利品遵循 T32（BOSS 主题武器掉落规则）：弱光 BOSS 掉光系主题武器**；蚀毒壁垒只对玩家侧 DoT 生效（当前仅 acid_bomb 系 BOSS 挂毒），Act2/3 毒爆类 BOSS 复用同一字段。

## 6. 实现步骤

> 本 BOSS 首次引入**玩家侧 DoT**——按 BOSS机制扩展指南 §7 属"前所未有的维度"，需在核心代码加支点（controller 字段 + 回合 tick + 清净分支扩展），其余仍走 gimmick 钩子。

| 步骤 | 内容 | 改动文件 | 验证点（F6） |
|---|---|---|---|
| Step 1 · 玩家侧 DoT 支点 | controller 新增 `player_status: Dictionary`（{"poison": 层数}）；玩家回合开始结算：先 tick 毒伤（走 `combat.enemy_deal_damage` 闸口，盾可挡）→ 层数 ≥ bomb_stacks 触发爆炸（伤害 + 清零）→ 再衰减/挂新层；每房清零 | `duel_controller.gd` / `battle_state.gd` / `status_system.gd` | 毒层显示、每回合毒伤、爆炸伤害与清零、房清零 |
| Step 2 · 清净药剂（净化职责拆分） | 新增清净药剂（cleanse）：清玩家 `player_status` 毒层 + frost 解冻（玩家侧状态统一）；净化药剂回归只抵消敌人意图 | `consumable_system.gd` / `resources/consumables/cleanse_potion.tres` | 清净后层数清零、爆炸不再触发；净化不再动玩家状态 |
| Step 3 · HUD 状态行 | 玩家状态行显示毒层（`❄霜冻×N` 同区域加 `☣酸蚀×N`，爆炸前警示色） | `battle_hud.gd` | 状态行实时、爆炸阈值警示可读 |
| Step 4 · gimmick 脚本 | `acid_bomb_gimmick.gd`：on_room_start 开场日志；on_turn_begin 挂毒 = `max(0, dot_per_turn - ctrl.charm_dot_reduce)`（参数化 `dot_per_turn`，默认 2）；ICON const | `scripts/battle/gimmicks/acid_bomb_gimmick.gd` | 每回合挂毒节奏、护符减层生效、日志正确 |
| Step 5 · 蚀毒壁垒护符 | `_apply_charms` 新 effect `dot_reduce` 聚合 `charm_dot_reduce`（battle_state 镜像）；`resources/charms/poison_ward.tres`（uncommon，value=1） | `duel_controller.gd` / `battle_state.gd` / `resources/charms/` | 整备可装配、挂毒 2→1、爆炸延后到第 10 回合 |
| Step 6 · 房间 .tres | 酸蚀恶鬼房：170/12/10 · poison · kind=boss · act=1 · boss_role=rotating · intents(attack 70/heavy 30) · gimmick_params · 光系战利品池（T32） | `resources/rooms/` 新增 | 4 选 1 可抽到、意图剖面生效 |
| Step 7 · 文档回写 | 总清单 T4 BOSS 池 4/12→5/12（护符计数 13→14） | `docs/未完成任务_总清单.md` | — |
| Step 8 · F6 验证 | 见 §7 清单 | — | 全绿 |

## 7. F6 验证清单

- [x] 酸蚀恶鬼以 rotating 候选进入 Act1 BOSS 槽（多局可抽到——抽取分布待实机复核）
- [x] 每回合挂毒 2 层、层数不衰减、HUD 状态行显示 `☣酸蚀×N`（单测：2/4/6 层节奏正确）
- [x] 毒伤每回合按层数结算、护盾可挡、飘字/日志正确（单测：R2 -2、R3 -4）
- [x] ≥10 层触发爆炸（30 伤 + 清零）（单测：10 层 → 10+30=40 伤，清零后重新挂层）
- [x] 清净药剂清零毒层、爆炸不再触发（单测：R3 清净后 R4 从 2 层重启）
- [x] 蚀毒壁垒护符：挂毒 2→1/回合（单测：护符挂载时挂层/毒伤减半）
- [ ] 光系克制 ×1.5/×1.7、充能联动正常（实机待验）
- [ ] 强袭/充能/三连速杀可行；毒层+爆炸双线施压可感知（实机待验）
- [ ] 通关 → 训练点 +1 → 训练房 → 商店/下一房（实机待验）
- [x] BOSS 战利品为光系主题武器池（holy_sword / dawn_bow / iron_sword，T32 规则）

## 8. 关联

- 总清单 **T10**（BOSS 阶段化·Act1 单阶段轮替示例）、**T24**（gimmick 参数化新规）、**T4**（BOSS 池 4/12→5/12，目标 12）、**T25**（`run_boss_weights` rotating 3 / `RoomData.boss_role`）、**T20 延伸**（净化职责拆分 → 清净药剂）、**T32**（BOSS 主题武器掉落规则）
- 结构参照：BOSS_碎裂石像鬼_设计.md（首个轮替 BOSS 文档）；本 BOSS 为非教学位轮替内容
- 玩家侧 DoT 支点（Step 1）为通用基建：Act2/3 的 status_bomb 类 BOSS（毒爆强化版）、最终 BOSS 均可复用
