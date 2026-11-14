# 地图巡逻诱导 · Step 2 阶段 1 · MapBoardBuilder 适配层（2026-11-14）

> ⚠️ **口径已作废（2026-11-14 13:41）**：主计划更新后新增 §6 Step 0.5，明确「不得通过退役 `g7_run3_test` 或 `loot_explore_test` 规避」，且 Step 2 任务 6 规定收敛与旧模型迁移不得绕过 Step 5A。本文档「切运行入口 + 退役 5 套回归」的方向及 §4 的三选项**全部作废**，改按 `docs/Step0.5_前置终局与奖励语义契约_2026-11-14.md` 执行。本文仅保留为当时的核查记录。
>
> 状态：✅ 阶段 1 适配层成果保留并已被 Step 0.5 吸收；**运行入口切换未执行**，原因见 §4（该原因已由 Step 0.5 解决）
> 依据：`docs/地图巡逻诱导_第一版预算与分步执行计划_2026-11-14.md` §6 Step 2、`docs/Step0_地图巡逻诱导_冻结数据口径与兼容边界_2026-11-14.md` §6.1
> 口径：作者 2026-11-14 决定「替换、工程内只保留一种 14×9 地图」

## 1. 结论

Step 2 被拆成两层：**2A 技术债**（切运行入口、收敛脚本、处置旧回归、退役旧脚本）与 **2B 计划正文**（相邻格移动、等待、回访、镜头、存档）。本轮按「先做 2A」推进，做到一半发现计划层面的连带冲突，**主动停在可运行状态**。

已交付并验证的是 2A 的前置：**14×9 MapGrid → BoardSystem 节点图的唯一适配层**。它证明「切入口」在数据层没有障碍，48 项定向断言全绿。侵入式改动（4 个既有脚本）已全部回滚，工作区保持可运行、既有 50 套回归不受影响。

## 2. 交付文件

| 文件 | 内容 |
|---|---|
| `scripts/board/map_board_builder.gd` + `.gd.uid` | 唯一适配层：`build(act, seed)` 把 126 格转成 61 个节点，绑定现有 `RoomData`，保留原始 `grid` 数据 |
| `tests/map_builder_test.gd` + `.gd.uid` + `.tscn` | 定向回归（48 项，5 组），**未注册进 `run_smoke.bat`**，不影响现有 50 套 |
| `docs/baseline/2026-11-14_map_step2a/map_builder.out.log` | 运行证据：`MAPBUILD\|RESULT PASS (checks=48 fails=0)` |

```
MAPBUILD|RESULT PASS (checks=48 fails=0)
```

| 分组 | 覆盖 | 结果 |
|---|---|---|
| A 结构 | 61 节点 / 28 内容 / 16 战斗、类型计数、start·boss、battle_rooms | 17 / 0 |
| B 邻接与可达 | 双向对称、四方向不越界、61 格全连通、起点到 BOSS 可达 | 6 / 0 |
| C 房间绑定 | 16 个战斗节点全部有 RoomData、kind 一致、battle_index 连续、ACT1 节奏样板 | 8 / 0 |
| D 固定种子与三幕 | 同种子一致、异种子可区分、布局/陷阱/巡逻起点不随种子变、ACT1/2/3 池非空 | 9 / 0 |
| E 无旧模型残留 | 无扫雷数字 / 骰子字段、保留 126 格 / 3 陷阱 / 3 巡逻起点 | 8 / 0 |

适配层边界：只做静态数据转换与房间冻结；运行时状态（`consumed` / `revealed` / `defeated`）仍由 `BoardSystem` 持有；不写回共享装备资源；不产生扫雷数字、行动点或第二套移动资源。

## 3. 数据层适配说明

| 差异 | MapGrid（Step 1） | BoardSystem 期望 | 适配方式 |
|---|---|---|---|
| 单位 | 126 格，其中 61 可走 | `nodes: Array` + `by_id` | 61 个可走格各成一个节点，空格 `type="empty"`（只移动、不结算，由 `duel_controller._on_board_node_entered` 的 `_:` 兜底） |
| 拓扑 | `neighbors(data, id)` 静态函数 | 每节点 `next: Array[String]` | 用 `MapGrid.neighbors()` 填 `next`，不另建拓扑 |
| 内容 | 28 个内容节点（按 cell_id 索引） | 节点 `type` | 覆盖到对应格子，保留 `variant` / `final` |
| 战斗房 | 未绑定 | 每节点 `room: RoomData` + `battle_index` | 从 `_ctrl.ALL_ROOMS` 按幕 / kind 取，ACT1 沿用冻结节奏样板；池耗尽允许复用首项，仍由 seed 决定 |
| 可见性 | 位置始终公开（§3.4） | `revealed` 运行时字典 | 全部置公开，不设隐藏揭示 |

