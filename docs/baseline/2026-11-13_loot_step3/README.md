# Step 3 基线 · 来源品质表与统一候选池（2026-11-13）

对应说明：`docs/Step3_来源品质表与统一候选池_2026-11-13.md`
对应计划：`docs/四级品质战利品与大奖池_分步执行计划_2026-11-12.md` Step 3

## 文件

| 文件 | 内容 |
|---|---|
| `smoke.out.log` | `run_smoke.bat` 全量 42 套输出（`[smoke] RESULT: ALL GREEN`） |
| `loot_source_pool.log` | 第 42 套 `loot_source_pool_test` 原始输出（83 项） |

第 4 套全流程原始日志较大（约 330 KB），未入库；需要时运行 `run_smoke.bat` 后查看 `%TEMP%\smoke_full.log`。

## 关键结果

| 项 | 结果 |
|---|---|
| 全量套件 | 42 / 42 ALL GREEN |
| 第 4 套全流程 | checks=2567, fails=0 |
| 第 42 套来源池 | checks=83, fails=0 |
| T7 获取轴 | 28 / 28 |
| T8 掉落渠道 | 21 / 21 |

第 42 套的 10,000 次纯来源表抽样（节选）：

```text
normal  common 0.704 / uncommon 0.246 / rare 0.050 / epic 0.000
elite   common 0.203 / uncommon 0.498 / rare 0.265 / epic 0.033
boss    common 0.000 / uncommon 0.098 / rare 0.609 / epic 0.293
chest   common 0.352 / uncommon 0.395 / rare 0.226 / epic 0.028
```

T7 对 BOSS 主题池的 4,000 次同层抽取（act1 / act3 一致，无深度偏置）：

```text
act1 uncommon 0.110 / rare 0.582 / epic 0.309
act3 uncommon 0.098 / rare 0.596 / epic 0.306
```

## 复现

```text
run_smoke.bat
Godot_v4.7-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tests/loot_source_pool_test.tscn
```
