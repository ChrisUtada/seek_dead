# 基线：地图巡逻诱导 Step 2 移动、等待、回访与镜头（2026-11-14）

## 1. 用途

本目录保存 Step 2 的单套实跑证据，用于：

- 复核「非相邻格不移动 / 等待只推进一次 / 回访不重复结算 / 查看与取消不改变 RNG / 镜头与按钮不越界 / 正式入口保持关闭」六条出口；
- 复核 Step 2 任务 7 的 `g8_loadout_layout_test` 未因本步失效（旧双开关与两个模式按钮仍在）。

全量回归不在本目录，按项目纪律由用户执行 `run_smoke.bat`。

## 2. 文件

| 文件 | 来源 | 结论 |
|---|---|---|
| `map_move.out.log` | `res://tests/map_move_test.tscn`（第 54 套） | `MAPMOVE\|RESULT PASS (checks=142 fails=0)` |
| `g8_layout_entry.out.log` | `res://tests/g8_loadout_layout_test.tscn`（第 21 套，既有） | `G8_LAYOUT\|RESULT PASS (121/121)` |

## 3. 复现命令

```bat
set APPDATA=%TEMP%\seek_dead_mapmove_appdata
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/map_move_test.tscn
"%GODOT%" --headless --fixed-fps 60 --path . res://tests/g8_loadout_layout_test.tscn
```

`APPDATA` 重定向到临时目录，不读写真实 `lobby_data.json`。

## 4. 判读要点

- 第 54 套的分组顺序为 A 相邻移动 / B 等待 / C 回访 / D 查看与取消 / E 镜头 / F 操作栏 / G 存档恢复 / H 入口闸门，合计 142 项。
- `FAIL` 计数必须为 0；`MAPMOVE|RESULT` 行是唯一权威结论。
- 日志尾部的 `ObjectDB instances were leaked` / `2 resources still in use` 与 Step 4–8 历史日志同类，属 Godot 退出期告警，不影响 RESULT。
- 本步**未**改 `board_system.gd` / `board_screen.gd` / `board_config.gd`，若这两份日志出现旧双开关相关断言失败，说明有并行改动破坏了 Step 2 边界，应先查该三个文件。
