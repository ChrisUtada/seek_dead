# duel_controller.gd 拆分方案 B（实现步骤）

> **状态**：待执行（用户已拍板按方案 B，每步 F6 验证后推进）
> **基线**：HEAD `3117c6d`（2026-08-06）
> **关联文档**：`docs/代码审查与优化建议.md`（P0–P3 重构路线图）、`docs/物品中心重构方案.md`

---

## 1. 背景与现状

`scripts/battle/duel_controller.gd` 约 **2252 行 / 109 个函数**，典型 God Object（战斗 / 商店 / 铁砧 / 奖励 / 整备 / 存档 / 转轮 / 结算全耦合）。

此前已落地 P0–P3 重构，本方案在其之上继续：
- P0 `BattleMath`：纯结算函数已抽至 `scripts/battle/battle_math.gd`（RefCounted，全 static）。
- P1 `BattleState`：只读快照，HUD 不再直读 controller 私有字段。
- P2 信号意图：HUD 只发意图信号，controller 订阅委托。
- P3b 覆盖层：RewardScreen / ShopScreen / AnvilScreen / LoadoutScreen / MetaScreen 已抽独立 .tscn。

**剩下的问题**：controller 本体仍是单体——所有"盘外系统"（存档、铁砧、商店、奖励、整备）的逻辑都堆在它里面。

## 2. 目标与验收标准

**目标**：把「盘外系统」（与单场战斗无强耦合）抽成 **5 个 RefCounted 子系统**，controller 降级为编排器。

| 子系统 | 职责 | 文件 |
|---|---|---|
| `MetaStore` | 存档读写 + 拥有池种子/自愈 + 金币授予 | `scripts/systems/meta_store.gd` |
| `AnvilSystem` | 铁砧 gacha（抽卡 / 保底 / 图鉴里程碑 / 点数 drip） | `scripts/systems/anvil_system.gd` |
| `ShopSystem` | 商店买卖 / 开槽 / 金币升级 | `scripts/systems/shop_system.gd` |
| `RewardSystem` | 房奖励三选一 / 精英补给 / 元进度三选一 | `scripts/systems/reward_system.gd` |
| `LoadoutSystem` | 整备选物 / 槽位 / 拥有池读 | `scripts/systems/loadout_system.gd` |

**留在 controller（战斗核心）**：reel 动画、`_evaluate` 结算、buff/status、enemy turn、run/房间流程、`_ready`/`_build_state`/`_build_pool` 编排入口。

**验收标准**：
- controller 行数 `2252 → ~1300`（5 系统抽走 ~740 行逻辑 + 删 ~250 行历史注释；战斗核心仍留。注：700 行是连战斗内也拆的 C 方案预期，非本方案）。
- 每个子系统 `<250 行`、单一职责、可独立 grep。
- 无 autoload、无全局注册表；`meta` 仍由 controller 单一持有。

## 3. 总节奏与通用守则（每步适用）

1. **每步单独 commit**；回退 = `git revert <commit>`（已推送）或 `git reset --hard HEAD~1`（未推送）。任何一步 F6 崩了只回退那一步。
2. **缩进零改动**：原文件 `extends Control` 的类级函数 1 tab，新 `RefCounted` 子系统的类级函数也是 1 tab → 函数体原样搬、缩进不变。主要工作量是把函数内对 controller 字段/方法的引用改成 `_ctrl.xxx`（如 `WEAPON_POOL` → `_ctrl.WEAPON_POOL`）。
3. **strangler fig 接口稳定技巧**：子系统一律经 `ctrl._owned_arr()` / `ctrl._save_meta()` 等 controller 方法读写。这些方法在步骤 1/5 会变成"转发"，但**调用点永远不用改**——每步互不牵连的关键。
4. 所有 `.gd` 编辑走 **Python 字节级归一 CRLF**（Edit 工具会混入 LF，Godot 报错；本仓库 `.gd` 全是 CRLF）。
5. 子系统为 `RefCounted`，构造注入 `_init(ctrl)`，**不持有 meta 所有权**（meta 是 controller 的 Dictionary 引用，子系统直接改会复现"只读快照不可写回"类 bug）；写回统一经 controller 方法或直接改 meta 对应键后调 `ctrl._save_meta()`。
6. **子系统之间不互相调用**，跨系统联动（如授予后刷新 UI、奖励后推进房间）一律留在 controller 编排层。
7. `RefCounted` 无 Node 树：子系统内**不能** `await get_tree().create_timer()`；协程/动画节拍必须借 controller 的 Timer（参考铁砧 `_spin_cell` 的 `is_instance_valid` 教训）。

