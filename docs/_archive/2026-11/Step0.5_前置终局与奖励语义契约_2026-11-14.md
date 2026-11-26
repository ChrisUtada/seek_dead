# 地图巡逻与诱导 · Step 0.5 · 前置终局与奖励语义契约（2026-11-14）

> 状态：✅ 已完成并实跑；新增 3 套定向回归，计划要求保留的 3 套旧回归全部复验通过
> 依据：`docs/地图巡逻诱导_第一版预算与分步执行计划_2026-11-14.md` §6 Step 0.5 / §6 Step 2 任务 6 / §7 / §8 / §9（2026-11-14 13:41 更新版）
> 前提：主计划 13:41 更新后明确「**不得通过退役 `g7_run3_test` 或 `loot_explore_test` 规避**」，并要求保留 `layout_mode / use_grid()` 双开关、正式入口默认关闭。此前按「切运行入口 + 退役旧回归」的 2A 方向**已作废**，侵入式改动全部回滚。

## 1. 结论

Step 0.5 的六项任务全部落地，五条自动出口全部通过。做法是**为 14×9 新地图建立独立的数据契约与开发／AI 测试入口**：旧运行入口、旧模型、旧回归一律不动；新地图的类型注册表、终局语义、奖励来源在开发入口里先冻结，等 Step 5A 完成再开放正式入口。

```text
MAPACT|RESULT  PASS (checks=28 fails=0)     # 第 51 套 · 配置驱动多幕终局
MAPLOOT|RESULT PASS (checks=38 fails=0)     # 第 52 套 · 节点类型与真实来源
MAPBUILD|RESULT PASS (checks=48 fails=0)     # 第 53 套 · 适配层结构 / 邻接 / 房间绑定
PASSED 53 / FAILED 0                         # g7_run3_test（旧三幕链，未改）
LOOTEXPLORE|RESULT PASS (checks=23 fails=0) # loot_explore_test（旧探索冻结，未改）
G8_LAYOUT|RESULT PASS (121/121)              # g8_loadout_layout_test（双开关布局，未改）
```

## 2. §6 Step 0.5 六项任务对应

| # | 任务 | 落地 |
|---|---|---|
| 1 | 多幕终局配置驱动，禁止把 BOSS `final` 静态写死 | `MapBoardBuilder.build(act, seed, total_acts)` 按 `act >= total_acts` 决定 `final`；`normalized_acts()` 把幕数夹在 `[1, 3]`，`MAX_ACTS=3` 杜绝 ACT IV。`acts=1` 唯一 BOSS final；`acts=3` 仅 ACT III final，ACT I/II 可继续 |
| 2 | 节点类型注册表 `battle / elite / boss / chest / armory / shop / rest / event` | 新增 `scripts/board/map_node_types.gd` 的 `TYPES` 注册表，含 `source / settlement / legacy / label / icon`。内容节点 `type` 必须命中注册表；`path` / `start` 是地形，不计入注册表 |
| 3 | 奖励来源映射 | 注册表固定 `source`：`chest→chest`、`armory→armory`、`shop→shop`、`rest→rest`、`event→event`、战斗节点→`room`。`shop` 不伪装成宝箱，`rest` 不生成装备，`event` 走独立 shrine 配置 |
| 4 | 固定 `treasure_kind / armory_paths` 等探索字段 | `fill_explore_fields()` 从 `RewardSystem.pick_explore_loot()`（chest 来源表）取真实路径；`chest` 写 `treasure_kind ∈ {weapon, charm, active, gold}` + `item_path`；`armory` 写两把互不重复的武器；禁止空类型或伪造节点 |
| 5 | 正式入口默认关闭，只有开发／AI 测试入口可提前进入 | `board_config.gd` 新增 `map14x9_enabled=false`（正式入口）与 `map_dev_override` / `--map14x9-dev`（开发入口）；`map14x9_active()` 统一判定。Step 5A 完成前不打开正式入口 |
| 6 | 将 `g8_loadout_layout_test` 纳入入口验收 | 第 21 套原样保留并复跑 `PASS (121/121)`；双开关与两个按钮**未改**，符合 §7「入口布局」矩阵 |

## 3. §6 Step 0.5 自动出口自检

| 出口 | 判定 | 证据 |
|---|---|---|
| `g7_run3_test` 继续覆盖旧三幕结构，不删除、不跳过 | ✅ | 文件与注册未动，实跑 53/53；`run_act_count()` 仍为 3 |
| 新增 `map_act_chain_test`：`acts=1` 唯一 BOSS final；`acts=3` 仅 ACT III final；ACT I/II 可继续；无第四幕 | ✅ | 第 51 套，28 项全通过 |
| `loot_explore_test` 继续覆盖旧探索冻结回归 | ✅ | 文件与注册未动，实跑 23/23 |
| 新增 `map_loot_explore_test`：新节点类型、真实来源映射、冻结内容、撤回／回访不重复结算 | ✅ | 第 52 套，38 项全通过 |
| `g8_loadout_layout_test` 的入口开关与布局断言通过 | ✅ | 实跑 121/121 |

