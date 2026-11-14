# 2026-11-14 · 地图巡逻诱导 Step 2 阶段 1 基线

## 用途

保存 `MapBoardBuilder`（14×9 MapGrid → BoardSystem 节点图适配层）的单套运行证据。
这是**适配层独立验证**，不经过 `BoardSystem.generate()`、不加载 `board_screen`、不改现有运行入口。

## 运行

```text
Godot_v4.7-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tests/map_builder_test.tscn
```

运行前把 `APPDATA` 重定向到临时目录（本目录已按此方式采集），避免写真实 `lobby_data.json`。

## 结论

```text
MAPBUILD|RESULT PASS (checks=48 fails=0)
PASSED 48 / FAILED 0
```

| 分组 | 断言数 |
|---|---:|
| A 结构 | 17 |
| B 邻接与可达 | 6 |
| C 房间绑定 | 8 |
| D 固定种子与三幕 | 9 |
| E 无旧模型残留 | 8 |

## 时点说明

- 本测试**未注册**进 `run_smoke.bat`，当前全量仍是 50 套。
- 4 个既有脚本的侵入式收敛已回滚，因此本基线不覆盖「运行入口切换」。
- 日志尾部 `ObjectDB instances were leaked` / `2 resources still in use` 与 Step 4–8 历史日志同类，非本次引入，`RESULT` 为 PASS。

## 关联文档

- `docs/Step2_阶段1_MapBoardBuilder适配层_2026-11-14.md`
- `docs/Step1_地图巡逻诱导_14x9灰盒地图_2026-11-14.md` §6（Step 2 待办清单）
- `docs/Step0_地图巡逻诱导_冻结数据口径与兼容边界_2026-11-14.md` §6.1（连带影响清单）
