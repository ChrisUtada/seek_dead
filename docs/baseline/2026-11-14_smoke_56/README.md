# 基线：全量 56 套回归（2026-11-14）

## 1. 用途

记录地图巡逻诱导 Step 0–4 与并行 loot/shop 重构入库后的**首次全量回归**结论，作为后续步骤（Step 5A 起）的对比基线。

不是单步证据：各步的定向证据分别在 `docs/baseline/2026-11-14_map_step*/`、`docs/baseline/2026-11-14_monster_step6/`、`docs/baseline/2026-11-14_loot_step8/`。

## 2. 结论

目录内有两份日志：先一份 55/56（含一条 loot 域既有偶发），修复后一份 56/56 全绿。**以此表为准。**

| 项 | 值 |
|---|---|
| 权威日志 | `smoke_after_flake_fix.out.log`（16:34） |
| 触发方式 | `run_smoke.bat`（无参数，用默认 Godot 路径） |
| 套件 | 1–56，编号连续、无缺号、无重复 |
| 结果 | **56 / 56 `ok`，0 `FAIL`** |
| 结尾 | `[smoke] RESULT: ALL GREEN` |
| 退出码 | 0 |
| 耗时 | **14 分 08 秒** |

### 关于先前那份 55/56

`smoke.out.log`（15:45，56/56 全绿）是 Step 0–4 入库后的首次全量。之后做 Step 5A 时又跑了一次（16:06，55/56），失败的是 `m1_reward_reach_test` 的「腰带满时卡片直接说明折算金币」。该失败当时重跑 3 次均通过，随后定位为**既有偶发**：消耗品资源没有 `epic` 层，`LootPool.roll()` 抽到 epic 就整次失败，奖励卡变空卡。

修复落在 `LootPool.roll()`：目标层为空时在「池里真实存在」的品质层之间按来源表权重改抽（与 `pick_explore_loot` 同口径），`forced_quality` 仍保持原样失败。修后 M1 连跑 15/15，`loot_balance` 86、`loot_offer` 37 未回归，全量 56/56。这次 55/56 的日志留在 `docs/baseline/2026-11-14_map_step5a/smoke_55of56.out.log` 作为定位凭据。

## 3. 覆盖范围（与本次提交对应的关键套件）

| 套 | 主题 | 归属 |
|---|---|---|
| 48 | Step 6 monster counterplay：两类有效对策 / 61 房裸 Build 通关 / 双 Build | 全怪物机制 |
| 49 | Growth loot：不发直接装备 / 重抽费用 / 免费跳过 / 探索与 BOSS 物品 | loot 重构 |
| 50 | Map grid Step 1：14×9 灰盒 / 预算 / 可达路线 / 固定种子 / validate 防护 | 地图 Step 1 |
| 51 | Map Step 0.5 多幕终局：配置驱动 final / ACT I–II 可续 / 无 ACT IV / 开发门闸 | 地图 Step 0.5 |
| 52 | Map Step 0.5 节点注册表与真实来源 / 冻结字段 / 不重复结算 | 地图 Step 0.5 |
| 53 | Map grid builder：61 节点 / 双向邻接 / 16 房间绑定 / 固定种子 | 地图适配层 |
| 54 | Map Step 2：相邻移动 / 等待一次 / 回访不重复结算 / 9×7 镜头 / 存档恢复 | 地图 Step 2 |
| 55 | Map Step 3：冻结巡逻环 / 预告与实际一致 / 占格与撞击 / 行动顺序 / BOSS 不被堵死 | 地图 Step 3 |
| 56 | Map Step 4：破甲陷阱触发一次 / 预告等于实战 / 不秒杀 / 玩家安全 | 地图 Step 4 |

其余 1–47 套为既有回归（意图门控、掉落、成长、专精、图鉴、三幕链、转轮手感、loot Step 1–8 等），本次全部保持通过。

## 4. 复现

```bat
cd /d D:\Games\yd\sd\seek_dead
run_smoke.bat
```

- `APPDATA` 会被脚本重定向到 `%TEMP%\seek_dead_smoke_appdata` 并在每次运行前清空，不会触碰真实 `lobby_data.json`。
- 每套的详细输出在 `%TEMP%\smoke_*.log`；本目录只保留 `run_smoke.bat` 的汇总输出。
- 单套复查可直接跑 `res://tests/<name>.tscn`，示例见各步 baseline 的 README。

## 5. 判读要点

- 只有 `[smoke] RESULT:` 行是权威结论；单套 `ok` 表示该进程退出码为 0。
- 若后续某套变红，先看 `%TEMP%\smoke_<key>.log` 的 `FAIL` 行与最后一次 `RESULT`。
- 地图线若误改：第 50 套管布局与预算、第 54 套管移动与存档、第 55 套管巡逻、第 56 套管陷阱；第 53 套是 14×9 → 节点图的适配层，改它有连带影响。
- 退出期 `ObjectDB instances were leaked` / `resources still in use` 属 Godot 告警，历史各版本一致，不影响 RESULT。