**§7 验收矩阵对应**：多幕终局（旧 + 新两套）、探索来源（旧 + 新两套）、入口布局（旧一套）三项均已有回归覆盖。

## 4. 节点类型与来源映射表

| `type` | `source` | `legacy_type` | 结算语义 | 数量 | 探索字段 |
|---|---|---|---|---:|---|
| `battle` | `room` | `normal` | 转轮战斗 | 12 | `room` / `battle_index` |
| `elite` | `room` | `elite` | 精英战 | 3 | 同上 |
| `boss` | `room` | `boss` | BOSS 战，final 由幕数决定 | 1 | 同上 |
| `chest` | `chest` | `treasure` | 宝箱 | 3 | `treasure_kind` + `item_path` |
| `armory` | `armory` | `armory` | 武器藏库二选一 | 1 | `armory_paths`（2 把） |
| `shop` | `shop` | `shop` | 商店结算 | 1 | 不写装备路径 |
| `rest` | `rest` | `rest` | 休整 | 2 | 不写装备路径 |
| `event` | `event` | `shrine` | 神龛独立配置 | 4 | `shrine_kind` / `shrine_value` |
| `start` / `path` | — | — | 地形，无结算 | 1 / 33 | — |

MapGrid 的 4 个 `treasure` 按 cell_id 最小者固定为 `armory`，其余为 `chest`；布局与 seed 都稳定可复现。`legacy_type` 只用于 Step 5A 之前映射到既有结算函数，不是第二套节点口径。

## 5. 保留现状（按 Step 2 任务 6 / Step 5A）

- `board_generator.gd`（1D3 骨架）、`board_grid.gd`（4×4 扫雷）**未退役、未改**；
- `board_system.gd` / `board_screen.gd` 的 `grid_mode` / `_is_grid()` 分支**未收敛、未改**；
- `board_config.gd` 的 `layout_mode` / `use_grid()` / `--grid` 双开关**未移除**（仅新增 3 个新地图字段）；
- `run_smoke.bat` 原有 1–50 套编号与注册**未删改**，只新增 51–53 套；
- `g7_run3_test` / `loot_explore_test` / `g8_loadout_layout_test` 三套**文件与注册均未动**。

## 6. 交付文件

| 文件 | 内容 |
|---|---|
| `scripts/board/map_node_types.gd` + `.gd.uid` | 节点类型注册表、来源映射、探索字段写入 |
| `scripts/board/map_board_builder.gd` + `.gd.uid` | 适配层：配置驱动 final、注册表类型、探索字段、房间冻结 |
| `scripts/board/board_config.gd` | 新增 `map14x9_enabled` / `map_dev_override` / `map14x9_active()`；旧双开关保留 |
| `tests/map_act_chain_test.gd` + `.tscn` + `.gd.uid` | 第 51 套，28 项 |
| `tests/map_loot_explore_test.gd` + `.tscn` + `.gd.uid` | 第 52 套，38 项 |
| `tests/map_builder_test.gd` + `.tscn` + `.gd.uid` | 第 53 套，48 项（同步更新为新类型断言） |
| `run_smoke.bat` | 注册 `[51/53]`–`[53/53]`，编号 1–53 齐全无缺号重复 |
| `docs/baseline/2026-11-14_map_step05/` | 3 套新测试 + 3 套旧回归的运行日志 |
| 本文档 | Step 0.5 落地记录 |

## 7. 已知限制与下一步

- ⚪ 新地图**尚未接入产品运行入口**，移动／等待／回访／镜头／存档属 §6 Step 2 五项任务，本步未做。
- ⚪ `legacy_type` 目前只是数据字段，尚未接进 `duel_controller._on_board_node_entered()` 的类型分派；正式结算绑定属 Step 5A / 5B。
- ⚪ `map14x9_enabled` 当前无产品代码读取，只作为「正式入口关闭」的契约占位；Step 5A 完成后才允许接入。
- ⚪ **全量 53 套回归未跑**，按纪律交回用户验证。本步只实跑 3 套新增 + 3 套旧回归 + 第 53 套，日志均在 `docs/baseline/2026-11-14_map_step05/`。
- ⚪ 日志尾部 `ObjectDB instances were leaked` / `2 resources still in use` 与 Step 4–8 历史日志同类，非本步引入。

## 8. 本步改动范围

新增 7 个代码／测试文件；修改 `board_config.gd`（只加字段）、`map_board_builder.gd`（本轮新建）、`map_builder_test.gd`（本轮新建的断言同步）、`run_smoke.bat`（编号 + 3 段注册 + 头部描述）、4 份文档的口径标注。**未修改任何既有产品业务逻辑、资源、数值、旧测试或旧模型**；全部文件未提交。
