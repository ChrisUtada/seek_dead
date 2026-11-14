# 基线：地图巡逻诱导 Step 5A 奖励类型、来源与冻结（2026-11-14）

## 1. 用途

保存 Step 5A 的证据，用于复核四条出口：

- 新 `map_loot_explore_test` 用真实节点验证来源、冻结与一次性结算；
- 旧 `loot_explore_test` 不失效、未被退役；
- 地图没有空类型、伪装备来源或落空奖励；
- 查看、撤回、重开界面和回访不重抽、不重复获得。

## 2. 文件

| 文件 | 来源 | 结论 |
|---|---|---|
| `map_loot_explore.out.log` | 第 52 套 `map_loot_explore_test`（38 → 83 项） | `MAPLOOT\|RESULT PASS (checks=83 fails=0)` |
| `loot_explore_regression.out.log` | 旧 `loot_explore_test`（未改一行） | `LOOTEXPLORE\|RESULT PASS (checks=23 fails=0)` |
| `map_builder_regression.out.log` | 第 53 套 `map_builder_test` | `MAPBUILD\|RESULT PASS (checks=48 fails=0)` |

同批还跑了 `map_grid` 66 / `map_act_chain` 28 / `map_move` 142 / `map_patrol` 116 / `map_trap` 106 / `loot_offer` 37 / `growth_loot_offer` 16，均通过；日志未重复保存。

## 3. 复现命令

```bat
set APPDATA=%TEMP%\seek_dead_maptrap_appdata
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/map_loot_explore_test.tscn
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/loot_explore_test.tscn
```

## 4. 判读要点

- 第 52 套分组：A 注册表 20 / B 来源 7 / C 字段 6 / D 冻结 5 / E 冻结内容 7 / F 语义与校验 15 / G 一次性与撤回 23，合计 83。
- 若 E 组「商店货架非空」失败：检查 `MapNodeTypes._freeze_shop_stock` 是否仍传入确定性 RNG；商店走的是 `LootSourceTable.shop_tiers/shop_categories`，若这两个表的 shop 标签被改动，货架可能抽空。
- 若 D 组「同种子完全冻结」失败：多半是某个新字段仍在用奖励池自有 RNG。`roll_ladder` 的 `opts["rng"]` 是唯一正确入口。
- 若 F 组「商店不能免费赠予」失败：说明有人把 `shop` 的 `source` 或 `free` 改成了宝箱语义，那会直接违反 Step 5A 任务 3。
- 旧 `loot_explore_test` 必须保持 23 项通过；它一旦变红，说明新地图改动影响了旧探索冻结路径，先查 `fill_explore_fields`。
