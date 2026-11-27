# W-01B poison_dagger 试点迁移 · 回报（2026-11-26）

> 提交：`979cb40 feat(combat): 试点迁移 poison_dagger 到伤害后概率触发 + W03 条件改为毒伤双牌`
> 结果：新测试 7/7 PASS（其中 3.3 先红后绿，两种红都跑过）；七个回归套件 checks/fails 与改前**逐项相同**；
> `run_smoke` ALL GREEN（`checks=1822 fails=0`）。W03 因规则改写触发率一度升到 37.4%，经裁决收紧后回到 20.4%。

## 1. 改动

| 文件 | 内容 |
|---|---|
| `resources/weapon_templates/poison_dagger.tres` | 增加毒牙 `venom_bite`（5 权重）作为 `sw1`，保留 `sw0`（poison 5.0）以便回滚；`status_migrated=true` / `status_family="poison"` / `status_chance=0.35`（**占位初值，待平衡验证**）/ `status_stacks=1`；`mechanism_summary` 改写 |
| `resources/patterns/w03_venom_burst.tres` | 删掉 `{"sym": poison.tres}`，改为毒伤条件（最终形态见 §4）；desc 同步 |
| `resources/patterns/sig_plague_reaper.tres` | 同上（`effect_params`/`priority`/`unlock`/`tier` 未动） |
| `tests/w01_status_migration_test.gd/.tscn/.uid` | 7 条断言 |
| `tests/p0_final_lethal_intercept_test.gd` | 6 条断言从「旧设计：poison_dagger 只有 status 格」改写为迁移后语义（见 §5） |
| `tests/pattern_matcher_test.gd` | S04 与 SIG_W03 夹具由 `[毒牙, 毒, 毒牙]` 改为 `[毒牙, 毒牙, 毒牙]`（§4 收紧后必需） |

未动：其它 89 把武器、其余 9 条状态牌谱、`combat_system.gd:169` status 分支、`poison.tres` 资源。

## 2. 新测试 7 条：红绿过程

最终状态：

```text
PASS  3.1 池过滤：poison 离池=true，venom_bite 在池=true
PASS  3.2 概率触发（chance=1.0）：中毒 1 层（期望 1）
PASS  3.3 每 SPIN 至多一次：三列→1 层，再判→1 层（期望 1/1；逐格结算=3，去掉集合第二次会再 +1）
PASS  3.4 chance=0.0：中毒 0 层（期望 0）
PASS  3.5 不外溢：fire_sword 的 burn 仍在池=true
PASS  3.6 W03 可达：三张毒伤=true，两张=false，含非毒武器=false，条件不含状态符号=true
PASS  3.7 P3 和解：三列毒牙触发 peaceful_win=true
W01MIG|RESULT PASS (checks=7 fails=0)
```

### 2.1 3.3 的两次红（都实跑过，代码已还原）

**红 A——按格结算、无去重**（临时把阶段函数改成逐格读 payline 并 `add_enemy_status(cells)`）：

```text
FAIL  3.3 每 SPIN 至多一次：三列→3 层，再判→6 层（期望 1/1；逐格结算=3，去掉集合第二次会再 +1）
FAIL  3.4 chance=0.0：中毒 3 层（期望 0）
W01MIG|RESULT FAIL (checks=7 fails=2)
```

**红 B——只去掉每 SPIN 去重集合**（`if _migrated_status_done.has(wid): continue` 注释掉）：

```text
FAIL  3.3 每 SPIN 至多一次：三列→1 层，再判→2 层（期望 1/1；逐格结算=3，去掉集合第二次会再 +1）
W01MIG|RESULT FAIL (checks=7 fails=1)
```

**绿**：还原后 7/7。

