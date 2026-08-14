# BOSS 信物 · 12 个设计方案

> 状态：2026-08-14 拍板（用户：不设独立槽位，信物 = epic 稀有护符）+ 落地。
> 背景：`roll_boss_rewards` 空池 bug（武器槽满 2 + 护符槽满/无信物 → 战利品无候选）引发本轮设计。

---

## 1. 决策：信物 = epic 稀有护符（不设独立槽位）

| 候选 | 结论 |
|---|---|
| 信物做成**武器** | ❌ 武器路线已被 `boss_reward_weapons` 主题池覆盖，且武器槽上限 2 再次撞车 |
| 信物做成**独立类别 + 独立槽位**（StS BOSS 遗物式） | ❌ 功能与护符同构（ItemData + effect + `_apply_charms` 聚合），加槽位 = 整备 UI/槽位上限/battle_state 全链路改动，过度设计 |
| **信物 = `category="passive"` + `rarity="epic"` 的稀有护符** | ✅ 选定：零槽位改动、零 UI 改动、复用勾选/商店/铁砧逻辑；「带 BOSS 信物还是带商店护符」的 3 格护符槽竞争本身就是健康取舍 |

- 新 12 信物**仅 BOSS 战利品可获**（不入商店/铁砧池——护符槽满拦截 + 候选仅在 roll_boss_rewards 生成）。
- 旧 4 信物（锈蚀核心/呓语残页/深渊之瞳/审判天平）保留为普通护符池成员，BOSS 房路径改指新信物。
- 真·最终「勇者的阴影」不给信物（保持毕业战独特性：击败/和解走元进度三选一）。

## 2. 十二信物总表

> 设计法则：**「你击败了它，你学会了它的把戏」**——效果 = 该 BOSS 机制的反向/回收。
> 幕一教学（直观易懂）→ 幕二机制（独特）→ 幕三顶格（数值天花板）。
> ✓ = 复用现有 effect；⭐ = 新增 effect 类型（§3）。

| 幕 | BOSS | 信物 | 图标 | effect | 数值 | 机制呼应 |
|---|---|---|---|---|---|---|
| 1 | 冰封铁瓮 | 霜核之心 | ❄️ | ✓ damage_bonus | +6 | 寒霜之力归你（覆盖锈蚀核心 +4） |
| 1 | 碎裂石像鬼 | 石屑之心 | 🪨 | ⭐ thorns | 反弹 20% | 石屑反弹回收（反伤） |
| 1 | 酸蚀恶鬼 | 毒腺囊 | 🧪 | ⭐ dot_amp | 挂 DoT 层数 +1 | 毒更毒 |
| 1 | 茧居石雕 | 节律之壳 | ⏳ | ✓ room_shield | 18/房 | 开合节律→开局护盾缓冲（覆盖守望 12） |
| 2 | 呓语教徒 | 静默之印 | 🤫 | ✓ interference_resist | 3 | 锁轮教头→抗扰顶格（覆盖明镜 3） |
| 2 | 迷宫低语者 | 迷宫回声 | 🌀 | ⭐ free_reroll | 每房间歇期免费刷新 1 次 | 迷路者→自己找路 |
| 2 | 躁怒元素使 | 二元之核 | ☯️ | ✓ element_boost | 克制 +0.3（×1.5→×1.8） | 属性翻转→你更懂克制 |
| 2 | 天平审判官 | 律法烙印 | ⚖️ | ✓ damage_mult | ×1.3 | 律法归你（覆盖审判天平 1.2） |
| 2 | 无名虚空 | 虚空回响 | 🌑 | ✓ status_boost | ×1.7 | 虚空之力灌注（覆盖疫病祭符 1.5） |
| 3 | 深渊监视者 | 深渊凝视 | 👁️ | ⭐ charge_start | 每回合开始充能 +1 | 深渊吞噬→你吞噬充能 |
| 3 | 碎裂魔王 | 碎片王冠 | 👑 | ⭐ first_hit | 每回合首个伤害符号 ×1.5 | 人格裂变→符号裂变 |
| 3 | 耻辱审判官 | 无罪之印 | 🕊️ | ✓ heal | 每回合 +14 | 罪业清算→无罪之身（覆盖救赎之心 12） |

- 稀有度统一 `epic`（信物 = 收藏金字塔顶端，呼应图鉴里程碑）。
- 数值遵循现有护符档位表（epic 档：狂怒 ×1.5 / 碎甲 40% / 疫病 ×1.5 同档）。

## 3. 新增 effect 类型（5 个，各 1 个结算点）

| effect | 语义 | 代码点 |
|---|---|---|
| `thorns` | 敌人攻击玩家时，反弹 `thorns×攻击值` 伤害给敌人（穿透护甲直击 HP） | `combat.enemy_deal_damage` 末尾 |
| `dot_amp` | 你给敌人挂的 DoT 层数 +N（status 符号结算时） | `combat.contribute` 的 `"status"` 分支 |
| `free_reroll` | 每房间歇期免费刷新货架 N 次（价格 0，不占付费次数；超出的刷新照常计费） | `shop_system.can_reroll/reroll_price` + `shop_screen._refresh_reroll_btn`（顺带收敛其硬编码价格逻辑） |
| `charge_start` | 每回合开始元素充能 +N（不触发爆发，爆发仍由克制命中驱动） | `duel_controller._begin_player_turn` |
| `first_hit` | 每回合首个伤害符号（damage/special）伤害 ×N | `combat.contribute` + `evaluate` 重置标记 |

- 聚合：`_apply_charms` 新增 5 分支（含 downside 反向分支，保持混合护符契约完整）。
- 剥夺纪律（无名虚空 deprived_level ≥ 1）：新 effect 与现有护符一致在读取点拦截。

## 4. 空池保底（顺带修复 bug）

`roll_boss_rewards` 双来源（主题武器 + 信物）都被槽位拦截时（武器 2/2 + 护符 3/3）→ 注入兜底卡：

| 兜底卡 | 数值 | 理由 |
|---|---|---|
| 铁砧点数 +3 | `boss_anvil` | 高于精英 +2、低于一次铁砧抽（10），空池 = 已满配玩家的稀有场景，跨局收益匹配 BOSS 身份 |

`apply_boss_reward` 新增 `"boss_anvil"` 分支（`meta["anvil_points"] += 3` + 落盘）。

## 5. 落地清单

**数据（零代码）**
- 12 个新 .tres → `resources/charms/`（`*_relic.tres`，passive/epic）
- 12 个常规 BOSS 房补 `boss_relic_path`（frozen_urn/whispering_cultist/maze_whisperer/abyss_watcher 从旧信物改指新信物；hero_shadow 不配）

**代码**
- `duel_controller.gd`：5 个 charm_* 变量 + `_apply_charms` 5 分支 + `_begin_player_turn` 充能
- `combat_system.gd`：thorns / dot_amp / first_hit 三结算点 + `_turn_hit_used` 标记
- `shop_system.gd`：免费重转计数接入 can_reroll/reroll_price；`shop_screen.gd` 改用查询
- `reward_system.gd`：空池兜底 + `apply_boss_reward` 新分支

**验证**：headless 启动无错 + verify_overlays.py + F6 实测（BOSS 战利品三选一恒有卡、免费重转、反弹、充能、首击）
