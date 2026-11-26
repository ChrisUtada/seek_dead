# C 轮基线收口 + D 轮跳过 · 回报（2026-11-26）

> 性质：纯文档收口（`docs/` 三份 md，零代码改动）。
> 提交：`72ba975 docs: C 轮统一组合面板收口，D 轮按用户决定跳过`
> 验收：三条 grep 达标；`loot_ui_test` PASS；`run_smoke` ALL GREEN；提交只含 3 个 md，工作区干净。

## 1. 基线改动（`docs/Seek_Dead_统一设计基线与总体进度_2026-11-22.md`）

| 位置 | 改动 |
|---|---|
| L4 最近更新 | 改为 2026-11-26：C 轮收口（战斗内第三格预览、不遮挡转轮）+ D 轮按用户决定跳过 + loot_ui 门禁加固 |
| L257 | 「未做：第三格只读组合预览」→「已完成」，写明战斗内入口、左侧抽屉、间歇期不再提供，并链接两份 T3-3C 文档 |
| L363 | C 轮描述改为战斗内第三格预览，追加 `is_battle_combo_window()` 单点判定 / `hud.set_reel_enabled` 单点驱动的说明；原「D 轮真人试玩未开始」同步改为「按用户决定跳过（后续另行提交）」 |
| L364 表现与操作 | 第三格预览改为「在战斗内给出（前两列已停后可开）…打开面板不遮挡转轮」 |
| L391 执行序列 | `D 专项/真人` → `D 专项/真人【已跳过】` |
| L392 注 | C 轮完成口径更新（`T3CPANEL 13/0`、`T3CSRC 21/0`、`T3CPREVIEW 43/0`、`T3CWIRE 28/0`）；D 轮跳过、真人验收后续另行提交、E 即本文件收口记录 |
| L394 T3-4 | 前置说明改为「核心按工程验收已通过，真人验收挂起」 |
| L367 item 4 | 「依赖统一组合核心通过」→「…通过（工程口径；真人验收挂起）」 |

未改：§9 间歇问题表、§3.3 run_smoke 步数（仍 55）、任何 `.gd/.tscn/.tres`。

**一处超出清单的一致性修正（如实报告）**：L363 原文含「D 轮真人试玩未开始」，与第 5/6 条「已跳过」
互相矛盾，同步改为「D 轮专项/真人验收按用户决定跳过（真人验收后续另行提交）」。其余均按工作单逐条执行。

**渲染处理**：L364 新增句「打开面板不遮挡转轮」并入同一列表项（未硬换行），避免在 Markdown 列表中断行。

## 2. 验证证据

### 2.1 三条 grep

```text
--- grep1: 未做：第三格只读组合预览 ---
(无输出，exit=1 → 0 处)

--- grep2: 已跳过 ---
docs/Seek_Dead_…_2026-11-22.md:393:→ P2／T3-3 统一组合核心（A 映射评审 → B 原型结算 → C 统一面板 → D 专项/真人【已跳过】→ E 回评审）

--- grep3: 真人验收挂起 ---
docs/Seek_Dead_…_2026-11-22.md:369:4. ⬜ **熟练组合变体试点（P2；依赖统一组合核心通过（工程口径；真人验收挂起））**：…
docs/Seek_Dead_…_2026-11-22.md:396:→ P2／T3-4 熟练组合变体（铁剑：爆燃／余烬；核心按工程验收已通过，真人验收挂起）
```

行号较工作单后移 2 行，因 L257 替换为 3 行。

### 2.2 loot_ui

```text
PASS  满槽（2/2）时武器卡必须标 needs_replace
PASS  空槽（1/2）时武器卡不得标 needs_replace
LOOTUI|RESULT PASS (checks=94 fails=0)
```

### 2.3 全量 smoke（首跑命中已登记抽样 flake，复跑全绿）

首跑：

```text
PATTERNSAMPLE|FAIL|… 组合高潮组成率中位 14.9% 落在 15%~10%（区间 15~? 回合/次；13.9%/15.8%/14.9%）
PATTERNSAMPLE|RESULT FAIL (checks=31 fails=1)
[smoke] RESULT: FAIL
```

该 flake 已登记在基线 §9（模式样本抽样边界，非回归），判定口径为「单跑 3 次全绿即视为抽样边界」。
单跑 3 次：

```text
run1: PATTERNSAMPLE|RESULT PASS (checks=31 fails=0)
run2: PATTERNSAMPLE|RESULT PASS (checks=31 fails=0)
run3: PATTERNSAMPLE|RESULT PASS (checks=31 fails=0)
```

全量复跑：

```text
SMOKE|RESULT PASS (checks=1870 fails=0)
[smoke] RESULT: ALL GREEN
```

（smoke 的 checks 总数随房间 RNG 在 1866–2084 间波动，属既有抽样特性。）

## 3. 提交

```text
72ba975 docs: C 轮统一组合面板收口，D 轮按用户决定跳过
 ...统一设计基线与总体进度_2026-11-22.md |  18 +--
 docs/loot_ui_needs_replace确定性覆盖_回报_2026-11-26.md | 113 +++++
 docs/loot_ui_满槽覆盖_回报_2026-11-26.md | 141 +++++
 3 files changed, 264 insertions(+), 8 deletions(-)
```

提交后 `git status --short` 无输出（工作区干净）。未 push、未 checkout/reset/stash。

## 4. 本回报

按"后续回报单独生成 MD 文档"的约定，本文件随任务追加一个 docs 提交入库。