## 4. 状态归属表（变量随谁走）

| 变量（行号） | 归属 | 说明 |
|---|---|---|
| `meta` / `ANVIL_SAVE_KEY`（279/282） | controller 持有，读写逻辑归 MetaStore | 存档字典引用注入 MetaStore |
| `anvil_run_awarded` / `last_anvil_drops`（280/281） | AnvilSystem | 本局 drip 累计 / 最近一次结果（UI 显示） |
| `anvil_*` @export 常量（170–177） | 参数化传入 AnvilSystem | RefCounted 不能在 Inspector 编辑，常量留 controller，调用时传参 |
| `gold`（226） | controller | 局内金币，ShopSystem 经 ctrl 读写 |
| `gold_upgrades`（274） | ShopSystem | 局内金币升级等级 |
| `paid_price`（272） | ShopSystem | 卖出返还依据 |
| `loadout_max / skill_max / charm_max`（77–79） | controller | 每局槽位，LoadoutSystem 读写、ShopSystem 经 ctrl 调 `_grow_slot` |
| `selected_loadout/consumables/charms/skills`（207–210） | controller | 勾选状态，LoadoutSystem 读写 |
| `run_symbol_bonus / run_power_bonus / run_shield_next`（264–266） | RewardSystem | 局内加成层 |
| `reward_choices / reward_is_boss`（267/268） | controller 编排 | RewardSystem 生成，controller 弹屏 |
| `shop_offers`（269） | ShopSystem | 商店货架 |
| `charm_*`（250–257） | controller | 战斗字段，`_apply_charms` 留 controller |
| `_weapon_power_map / _item_crit_map / pool / pool_items`（121–123） | controller | 战斗池构建，`_build_pool` 留 controller |

## 5. 函数搬迁总表（真实行号，2026-08-06 核对）

### 5.1 MetaStore（5 个，纯 IO）

| 函数 | 行号 |
|---|---|
| `_load_meta` | 786 |
| `_save_meta` | 798 |
| `_seed_default_owned` | 807 |
| `_sanitize_owned` | 842 |
| `_award_gold` | 897 |

> `_award_meta`（铁砧点 drip）**故意留到步骤 2**——它与图鉴里程碑红包联动，跟 Anvil 一起搬更干净。

### 5.2 AnvilSystem（11 个）

| 函数 | 行号 |
|---|---|
| `_roll_anvil_cell` | 1184 |
| `_anvil_drop_for` | 1207 |
| `_anvil_rarity_weight` | 1225 |
| `_anvil_pool` | 1232 |
| `_anvil_is_owned` | 1243 |
| `_anvil_not_yet_owned` | 1246 |
| `_anvil_grant_owned` | 1253 |
| `_resolve_anvil_drop` | 1266 |
| `_anvil_collection_pct` | 1285 |
| `_check_collection_milestones` | 1295 |
| `_award_meta` | 875 |

### 5.3 ShopSystem（11 个）

| 函数 | 行号 |
|---|---|
| `_shop_price` | 904 |
| `_shop_name` | 922 |
| `_roll_shop` | 931 |
| `_on_shop_buy_pressed` | 948 |
| `_sell_price` | 1014 |
| `_on_shop_sell_pressed` | 1023 |
| `_gold_upgrade_def` | 1067 |
| `_gold_upgrade_cost` | 1074 |
| `_gold_upgrade_desc` | 1082 |
| `_gold_upgrade_defs` | 1091 |
| `_on_gold_upgrade_pressed` | 1106 |

### 5.4 RewardSystem（7 个）

| 函数 | 行号 |
|---|---|
| `_roll_rewards` | 672 |
| `_roll_elite_rewards` | 687 |
| `_roll_boss_rewards` | 693 |
| `_apply_reward` | 723 |
| `_apply_boss_reward` | 763 |
| `_roll_meta_choices` | 646 |
| `_on_meta_choice_chosen` | 661 |

### 5.5 LoadoutSystem（9 个）

