# 基线：地图巡逻诱导 Step 5B 接入成长与路线分工（2026-11-14）

## 1. 用途

保存 Step 5B 的证据，用于复核五条出口：

- 装备来源不被错误迁移；
- 成长只结算一次；
- 未选 queued 成长正确保留；
- 宝箱、商店和 BOSS 仍可获取真实装备；
- 图鉴与来源记录一致。

## 2. 文件

| 文件 | 来源 | 结论 |
|---|---|---|
| `map_progress.out.log` | 第 57 套 `map_progress_test` | `MAPPROG\|RESULT PASS (checks=67 fails=0)` |
| `map_move_regression.out.log` | 第 54 套（存档结构加入 `battles` 后） | `MAPMOVE\|RESULT PASS (checks=142 fails=0)` |
| `map_loot_regression.out.log` | 第 52 套 | `MAPLOOT\|RESULT PASS (checks=83 fails=0)` |
| `loot_explore_regression.out.log` | 旧 `loot_explore_test` | `LOOTEXPLORE\|RESULT PASS (checks=23 fails=0)` |

同批还跑了第 50 / 51 / 53 / 55 / 56 套（66 / 28 / 48 / 116 / 106），均通过。

## 3. 复现命令

```bat
set APPDATA=%TEMP%\seek_dead_mapprog_appdata
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/map_progress_test.tscn
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/map_move_test.tscn
```

## 4. 判读要点

- 第 57 套分组：A 分工 12 / B 普通三选一 6 / C 精英 4 / D BOSS 8 / E 装备来源 12 / F 只结算一次 9 / G 队列保留 6 / H 战败 7 / I 来源一致 3，合计 67。
- 若 D 组「BOSS 卡只来自专属类型」变红：说明有人把 BOSS 战利品改成走宝箱池，直接违反 Step 5B 任务 4。
- 若 F 组「二次结算被拒」变红：检查 `resolve_battle` 是否仍在消费 `pending_battle` 之后才查 `battles`；必须先查已结算再消费。
- 若 G 组「不消耗待选成长」变红：检查 `post_battle.build()` 是否被改成会 `pick` 或清空 `pending_picks`。
- BOSS 主题层为空时只剩信物卡属既有 `short_tier` 行为，D 组断言已按「有武器则必须在主题池」判定，不要求必须有武器。
