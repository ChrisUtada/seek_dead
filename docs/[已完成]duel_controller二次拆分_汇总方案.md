# duel_controller 二次拆分 · 可拆系统汇总方案

> **状态**：待执行（2026-08-09 汇总，用户拍板后按优先级逐项推进，每项独立 commit + F6 验证）
> **基线**：HEAD `c744680`（2026-08-09，ReelSystem / CombatSystem / StatusSystem 已拆）
> **关联文档**：`docs/[已完成]duel_controller拆分方案B.md`（一次拆分：5 个 RefCounted 子系统）、`docs/代码审查遗留项_进度跟踪.md`

---

## 1. 背景与现状

`scripts/battle/duel_controller.gd` 已从 **1926 行降至 1225 行**（-36%），三次拆分：

| 拆分 | 提交 | 迁出内容 | controller 行数 |
|---|---|---|---|
| ReelSystem | `3adf3cb` | 转轮带/旋转/按停/落子 9 函数 + 信号 | 1926 → 1709 |
| CombatSystem | `a7962f9` | 回合结算/符号贡献/敌我攻防/破甲核爆/元素充能/增益状态 17 函数 | 1709 → 1287 |
| StatusSystem | `62a0cbd` | 意图抽取/意图与状态定义表/汇总文案 8 函数 | 1287 → 1225 |

**剩余结构**（1225 行 / 74 函数）按职责块：

| 职责块 | 行数（估） | 代表性函数 |
|---|---|---|
| 房间/回合状态机 | ~260 | `_start_room` `_begin_player_turn` `_on_spin_pressed` `_enemy_turn` `_free_spin` |
| 装备池聚合 | ~110 | `_build_pool` `_eff_element` |
| 整备/槽位/护符 | ~90 | `_on_card_toggled` `_sel_arr` `_cat_*` `_grow_slot` `_confirm_loadout` `_apply_charms` |
| 奖励/BOSS/元进度编排 | ~90 | `_on_reward_chosen` `_finish_room` `_open_reward_screen` `_apply_*`（多数已是转发） |
| 商店/训练（经 shop_system） | ~70 | `_on_shop_*` `_gold_upgrade_defs`（多数已是转发） |
| 消耗品 | ~70 | `_on_consumable_pressed`（含 5 个效果分支，**未拆**） |
| meta 持久化 | ~30 | `_load_meta` `_save_meta` `_seed_default_owned` `_sanitize_owned` |
| 输入/薄转发/状态工具 | ~120 | `_input` `_status_*`（1 行转发） |
| 字段声明/常量/注释 | ~330 | — |

---

## 2. 目标

把「内容迭代高频、逻辑仍堆在 controller」的 4 块收编进既有子系统，controller 降级为纯编排器。

**预期**：controller `1225 → ~950 行`；新增消耗品/奖励/整备逻辑只碰子系统文件，controller 零改动。

---

## 3. 可拆系统清单（按推荐优先级排序）

### 3.1 ConsumableSystem（推荐先做——消耗品是最高频内容迭代点）

- **现状**：`_on_consumable_pressed`（~70 行）在 controller 内，`match data.effect` 五分支（purify / heal / assault / reroll / element）+ 守卫判断 + 扣 charges + 移除空槽 + 面板刷新耦合在一起。
- **拆法**：新建 `scripts/systems/consumable_system.gd`（RefCounted，`_init(ctrl)`）：
  - `use(uid) -> void`：原函数主体整体迁入（守卫、找槽、扣次、分发、移空槽、刷新全部经 `_ctrl`）。
  - 效果拆独立函数：`use_purify / use_heal / use_assault / use_reroll / use_element`——新增消耗品 = 加一个函数 + match 一行。
- **controller 保留**：`hud.consumable_used` 信号 → `consumable_system.use(uid)` 一行转发。
- **注意点**：
  - `reroll` 分支 `await _free_spin()` 跨系统调用——RefCounted 函数支持 await，`_free_spin` 仍留 controller（回合状态机），经 `_ctrl._free_spin()` 调用。
  - `purify` 分支读写 `enemy_intent` / `player_frost` / `frozen_cols`——全部经 `_ctrl`。
- **收益**：消耗品逻辑单文件内聚；未来 20 种消耗品不碰 controller。

### 3.2 MetaStore 全迁

- **现状**：`meta_store.gd` 已存在（存档读写外壳），但 `_load_meta / _save_meta / _seed_default_owned / _sanitize_owned`（4 函数 ~30 行）仍在 controller，`_ready` 里只调 `_meta_store` 的两个方法。
- **拆法**：把 controller 的 4 个函数体搬进 `meta_store.gd`（`load / save / seed_default_owned / sanitize_owned`），controller 改调新方法。
- **注意点**：`_sanitize_owned` 依赖 `_owned_arr`（可保留 controller 或一并迁入）；`_seed_default_owned` 依赖资源扫描池——经 `_ctrl.WEAPON_POOL` 等读取。
- **收益**：存档逻辑全归一处；无行为变化，纯搬家。