> 口径说明（如实）：现实现按 `acc["source_dmg"]` 的**键**（武器 id）迭代，同一把武器的 3 格天然只产生 1 个键，
> 所以「三列→+3」只会在逐格实现里出现（红 A）；`_migrated_status_done` 真正兜住的是「同一 SPIN 内第二次进入判定」（红 B）。
> 因此 3.3 写成两半：三列→+1（结构上限）+ 再判→仍 +1（去重集合），两半都有红证据。
> 代码已逐字节还原（`git diff` 对新提交的 `combat_system.gd` 为空）。

### 2.2 3.7 真的走到了 gimmick

`_start_room(勇者的阴影)` → `on_damaged` 推到 P3 → 三列毒牙 → `gimmick.on_turn_resolved(duel)`
→ `peaceful_win=true`。不是「池里有毒牙」这种间接断言。

## 3. 七个回归套件：改前 vs 改后

改前基线用 `git checkout-index -a -f --prefix=%TEMP%\sd_before_w01b/` 物化 HEAD（f098f27）到临时目录，
补拷 `.gitignore` 忽略的美术目录后独立 `--import` 实跑（不引用旧文档）。

| 套件 | 改前 | 改后 | checks |
|---|---|---|---|
| `pattern_matcher_test` | `PASS (checks=137 fails=0)` | `PASS (checks=137 fails=0)` | 不变 |
| `pattern_reachability_test` | `PASS (checks=38 fails=0)` | `PASS (checks=38 fails=0)` | 不变 |
| `t3b_symbol_category_test` | `PASS (checks=41 fails=0)` | `PASS (checks=41 fails=0)` | 不变 |
| `boss_rhythm_test` | `PASSED 174 / FAILED 0` | `PASSED 174 / FAILED 0` | 不变 |
| `p0_final_lethal_intercept_test` | `PASS (checks=34 fails=0)` | `PASS (checks=34 fails=0)` | 不变（6 条断言改写，见 §5） |
| `m4_demo_test` | `PASSED 43 / FAILED 0` | `PASSED 43 / FAILED 0` | 不变 |
| `p0b_boss_loot_theme_test`（`--script`） | `PASSED 270 / FAILED 0` | `PASSED 270 / FAILED 0` | 不变 |

`p0b` 没有 `.tscn`：`run_smoke.bat:34` 用 `--script` 运行，逐字照搬。

## 4. W03 频率冲突与收紧（需要单独说明）

按工单 2.1 原条件（毒伤牌×2＋任意毒武器）实测：

```text
[样板] 毒爆连携[中频高潮]：组成率中位 37.4%（37.4/40.1/41.0/36.3/36.6）｜每 2.7 回合一次（波动 2.4–2.8）
PATTERNSAMPLE|FAIL|毒爆连携：中频高潮每 2.7 回合一次（区间 3–5.5；波动 2.4–2.8）
```

设计定稿是「其余基础 W 维持中频 3–5.5 回合（20%–33%）」（`docs/_archive/2026-11/G0_任务追踪_2026-11-19.md:398`）。
经你裁决「收紧 W03 规则回 3–5.5」，最终条件改为**三张毒伤牌，且至少一张来自毒武器**：

```text
{"all": [
  {"kind": "damage", "source_element": "poison"},
  {"kind": "damage", "source_element": "poison"},
  {"kind": "damage", "source_element": "poison", "source_kind": "weapon"}
]}
```

收紧后实测：

```text
[样板] 毒爆连携[中频高潮]：组成率中位 20.4%（22.0/19.2/20.1/20.4/21.3）｜每 4.9 回合一次（波动 4.5–5.2）
PATTERNSAMPLE|RESULT PASS (checks=32 fails=0)
```

落回 20%–33% / 3–5.5 区间，且仍不含任何状态符号引用（`3.6` 断言覆盖）。
`desc` 同步改为「毒系伤害牌×3（至少一张来自毒武器）」。

## 5. 为通过验收而改的两处既有测试（逐条）

### 5.1 `p0_final_lethal_intercept_test.gd` 场景 8（6 条，checks 仍 34）

旧断言把「poison_dagger 只有 status 格、没有核心符号」当成前提；迁移后该前提不成立，6 条全红：

