# 2026-11-14 · 地图巡逻诱导 Step 0.5 基线

## 用途

保存 §6 Step 0.5 六项任务与五条自动出口的运行证据：3 套新增定向回归 + 3 套计划要求保留的旧回归。

运行前把 `APPDATA` 重定向到临时目录，避免写真实 `lobby_data.json`（`run_smoke.bat` 已统一隔离）。

## 结论

```text
MAPACT|RESULT  PASS (checks=28 fails=0)      map_act_chain.out.log       第 51 套
MAPLOOT|RESULT PASS (checks=38 fails=0)      map_loot_explore.out.log    第 52 套
MAPBUILD|RESULT PASS (checks=48 fails=0)      map_builder.out.log         第 53 套
PASSED 53 / FAILED 0                          g7_run3_legacy.out.log      旧三幕链
LOOTEXPLORE|RESULT PASS (checks=23 fails=0)  loot_explore_legacy.out.log 旧探索冻结
G8_LAYOUT|RESULT PASS (121/121)               g8_layout_legacy.out.log    旧入口布局
```

三套旧回归的**文件与 `run_smoke.bat` 注册均未改动**，日志用于证明 Step 0.5 自动出口「不删除、不跳过」成立。

## 时点说明

- 主计划于 2026-11-14 13:41 更新，新增 Step 0.5 / Step 5A / Step 5B；本基线基于更新后的口径。
- 全量 53 套回归未跑，按纪律交回用户验证；本目录只含上述 6 套的单套实跑日志。
- 日志尾部 `ObjectDB instances were leaked` / `2 resources still in use` 与 Step 4–8 历史日志同类，非本步引入，`RESULT` 均为 PASS。

## 关联文档

- `docs/Step0.5_前置终局与奖励语义契约_2026-11-14.md`
- `docs/地图巡逻诱导_第一版预算与分步执行计划_2026-11-14.md` §6 Step 0.5 / §7