| 函数 | 行号 |
|---|---|
| `_on_card_toggled` | 477 |
| `_sel_arr` | 493 |
| `_cat_max` | 503 |
| `_cat_cap` | 513 |
| `_can_grow_slot` | 523 |
| `_cap_text` | 529 |
| `_grow_slot` | 535 |
| `_cat_name` | 543 |
| `_owned_arr` | 863 |

### 5.6 留在 controller（不搬）

- 编排/UI 接线：`_on_anvil_roll_pressed`（变薄）、`_on_anvil_back_pressed`、`_on_shop_leave_pressed`、`_on_shop_requested`、`_on_reward_chosen`、`_on_reward_skip_pressed`、`_on_boss_reward_chosen`、`_show_meta_choice`、`_confirm_loadout`、`_apply_charms`、`_return_to_loadout`
- 战斗核心：`_begin_spin` / `_build_strips` / `_on_spin_tick` / `_write_reel_cell` / `_lock_reel` / `_stop_next_reel` / `_finish_spin`（1539–1700）、`_evaluate`（2009–2166，157 行，收尾可选拆）、`_contribute` / `_push_dmg_line`（1930–1982）、buff/status 聚合（2166–2252）
- run 流程：`_full_reset` / `_build_run` / `_sort_rooms` / `_start_room` / `_is_boss_room` / `_is_run_final` / `_enter_interroom` / `_on_next_room_pressed`（1134–1384）
- 生命周期：`_ready` / `_build_state` / `_build_pool` / `_eff_element`

## 6. 实现步骤（每步 = 迁移 + 薄转发 + commit → 用户 F6 → 通过再下一步）

### 步骤 0：基线整理（无代码改动）

```
git checkout -- project.godot   # 还原 CRLF 伪改动（core.autocrlf 导致，非真实改动）
git status                      # 确认工作树干净
```

### 步骤 1：抽 MetaStore（风险最低）

| 项 | 内容 |
|---|---|
| 新文件 | `scripts/systems/meta_store.gd`（`class_name MetaStore extends RefCounted`，`_init(ctrl: DuelController, meta: Dictionary)`） |
| 迁入 | §5.1 的 5 个纯 IO 函数 |
| controller | 同名薄转发：`func _save_meta(): _meta.save()` 等 |
| **F6 测试** | ① 跑 1 房 → 死亡 → 回整备 → **退出游戏重进**：拥有池 / 铁砧点数保留（`_save_meta` 生效）② 删 `user://lobby_data.json` → 重进：种子重建 + `_sanitize_owned` 自愈无报错 |
| 提交 | `refactor: 抽 MetaStore 存档子系统` |

### 步骤 2：抽 AnvilSystem

| 项 | 内容 |
|---|---|
| 新文件 | `scripts/systems/anvil_system.gd`（`class_name AnvilSystem extends RefCounted`，`_init(ctrl)`） |
| 迁入 | §5.2 的 11 个函数 |
| controller | `_on_anvil_roll_pressed` 变薄编排（扣点 → `_anvil.compute_roll()` → `_anvil.resolve(d)` → `_save_meta` → `hud._refresh_anvil()`）；`_on_anvil_back_pressed` 留 |
| 依赖 | 经 `ctrl._owned_arr()` / `ctrl._save_meta()` 读写（步骤 5 后自动变转发，调用点不改） |
| **F6 测试** | ① 摇奖扣 10 点 ② 三连动画、三格同符号 ③ 抽中新件 → 整备栏**立即刷新** ④ 重复件 → 软保底返点 ⑤ 图鉴 % → 里程碑红包 ⑥ 每房 drip 点数、封顶 40 |
| 提交 | `refactor: 抽 AnvilSystem 铁砧子系统` |

### 步骤 3：抽 ShopSystem

| 项 | 内容 |
|---|---|
| 新文件 | `scripts/systems/shop_system.gd`（`class_name ShopSystem extends RefCounted`，`_init(ctrl)`） |
| 迁入 | §5.3 的 11 个函数 |
| controller | `_on_shop_leave_pressed` / `_on_shop_requested` 留（UI 导航/编排）+ 薄转发 |
| 关键 | **保住 `3117c6d` 修复**：buy 里仅 `kind=="weapon"/"passive"` 写 owned_*，skill 跳过（防 SkillData 进 owned_weapons 崩溃） |
| **F6 测试** | ① 买武器 → 扣金 + 开槽 + 下次涨价 ② 买护符 → cap 3 硬顶 ③ **买技能 → 不崩、不进 owned_weapons**（3117c6d 回归）④ 卖出 → ~50% 回收 ⑤ 金币升级 4 项（锋锐研磨 / 连线精通 / 护符共鸣 / 壁垒）生效 |
| 提交 | `refactor: 抽 ShopSystem 商店子系统` |

