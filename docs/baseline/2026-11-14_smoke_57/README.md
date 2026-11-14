# 基线：全量 57 套回归（2026-11-14）

## 1. 用途

Step 5A / 5B 完成后的全量基线。用于后续 Step 6（UI 收口）与正式入口切换时的对比。

上一版 56 套基线见 `docs/baseline/2026-11-14_smoke_56/`。

## 2. 结论

| 项 | 值 |
|---|---|
| 触发方式 | `run_smoke.bat`（无参数，默认 Godot 路径） |
| 套件 | 1–57，编号连续、无缺号、无重复 |
| 结果 | **57 / 57 `ok`，0 `FAIL`** |
| 结尾 | `[smoke] RESULT: ALL GREEN` |
| 退出码 | 0 |
| 耗时 | **13 分 15 秒** |

## 3. 本版新增

| 套 | 主题 |
|---|---|
| 57 | Map Step 5B：battle / elite / boss 分流、三选一成长、队列保留、战败不发奖 |

第 56 套（Step 4 破甲陷阱）与 50–55 套（Step 1–3 与适配层）保持通过；第 48 / 49 套（对策有效性、成长三选一 loot）也在列。

## 4. 复现

```bat
cd /d D:\Games\yd\sd\seek_dead
run_smoke.bat
```

- `APPDATA` 由脚本重定向到 `%TEMP%\seek_dead_smoke_appdata` 并在每次运行前清空，不触碰真实 `lobby_data.json`。
- 单套详细输出在 `%TEMP%\smoke_*.log`。

## 5. 判读要点

- 只有 `[smoke] RESULT:` 行是权威结论。
- 地图线误改的定位顺序：50 布局与预算 → 53 适配层 → 54 移动与存档 → 55 巡逻 → 56 陷阱 → 57 战斗奖励分流。
- 若 54 套「恢复后状态指纹一致」变红：`MapRuntime.to_dict/from_dict` 新增了 `battles`，检查恢复是否覆盖该字段。
- 退出期 `ObjectDB instances were leaked` / `resources still in use` 属 Godot 告警，历史一致，不影响 RESULT。
