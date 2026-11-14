# Step 8 基线 · 大奖池统计、平衡与完整回归（2026-11-14）

对应说明：`docs/Step8_大奖池统计平衡与完整回归_2026-11-14.md`
对应计划：`docs/四级品质战利品与大奖池_分步执行计划_2026-11-12.md` Step 8

## 文件

| 文件 | 内容 |
|---|---|
| `smoke.out.log` | `run_smoke.bat` 全量 47 套输出（`[smoke] RESULT`） |
| `loot_balance.log` | 第 47 套 `loot_balance_test` 原始输出（86 项） |
| `smoke_loot_line.txt` | 第 4 套全流程跑局的战利品不变量汇总行 |

## 关键结果

| 项 | 结果 |
|---|---|
| 全量套件 | 47 / 47 ALL GREEN |
| 第 4 套全流程 | checks=2654, fails=0 |
| 第 47 套统计与平衡 | checks=86, fails=0，约 12s |
| 来源分布（10,000 次/来源/幕） | 最大偏差 1.23pp ≤ 2pp |
| 生成路径品质（1,000 组/来源/幕） | 最大偏差 4.10pp ≤ 5pp，0 组失败 |
| 批量不变量（1,200 组） | `empty_tier` 0；三项/同层/去重/用途/文案 全 0 违例 |
| 组内严格上位 | 0 条（另有 1 对跨机制线数值差，只作记录） |
| 品质可用性 | 11/12 组合可结算；缺口仅 `epic` × `active`（内容无传说消耗品） |
| 家族基础路径 | 10 个家族 + 混合 Build 全部清掉第 1 房 |
| 选卡策略 | 数值 300.1 / 联动 288.1（−4%），一致性 0.861 → 0.880，家族重叠 93 → 109 |
| 全流程战利品 | offers=49，0 异常；有成长位时 19 次全部正常进入 |

## 本步顺带修的

- `LootPool` 索引补 `unique_group` / `family_tags`：「同机制不重复」贪心此前是死代码；
- 索引 O(1) 查找（`path → entry`），候选资源缓存（`resource_of`）：一组三选一 18ms → 约 0.5ms；
- 三项全同用途时先换同层另一用途的真实物品，池内没有才退化为同层转化。

## 复现

```text
run_smoke.bat
Godot_v4.7-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tests/loot_balance_test.tscn
```
