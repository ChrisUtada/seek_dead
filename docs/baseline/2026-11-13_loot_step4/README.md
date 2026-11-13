# Step 4 基线 · 同层三选一与冻结 payload（2026-11-13）

对应说明：`docs/Step4_同层三选一与冻结payload_2026-11-13.md`
对应计划：`docs/四级品质战利品与大奖池_分步执行计划_2026-11-12.md` Step 4

## 文件

| 文件 | 内容 |
|---|---|
| `smoke.out.log` | `run_smoke.bat` 全量 43 套输出（`[smoke] RESULT: ALL GREEN`） |
| `loot_offer.log` | 第 43 套 `loot_offer_test` 原始输出（34 项） |

## 关键结果

| 项 | 结果 |
|---|---|
| 全量套件 | 43 / 43 ALL GREEN |
| 第 4 套全流程 | checks=2567, fails=0 |
| 第 43 套同层三选一 | checks=34, fails=0 |

第 43 套覆盖：

- normal / elite / boss × act1–3 共 360 组：每组恰好 3 项、同品质、路径不重复、至少两种用途；
- 短层（BOSS 主题仅 1 件 epic）：1 件物品 + 2 项同层转化（金币 / 伤害）；
- 重复装备、腰带满、护符槽触顶：全部展示为同层金币转化；
- 空主题池：3 项同层转化；
- 重抽 30 次：品质层与跳过收益不变，候选可换；
- 图鉴已解锁但本局未装备：仍为物品候选；
- 武器槽满：新武器候选冻结 `needs_replace`；
- 200 次生成不消耗全局 RNG。

## 复现

```text
run_smoke.bat
Godot_v4.7-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tests/loot_offer_test.tscn
```
