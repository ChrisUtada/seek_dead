# Step 5 基线 · 接入普通 / 精英 / BOSS / 探索来源（2026-11-13）

对应说明：`docs/Step5_接入普通精英BOSS与探索来源_2026-11-13.md`
对应计划：`docs/四级品质战利品与大奖池_分步执行计划_2026-11-12.md` Step 5

## 文件

| 文件 | 内容 |
|---|---|
| `smoke.out.log` | `run_smoke.bat` 全量 44 套输出（`[smoke] RESULT: ALL GREEN`） |
| `loot_explore.log` | 第 44 套 `loot_explore_test` 原始输出（23 项） |
| `loot_pool.log` | 第 42 套 `loot_source_pool_test` 原始输出（84 项） |
| `loot_offer.log` | 第 43 套 `loot_offer_test` 原始输出（34 项） |

## 关键结果

| 项 | 结果 |
|---|---|
| 全量套件 | 44 / 44 ALL GREEN |
| 第 4 套全流程 | checks=2567, fails=0 |
| 第 42 套来源池 | checks=84, fails=0 |
| 第 43 套同层三选一 | checks=34, fails=0 |
| 第 44 套探索来源 | checks=23, fails=0 |

第 44 套覆盖：

- 90 武器 / 30 非信物护符 / 25 消耗品带 `chest` 标签；15 件 BOSS 信物与 40 技能不带；
- 3 类别 × 3 幕 × 300 次探索抽取：类别、幕次、品质、来源标签全部合法，信物泄漏 0；
- 探索武器 act1 10,000 次抽样 ≈ chest 表 35 / 40 / 22 / 3，且明显区别于普通战表；
- 专用 RNG 同种子可复现；60 张棋盘同种子重生成物品路径完全一致；
- 宝箱 / 武器格 / 护符格 / 武器藏库在生成时冻结，重生成前路径不变；
- 探索抽取不消耗全局 RNG；技能类别明确返回空；
- 商店 3 幕类别序列均为 6 格且与品质阶梯逐格对齐。

## 复现

```text
run_smoke.bat
Godot_v4.7-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tests/loot_explore_test.tscn
```
