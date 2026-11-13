# Step 6 基线 · 重复转化、成长队列与图鉴（2026-11-14）

对应说明：`docs/Step6_重复转化成长队列与图鉴_2026-11-14.md`
对应计划：`docs/四级品质战利品与大奖池_分步执行计划_2026-11-12.md` Step 6

## 文件

| 文件 | 内容 |
|---|---|
| `smoke.out.log` | `run_smoke.bat` 全量 45 套输出（`[smoke] RESULT`） |
| `loot_growth.log` | 第 45 套 `loot_growth_test` 原始输出（30 项） |
| `loot_offer.log` | 第 43 套 `loot_offer_test` 原始输出（34 项） |

## 关键结果

| 项 | 结果 |
|---|---|
| 全量套件 | 45 / 45 ALL GREEN |
| 第 4 套全流程 | checks=2567, fails=0 |
| 第 43 套同层三选一 | checks=34, fails=0 |
| 第 45 套重复转化 / 成长 | checks=30, fails=0 |

第 45 套覆盖：

- 已装备武器的重复候选冻结为 `mastery`，展示值 = 同品质配置值（epic +4）；
- 结算一次后熟练恰 +4，跨 R2 只欠一次铭印；重复结算返回 `already_settled`；
- 20 次重抽不改变熟练 / 欠铭印 / 待选技艺，重抽后结算仍按展示值；
- 同层强化 / 同层金币 / 跳过各只结算一次；
- 普通授予写入 `owned_weapons`，`item_sources` 带 `loot_source = normal`，图鉴文案含「普通战利品」；
- 重复护符 / 满腰带 → 同层金币；
- 满槽 `needs_replace` 失败不消耗结算机会，腾槽后可结算；
- `codex.record_run` 写入最高 R 等级与最高熟练点数。

## 复现

```text
run_smoke.bat
Godot_v4.7-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tests/loot_growth_test.tscn
```