```text
FAIL|poison_dagger 建池：三条 strip 合计 status 格 >=3（实测 0）
FAIL|poison_dagger 建池：不含 damage/special/heal 核心符号格（实测 60）
FAIL|第 1/2/3 列 strip 含 poison(status) 格
FAIL|poison_dagger P3：建池三列 poison 真实 spin+结算后和解（无死局）
```

改写为同一意图下的新不变量：`status_cells == 0`、`venom_cells >= 3`、每列 strip 含毒牙格、
三列毒牙真实 spin+结算后 `peaceful_win=true`。断言条数不变（34），验证的仍是「P3 无死局」，只是符号从 poison 换成毒牙。

### 5.2 `pattern_matcher_test.gd` S04 / SIG_W03 夹具（checks 仍 137）

`[毒牙, 毒, 毒牙]` 里第二张是 status 卡，不再满足「毒伤牌×3」；改为 `[毒牙, 毒牙, 毒牙]`，其余期望（+2/+3 层、50%/60% 即时结算、不消耗层）不变。

## 6. 全量 smoke

```text
run1（工单原条件，2 条毒伤）：SMOKE|RESULT PASS (checks=1972 fails=0) → [smoke] RESULT: FAIL（pattern_sample）
run2（收紧后）：            SMOKE|RESULT PASS (checks=1822 fails=0) → [smoke] RESULT: ALL GREEN
```

run2 的套件结果（`%TEMP%\smoke_*.log`）：patternmatch 137/0、patternreach 38/0、patternsample 32/0、
bossrhythm 174/0、p0b 270/0；t3b 41/0、p0_final 34/0、m4_demo 43/0 由单独命令复跑（run_smoke 不含这三套）。
checks 总数随房内 RNG 波动，属既有抽样特性。

## 7. 提交

```text
979cb40 feat(combat): 试点迁移 poison_dagger 到伤害后概率触发 + W03 条件改为毒伤双牌
 resources/patterns/sig_plague_reaper.tres     |   4 +-
 resources/patterns/w03_venom_burst.tres       |   4 +-
 resources/weapon_templates/poison_dagger.tres |  16 +-
 tests/p0_final_lethal_intercept_test.gd       |  21 +--
 tests/pattern_matcher_test.gd                 |   5 +-
 tests/w01_status_migration_test.gd            | 204 ++++++++++++++
 tests/w01_status_migration_test.gd.uid        |   1 +
 tests/w01_status_migration_test.tscn          |   6 +
 8 files changed, 241 insertions(+), 20 deletions(-)
```

另有一笔只含注释的跟进提交：

```text
5593fa5 chore(combat): 标注 status_chance 试点值 0.35 为占位、待平衡验证
 scripts/equipment/weapon_data.gd | 2 +-
```

`git grep -c "status_migrated = true" -- resources/` → `poison_dagger.tres:1`（恰好 1）。

## 8. 与工单的偏差（逐条）

1. **W03/SIG_W03 条件从「毒伤牌×2＋任意毒武器」收紧为「毒伤牌×3（至少一张来自毒武器）」**：
   原条件实测 37.4% / 2.7 回合，越出设计 3–5.5 区间；按你的裁决收紧。`desc` 与提交说明同步。
2. **多改 2 个测试文件**（`p0_final_lethal_intercept_test.gd`、`pattern_matcher_test.gd`）：
   前者 6 条断言写死旧设计，不改则套件红；后者夹具依赖已删除的 status 条件。两处均保持 checks 数不变。
3. **多提交 1 个 `.gd.uid`**：Godot 自动生成，仓库 142 个同类文件全部入库。
4. `p0b_boss_loot_theme_test` 无 `.tscn`，按 `run_smoke.bat:34` 用 `--script` 运行。
5. `status_chance=0.35` 是**占位初值，待平衡验证**：字段注释已写在 `weapon_data.gd` 的 `status_chance` 声明行
   （单独提交 `5593fa5`，仅 1 行注释），本回报与资源 `mechanism_summary` 的 35% 同口径。