每幕房间池实测：normal 12 / elite 4 / boss 4–5，刚好支撑 16 个战斗节点。

## 4. 🔴 为什么停在这里：切入口会提前触发 Step 5 契约

上一轮给出的 6 套回归处置判定，在逐条核断言后发现**实际是 7 套，且其中 2 套不能迁移**：

| 套 | 文件 | 原判定 | 复核后 | 依据 |
|---|---|---|---|---|
| 16 | `m2_board_test` 1622 行 | 退役 | 退役 | 25 节点 1D3 骨架、4 BOSS、骰子、`shape_id/template_id` |
| 21 | `g8_loadout_layout_test` | **本轮新发现** | 迁移 | 断言 `layout_mode` / `use_grid()` 双开关与两个按钮 |
| 22 | `g7_run3_test` 392 行 | 迁移 | 🔴 **不能迁移 → 退役** | 断言「4 个 BOSS 节点都标记 final」「ACT III 4 个 final」「ACT II 无 final」；新地图只有 1 个 BOSS |
| 27 | `mine_grid_test` 473 行 | 退役 | 退役 | 直接 `preload board_grid.gd`、4×4 格 id、扫雷数字 |
| 29 | `rhythm_windows_test` | 改数据源 | 改数据源 | 第 328 行 `board_grid.gd.new(duel)` 取 board samples |
| 30 | `grid_templates_test` 213 行 | 退役 | 退役 | 3 套受控模板 + 威胁带，14×9 只有 1 套静态布局 |
| 44 | `loot_explore_test` 358 行 | 迁移 | 🔴 **不能迁移 → 退役** | `_board_item_sig()` 要求 `weapon` / `charm` / `armory` 格与 `treasure_kind` / `armory_paths`；`_test_frozen_board_content` 断言 `seen_armory > 0` 且物品全部来自 `chest` 来源。14×9 的 28 个内容节点不含这些类型 |

另有两项**产品契约**必须同步改造，否则切入口后游戏本身会坏：

1. **三幕 `final` 语义**：`MapGrid` 把 BOSS 节点 `final = (content == "boss")` 静态写死，而 `advance_act()` / `run_final` 要求只有最后一幕的 BOSS 才结束整局。ACT I 打完 BOSS 就收口，三幕链断掉。需要按 `cfg.acts` 决定 `final`。
2. **棋盘探索物品来源**：旧骨架的 `weapon` / `charm` / `armory` 格承载 loot 四级品质体系的「冻结棋盘物品」出口（Step 5 / Step 8）。14×9 用 `treasure` 统一承担，物品绑定与 `chest` 来源标签需要重新设计 —— 这属于计划 §6 **Step 5「接入奖励、成长与路线分工」**，不是 Step 2。

也就是说：**退役 22 / 44 会拆掉三幕链与刚完成的 loot 探索冻结回归；不退役就得提前做 Step 5。** 两者都超出「退役 3 套」的已确认范围，因此本轮不擅自执行。

## 5. 回滚说明

本轮曾把 `board_config.gd` / `board_system.gd` / `board_screen.gd` / `loadout_scene.gd` 收敛为单路径（含移除双开关、16 处 `_is_grid()` 分支、扫雷数字绘制、双按钮）。因这些改动会让上述 7 套回归立刻失效、且触发 §4 的契约问题，已用 `git checkout --` **全部回滚到 HEAD**，工作区恢复可运行。内容未丢失，方向确认后可重放。

## 6. 本轮改动范围

只新增 4 个文件（适配层 + 测试 + uid）、1 个证据文件、1 份文档。**未修改任何既有产品代码、资源、数值、测试或 `run_smoke.bat`**；未提交。

## 7. 待定方向

见对话中的三个选项。任一方向确认后，2A 剩余工作按 `docs/Step1_地图巡逻诱导_14x9灰盒地图_2026-11-14.md` §6 的 7 项清单推进。
