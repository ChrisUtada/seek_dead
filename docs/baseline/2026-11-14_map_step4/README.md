# 基线：地图巡逻诱导 Step 4 破甲陷阱与战斗联动（2026-11-14）

## 1. 用途

保存 Step 4 的证据，用于复核四条出口：

- 陷阱触发一次，效果只结算一次；
- 战斗护甲变化与地图预告一致；
- 不秒杀、不重复触发、不重复发奖；
- 玩家无陷阱路线也能正常击败怪物。

以及确认「陷阱迁位」（45 / 39 / 110）没有破坏 Step 1–3 的契约。

## 2. 文件

| 文件 | 来源 | 结论 |
|---|---|---|
| `map_trap.out.log` | `res://tests/map_trap_test.tscn`（第 56 套） | `MAPTRAP\|RESULT PASS (checks=106 fails=0)` |
| `map_grid_regression.out.log` | 第 50 套 `map_grid_test`（布局改动） | `MAPGRID\|RESULT PASS (checks=66 fails=0)` |
| `map_patrol_regression.out.log` | 第 55 套 `map_patrol_test`（选房改动） | `MAPPATROL\|RESULT PASS (checks=116 fails=0)` |
| `map_move_regression.out.log` | 第 54 套 `map_move_test`（Step 2 契约） | `MAPMOVE\|RESULT PASS (checks=142 fails=0)` |

同批还跑了第 51 套 `MAPACT PASS (28)`、第 52 套 `MAPLOOT PASS (38)`、第 53 套 `MAPBUILD PASS (48)`，均通过；未重复保存日志。

## 3. 复现命令

```bat
set APPDATA=%TEMP%\seek_dead_maptrap_appdata
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/map_trap_test.tscn
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/map_grid_test.tscn
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/map_patrol_test.tscn
```

## 4. 判读要点

- 第 56 套分组：A 数据与公开性 23 / B 触发一次 16 / C 不重复武装 5 / D 只结算一次 19 / E 预告一致 10 / F 不秒杀 8 / G 玩家踩陷阱 7 / H 无陷阱路线 8 / I 存档 10，合计 106。
- 陷阱坐标是 **45 / 39 / 110**。若这三个位置被改回 row4 咽喉（59 / 64），会出现两类失败：第 50 套的「陷阱被占仍可达 BOSS」类断言，以及第 56 套 A 组的「陷阱在巡逻环上」。
- 巡逻怪绑定房间是「有甲优先」。若有人改回纯 `resource_path` 排序，第 56 套 A 组的「绑定的怪有护甲（>0）」会失败，破甲会退化成 0→0。
- 日志尾部的 `ObjectDB instances were leaked` / `2 resources still in use` 属 Godot 退出期告警，与 Step 4–8 历史日志同类，不影响 RESULT。
