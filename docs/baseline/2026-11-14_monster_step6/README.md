# 全怪物机制 · Step 6 基线 · 对策有效性与无装备可通关（2026-11-14）

对应说明：`docs/Step6_对策有效性与无装备可通关_全怪物_2026-11-14.md`
对应计划：`docs/全怪物个性机制设计与制作计划_2026-11-12.md` Step 6 出口、§11 第 5 / 6 条

## 文件

| 文件 | 内容 |
|---|---|
| `counterplay.out.log` | 第 48 套 `counterplay_test` 原始输出（162 项，含 61 房逐房跑局明细） |

## 关键结果

| 项 | 结果 |
|---|---|
| 单套结论 | `COUNTER\|RESULT PASS (checks=162 fails=0)` |
| A 减益双通道（9 个减益） | 69 PASS / 0 FAIL |
| B 干扰意图（jam / lock / chaos / auto_stop） | 24 PASS / 0 FAIL |
| C 61 房裸 Build 全量通关 | 66 PASS / 0 FAIL，`won=61/61`，最慢 35 回合，无软锁 / 无超时 |
| D 代表房双 Build | 3 PASS / 0 FAIL（窃语咒师 3/3、腐化史莱姆 2/3、勇者的阴影 33/24 回合） |
| 分组耗时 | 减益 585ms / 干扰 875ms / 61 房 24874ms / 双 Build 4382ms |

## 口径

- 裸 Build = 腰带为空（无净化 / 清净药剂）、护符为空、`charm_interf_resist<=0`，只保留 2 把基础武器；带对策装备 Build 在其上加净化 + 清净 + 抗扰 + 守备。
- `GOD_HP=1000000` 只作用于测试实例，判定「是否因缺装备被软锁」，不代表无装备在真实血量下数值可行。
- 固定种子 `SEED=20261114`；单房预算 400 回合、单回合帧保护 900。
- 运行前备份 `lobby_data.json` 并在结束后恢复；`APPDATA` 重定向到临时目录，未读写真实存档。
- 日志尾部 Godot 退出期 `ObjectDB instances were leaked` / `resources still in use` 告警与 Step4–8 历史日志同类，`RESULT` 为 PASS。

## 复现

```text
run_smoke.bat
Godot_v4.7-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tests/counterplay_test.tscn
```

⚠️ 本基线只覆盖第 48 套单套实跑。会话期间 `run_smoke.bat` 被并行工作扩展为 49 套（新增第 49 套 `growth_loot_offer_test`），全量 49 套回归与真人 ACT1 / 多 Build 复测尚未执行，交回验证。
