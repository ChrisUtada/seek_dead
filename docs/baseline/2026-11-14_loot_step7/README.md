# Step 7 基线 · 信息展示与交互收口（2026-11-14）

对应说明：`docs/Step7_信息展示与交互收口_2026-11-14.md`
对应计划：`docs/四级品质战利品与大奖池_分步执行计划_2026-11-12.md` Step 7

## 文件

| 文件 | 内容 |
|---|---|
| `smoke.out.log` | `run_smoke.bat` 全量 46 套输出（`[smoke] RESULT`） |
| `loot_ui.log` | 第 46 套 `loot_ui_test` 原始输出（107 项） |
| `loot_offer.log` | 第 43 套 `loot_offer_test` 原始输出（34 项） |

## 关键结果

| 项 | 结果 |
|---|---|
| 全量套件 | 46 / 46 ALL GREEN |
| 第 4 套全流程 | checks=2531, fails=0 |
| 第 43 套同层三选一 | checks=34, fails=0 |
| 第 46 套界面与交互 | checks=107, fails=0 |

第 46 套覆盖：

- 四级显示名 / 来源名 / 颜色统一（`LootSourceTable` + `Palette` 单一来源）；
- 480×270 下三张同层卡内容不越出卡片，跳过 / 重抽按钮在屏内；
- 三项品质相同，卡面与 tooltip 不出现「更高品质 / 推荐」诱导；
- 每项都有品质、机制、条件、结果文本，tooltip 含「条件：」「结果：」；
- 连续 6 次重抽：品质层、跳过金币、标题不变，候选确实换过；
- 点卡 / 重复点卡 / 重复结算只发一次；跳过两次不二次发奖；ESC 不结算；
- 满槽武器 → 替换弹层；取消不改配装；替换后再次结算返回 `already_settled`；
- 成长阶段单独展示、可保留；选择后技艺入列；
- 开屏 + 重抽 + 关屏后战利品 RNG 种子、房间表、棋盘节点全部不变；
- BOSS 武器候选带品质字段，卡面带【品质】角标。

## 复现

```text
run_smoke.bat
Godot_v4.7-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tests/loot_ui_test.tscn
```
