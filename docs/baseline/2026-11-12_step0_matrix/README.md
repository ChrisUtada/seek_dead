# Step 0 基线快照（2026-11-12）

> 对应：`docs/全怪物个性机制设计与制作计划_2026-11-12.md` §10 Step 0
> 冻结提交：`9aa15e5`（master，拉取最新后快进）
> 四元组表：`docs/全怪物机制四元组表_Step0_2026-11-12.md`
> 真人复核清单：`docs/Step0_第7房精英战后路径_真人复核清单_2026-11-12.md`

---

## 1. 冻结值

| 项 | 值 | 位置 |
|---|---|---|
| 克制元素三连核爆 | **12.5% max HP** | `BalanceConfig.counter_burst_pct = 0.125` |
| 治疗 1/2/3 连倍率 | **1.0 / 2.5 / 4.5**（三连 base10 → 45） | `BalanceConfig.heal_line_mults` |
| 三连溢出转盾上限 | 20% maxHP | `BalanceConfig.heal_overflow_shield_cap_pct = 0.2` |
| 怪物规模 | 61 = 36 普通 + 12 精英 + 13 BOSS | `resources/rooms/*.tres` |

---

## 2. 全量回归

命令（隔离存档，真实 `lobby_data.json` 不被读写）：

```text
run_smoke.bat
→ %TEMP%\seek_dead_smoke_appdata（每次清空）
```

### 2.1 拉取最新后的首次基线

- 日志：`smoke_2026-11-12.out.log`
- 结果：**30 / 34 通过**，4 套失败：
  - `[12] M3 entity / symbol art binding`：3 / 12 失败
  - `[14] P1 reel readability`：2 / 51 失败
  - `[32] Reel absorb Step 2`：1 / 20 失败
  - `[33] Reel pacing Step 3`：3 / 26 失败

### 2.2 失败归因

| 套件 | 失败断言 | 归因 | 处理 |
|---|---|---|---|
| M3 binding | 转轮格 label/图标断言 | `f47c919` 起文字/图标改由 `_sync_cell_occlusion` 帧内应用、图标走独立 `TextureRect` 覆盖层；武器行无 `icon_tex` 时回落元素小图标 | **测试断言跟随实现**（m3_binding_test） |
| P1 readability | `1/12`、`1/11`、`0.0014` | `9aa15e5` 速度曲线按 19/30 缩放：5.7 / 7.6 CPS、accel 0.0038 | **测试改读 `ReadabilitySystem` 常量** |
| Reel absorb | 「停轮吸附不消耗全局 RNG」 | `f47c919` 停列爆裂 `CPUParticles2D` 未设固定种子，每次停列从全局 RNG 取 1 次 → 平移种子局随机流 | **玩法代码修复**：粒子 `use_fixed_seed = true`；测试隔离 finish_spin 结算 |
| Reel pacing | 8–10 / 10–12 格每秒、启动段接近巡航 | 同 `9aa15e5`，旧阈值硬编码 | **测试改读常量并调整启动段阈值** |

> 结论：3 套为断言漂移；1 套（reel absorb）是真实的「表现层消耗全局 RNG」缺陷，已在 `battle_hud.gd` 修复。均不涉及战斗数值。

### 2.3 修复后复跑

- 日志：`smoke_2026-11-12_after_fix.out.log`
- 结果：**34 / 34 ALL GREEN**（`[smoke] RESULT: ALL GREEN`，退出码 0）
- 固定种子局的确定性从此不再受停列爆裂粒子影响；4 套失败全部关闭，无新增失败。

---

## 3. 怪物清单与机制快照

| 文件 | 内容 |
|---|---|
| `monsters_snapshot.md` | 61 行怪物清单（有效 HP/ATK/甲、行为族意图、机制摘要） |
| `monsters_snapshot.csv` | 同上，机器可读 |
| `monsters_snapshot.json` | 全字段 + 房间/行为族/机制脚本 SHA-1（冻结指纹） |

生成器：`tools/monster_snapshot.py`（只读；任何房间/机制改动后重跑即可对比指纹）。

计数：