### 3.3 RewardSystem 补齐

- **现状**：reward_system.gd 已有 `roll_rewards / roll_elite_rewards / roll_boss_rewards / apply_reward / apply_boss_reward / roll_meta_choices / on_meta_choice_chosen`，但 controller 仍留同名薄转发（`_roll_rewards` 等 8 个，~60 行）与 UI 编排（`_open_reward_screen` `_show_meta_choice` `_on_reward_chosen` `_on_boss_reward_chosen`）。
- **拆法**：
  - 删除 controller 的 8 个 1 行转发，调用点直指 `_reward_system.xxx`。
  - `_open_reward_screen` / `_show_meta_choice`（UI 弹屏）迁入 reward_system（经 `_ctrl.hud` 弹屏）；`_on_reward_chosen` / `_on_boss_reward_chosen`（含 `_finish_room` 流程回调）可留在 controller 编排层——**跨系统联动不迁**（沿用拆分方案 B 守则 6）。
- **收益**：消灭转发层，奖励链路单文件可读。

### 3.4 LoadoutSystem 补齐

- **现状**：loadout_system.gd 已有 `selected_*` 槽位查询外壳，但 `_on_card_toggled / _sel_arr / _cat_max / _cat_cap / _can_grow_slot / _cap_text / _grow_slot / _cat_name / _confirm_loadout / _apply_charms`（10 函数 ~90 行）仍在 controller。
- **拆法**：槽位查询/勾选/开槽逻辑迁入 loadout_system（`_ctrl` 模式）；`_apply_charms`（护符被动聚合，被 `_start_room` / BOSS 信物等多处调用）**建议留在 controller**——它是战斗字段的聚合写回点，拆出后仍需 controller 维护 charm_* 字段，转发收益低。
- **注意点**：`_grow_slot` 被 shop_system（经 `_ctrl._grow_slot`）与 BOSS 战利品调用——迁入后改 `_ctrl._loadout_system.grow_slot` 或保留转发；建议保留 controller 薄转发以少动调用点（strangler fig 守则）。
- **收益**：整备逻辑单文件；槽位规则（cap/max/可扩容）可读性提升。

---

## 4. 不建议拆的块（及理由）

| 块 | 理由 |
|---|---|
| `_start_room` / `_on_spin_pressed` / `_enemy_turn` / `_free_spin` 回合房间状态机 | 本质是 controller 的编排职责；拆出需与 controller 双向回调（await / 状态翻转 / hud 刷新穿插），制造转发地狱，负收益 |
| `_build_pool` / `_eff_element` 装备池聚合 | 被 shop / reward / boss / 精华 / 整备多处调用，且读写 `_weapon_power_map` 等战斗字段；是"装备 → 池"的唯一聚合点，拆出必留转发 |
| `_input` / `_on_*_pressed` 输入入口 | 纯薄分发，无逻辑 |
| `_status_*` / `_intent_name` / `_buff_effect_name` 转发 | 已是 1 行转发（StatusSystem 壳） |
| `_build_state`（BattleState 快照） | 单向只读快照，与字段声明强耦合，无拆分收益 |

---

## 5. 通用守则（沿用拆分方案 B §3）

1. 每项独立 commit；回退 = `git revert <commit>`。
2. 子系统一律 `RefCounted` + `_init(ctrl)`，构造注入；状态仍由 controller 持有，子系统经 `_ctrl` 读写。
3. 缩进零改动（类级函数 1 tab 原样搬），主要工作量是把 controller 字段引用改 `_ctrl.xxx`。
4. 跨系统联动留在 controller 编排层；子系统之间不互调。
5. `.gd` 一律 CRLF（PowerShell 字节级写回，勿用 Edit 工具直接改 .gd——混入 LF 会触发 Godot 报错）。
6. `RefCounted` 无 Node 树：`await get_tree().create_timer()` 必须经 `_ctrl.get_tree()`（CombatSystem.evaluate 已有先例）。

---

## 6. 验收标准

- controller `1225 → ~950 行`，新增 3 个（或 2 个，视 Loadout 取舍）子系统文件，各 `<200 行`、单一职责、可独立 grep。
- 消耗品/奖励/整备 新增内容零 controller 改动。
- F6 全流程回归：旋转 → 结算 → 消耗品（五类效果）→ 房奖励 → BOSS 战利品 → 整备 → 商店 → 铁砧 → 训练房 → 元进度 → 新开一局。