### 步骤 4：抽 RewardSystem

| 项 | 内容 |
|---|---|
| 新文件 | `scripts/systems/reward_system.gd`（`class_name RewardSystem extends RefCounted`，`_init(ctrl)`） |
| 迁入 | §5.4 的 7 个函数 |
| controller | `_on_reward_chosen` / `_on_reward_skip_pressed` / `_on_boss_reward_chosen` / `_show_meta_choice` 留（UI 选择接线 + 房间推进编排）+ 薄转发 |
| **F6 测试** | ① 普通房三选一（治疗 / 灌注 / 结界各验一次）② 精英房战前补给三选一 ③ BOSS 奖励 → 通关开新局 ④ 局末元进度三选一（武器 +3 / 护符 ×0.12 / 命中 +5%） |
| 提交 | `refactor: 抽 RewardSystem 奖励子系统` |

### 步骤 5：抽 LoadoutSystem（与战斗耦合最多，放最后）

| 项 | 内容 |
|---|---|
| 新文件 | `scripts/systems/loadout_system.gd`（`class_name LoadoutSystem extends RefCounted`，`_init(ctrl)`） |
| 迁入 | §5.5 的 9 个函数 |
| controller | `_confirm_loadout`（触发 `_full_reset`/`_build_pool` 战斗准备）、`_apply_charms`（写 `charm_*` 战斗字段）**留 controller**——与战斗强耦合 |
| **F6 测试** | ① 整备四类勾选 ② 槽位显示与增长 ③ 武器/技能无硬顶 ④ 消耗品腰带 4 格 ⑤ 护符 cap 3 ⑥ 确认开战正常 ⑦ 护符合成生效 ⑧ **铁砧新件仍显示**（`_owned_arr` 变转发后） |
| 提交 | `refactor: 抽 LoadoutSystem 整备子系统` |

### 步骤 6：收尾（清理 + 回归）

- 删除 controller 顶部 M0–M6 历史注释（~250 行，摘要迁到各子系统头注释防信息丢失）。
- 核查 controller 只剩：编排 + 薄转发 + 战斗核心。
- 可选：拆 `_evaluate`（157 行）→ 逼近 1000 行内（属方案 A，可跳过）。
- **F6 测试**：完整跑一局——整备 → 商店 → 战斗（三连暴击 / special 连锁）→ 精英 → BOSS → 死亡回整备 → 元进度三选一 → 通关开新局。
- 提交：`refactor: 清理历史注释 + 瘦身核查`

## 7. 完成后的目标结构

```
scripts/
├── battle/
│   ├── duel_controller.gd      # ~1300 行：编排 + 薄转发 + 战斗核心
│   ├── battle_math.gd          # 纯结算（已有）
│   ├── battle_state.gd         # 只读快照（已有）
│   ├── loadout_item.gd         # 基类（已有）
│   ├── symbol_data.gd / weapon_data.gd / skill_data.gd（已有）
├── systems/                    # ★ 新建
│   ├── meta_store.gd           # 存档
│   ├── anvil_system.gd         # 铁砧 gacha
│   ├── shop_system.gd          # 商店 + 金币升级
│   ├── reward_system.gd        # 房奖励 + 元进度三选一
│   └── loadout_system.gd       # 整备 / 槽位 / 拥有池读
└── ui / loadout / utils / ...  # 不变
```

## 8. 风险与注意

- **不做 autoload、不做全局注册表**（项目铁律，反垄断根因；子系统一律组合注入）。
- **meta 写回纪律**：子系统改 meta 键后必须调 `ctrl._save_meta()` 落盘；跨系统联动（授予后刷新 UI / 奖励后推进房间）留在 controller 编排。
- **RefCounted 无协程**：动画节拍借 controller 的 Timer。
- **`@export` 常量不随子系统走**：RefCounted 资源无法在 Inspector 编辑，常量留 controller、调用时传参。
- **CRLF**：本仓库 `.gd` 全 CRLF，编辑一律 Python 字节级归一。
- 已推送提交（c7bd8d2 等）之后的新提交为 `3117c6d`（本地未推送，本次重构在其上继续，最后一起推）。
