# 基线 · 地图巡逻诱导 Step 1 · 14×9 灰盒地图（2026-11-14）

## 用途

保存第 50 套 `map_grid_test` 的**单套**实跑证据，对应 `docs/Step1_地图巡逻诱导_14x9灰盒地图_2026-11-14.md` 的出口自检。

## 运行方式

```
D:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe ^
  --headless --fixed-fps 60 --path . res://tests/map_grid_test.tscn
```

`run_smoke.bat` 中的注册编号为 `[50/50]`，日志名 `smoke_mapgrid.log`。
本套不加载 `duel.tscn`，纯静态数据校验；运行时 `APPDATA` 重定向到临时目录，不读写真实 `lobby_data.json`。

## 结论

```
MAPGRID|RESULT PASS (checks=66 fails=0)
PASSED 66 / FAILED 0
```

| 分组 | PASS | FAIL | 覆盖 |
|---|---:|---:|---|
| A 结构 | 16 | 0 | 14×9 / 126 格 / 61 可走 / 三区域 / 2 门 / 无运行时状态写入 cell |
| B 预算 | 16 | 0 | §1.2 九项数量区间、战斗合计、陷阱位置与类型 |
| C 路线 | 13 | 0 | 起点→BOSS 可达、精英可绕行、无探索率门票、全图连通、起点安全 |
| D 固定种子 | 13 | 0 | 同种子一致、不同种子可区分、揭示/回访/重开不重抽 |
| E validate 防护 | 8 | 0 | 墙化 BOSS / 篡改计数 / 陷阱越界 / 运行时状态写回 / 门堵死等 |

日志内含 `MAPGRID|ASCII` 段，可直接核对 9 行 × 14 列的灰盒布局。

## 边界

- ⚠️ **全量 50 套回归未执行**。本基线只证明第 50 套通过，不能替代 `run_smoke.bat` 全量结论；全量交回作者验证。
- 本步为「分阶段切」的数据层阶段，未切换运行入口；旧 `board_generator.gd` / `board_grid.gd` 仍在运行路径中，第 16/22/27/29/30/44 套未做任何迁移或改动。
- 日志尾部若出现 `ObjectDB instances were leaked` / `resources still in use`，与项目既有 headless 退出告警同类，不影响 `RESULT`。