| 类型 | 数量 |
|---|---:|
| 普通 | 36 |
| 精英 | 12 |
| BOSS | 13 |
| **合计** | **61** |

---

## 4. 四元组与状态

见 `docs/全怪物机制四元组表_Step0_2026-11-12.md`：

- 61 项全部有触发 / 效果 / 持续·结束 / 应对 / 状态；
- 状态：现有 21、改造 3、替换 5、新增 32；
- 四元组同类冲突 D1–D5 已裁决；D6（呓语教徒 ↔ 迷宫低语者 P1）于 Step 5 以「首次锁轮第 2 回合 vs 第 3 回合」分化，D1–D6 全部落地。

---

## 5. 第 7 房精英战后路径（真人复核）

- 状态：**已完成（2026-11-12 用户决定标记完成）**。后续不设逐项真人复核门禁，以用户自由试玩与随时反馈为准。
- 清单与记录表：`docs/Step0_第7房精英战后路径_真人复核清单_2026-11-12.md`（保留作 FAIL 时的复现/取证模板）。

---

## 6. 复现

```text
# 全量回归（PowerShell，隔离存档）
powershell -NoProfile -Command "Start-Process cmd.exe -ArgumentList '/c','\"D:\Games\yd\sd\seek_dead\run_smoke.bat\"' -Wait -PassThru"

# 快照
python -I tools/monster_snapshot.py
```

---

## 复跑结果（2026-11-12 修复后）

- 套件数：**34**
- 通过：**34**，失败：**0**
- 结束标记：`[smoke] RESULT: ALL GREEN`，进程退出码 `0`
- 关键套件：
  - `[4] L2+L3 full-run smoke` → `PASS (checks=3899 fails=0)`
  - `[12] M3 entity / symbol art binding` → ok（断言已跟随 `_sync_cell_occlusion` + 图标覆盖层）
  - `[14] P1 reel readability` → ok（改读 `ReadabilitySystem` 常量）
  - `[32] Reel absorb Step 2` → ok（粒子固定种子 + 用例隔离 finish_spin 结算）
  - `[33] Reel pacing Step 3` → ok（巡航/封顶跟随常量）

Step 0 冻结基线成立：后续任何机制改动的回归对比都以本轮 34/34 为准。
Step 1（2026-11-12）新增共用触发/debuff 模块与第 35 套测试，全量回归升为 35 套；
最新一轮 35/35 见 `smoke_2026-11-12_step1.out.log`，模块说明见 `docs/Step1_共用触发与减益模块_2026-11-12.md`。
Step 2（2026-11-12）完成 ACT1 12 只普通怪特性接入，35/35 见 `smoke_2026-11-12_step2.out.log`，
说明见 `docs/Step2_ACT1普通怪接入_2026-11-12.md`。
Step 3（2026-11-12）完成 ACT2/ACT3 各 12 只普通怪接入（36 只普通怪全特性覆盖），35/35 见
`smoke_2026-11-12_step3.out.log`（第 4 套 `SMOKE|RESULT PASS (checks=3527 fails=0)`），
说明见 `docs/Step3_ACT2ACT3普通怪接入_2026-11-12.md`。期间修复 rtl 缠绕下空格停列软锁。
Step 4（2026-11-12）完成 12 只精英的压力—恢复节奏与 D1–D4 分化，新增第 36 套
`elite_combo_test`（134 检查）；全量 36/36 见 `smoke_2026-11-12_step4.out.log`
（第 4 套 `SMOKE|RESULT PASS (checks=3377 fails=0)`，末行 `[smoke] RESULT: ALL GREEN`），
说明见 `docs/Step4_精英组合补强_2026-11-12.md`。
Step 5（2026-11-12）完成 13 只 BOSS 的节奏补强与 D6 分化，新增第 37 套
`boss_rhythm_test`（171 检查）；全量 37/37 见 `smoke_2026-11-12_step5.out.log`
（第 4 套 `SMOKE|RESULT PASS (checks=3317 fails=0)`，末行 `[smoke] RESULT: ALL GREEN`），
说明见 `docs/Step5_BOSS节奏补强_2026-11-12.md`。
