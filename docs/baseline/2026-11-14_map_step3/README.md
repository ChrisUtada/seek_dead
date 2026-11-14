# 基线：地图巡逻诱导 Step 3 巡逻与下一步预告（2026-11-14）

## 1. 用途

保存 Step 3 的证据，用于复核四条出口：

- 预告位置与实际行动位置 100% 一致；
- 多只怪物行动顺序固定；
- 巡逻不穿墙、不越界、不永久堵死 BOSS；
- 同一地图种子和输入序列得到完全一致结果。

以及确认本步没有回退 Step 1 / 2 / 0.5 的既有契约。

## 2. 文件

| 文件 | 来源 | 结论 |
|---|---|---|
| `map_patrol.out.log` | `res://tests/map_patrol_test.tscn`（第 55 套） | `MAPPATROL\|RESULT PASS (checks=116 fails=0)` |
| `map_move_regression.out.log` | 第 54 套 `map_move_test`（Step 2） | `MAPMOVE\|RESULT PASS (checks=142 fails=0)` |
| `map_builder_regression.out.log` | 第 53 套 `map_builder_test`（Step 0.5/1 适配层） | `MAPBUILD\|RESULT PASS (checks=48 fails=0)` |

同批还跑了第 50 套 `MAPGRID PASS (66)`、第 51 套 `MAPACT PASS (28)`、第 52 套 `MAPLOOT PASS (38)`，均通过；未重复保存日志。

## 3. 复现命令

```bat
set APPDATA=%TEMP%\seek_dead_mappatrol_appdata
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/map_patrol_test.tscn
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/map_move_test.tscn
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/map_builder_test.tscn
```

## 4. 判读要点

- 第 55 套分组顺序：A 结构 42 / B 预告一致 4 / C 占格与撞击 20 / D 追上玩家 9 / E 行动顺序 16 / F 确定性 5 / G 不堵 BOSS 5 / H 只读 5 / I 存档 10，合计 116。
- 巡逻在 `MapRuntime` 里是**显式开关**：`create(ctrl, act, seed, total_acts, with_patrols)`。第 54 套用默认 `false`，因此 Step 2 的 142 项不受巡逻影响；第 55 套用 `true`。
- 若第 54 套开始失败，先检查是否有人把 `with_patrols` 默认值改成 `true`——那会让巡逻占格改变 Step 2 的移动可达性。
- 日志尾部的 `ObjectDB instances were leaked` / `2 resources still in use` 属 Godot 退出期告警，与 Step 4–8 历史日志同类，不影响 RESULT。
