# 战斗 UI 重构 · Step 2 战斗 HUD 结构整理（2026-10-31）

> 依据：`docs/战斗UI重构_执行方案与AI任务书.md` §6 Step 2
> 范围：外框、边距、栏宽、转轮格尺寸、SPIN 主操作样式；不改逻辑、不改节点路径、不改资源数据
> 截图：`docs/baseline/2026-10-31_ui/step2/`（同工具、同流程；与 `before/`、`after/` 可直接对照）

---

## 1. 任务书条目对照

| 任务书 Step 2 条目 | 处理 |
|---|---|
| ① 移除/隐藏常驻产品标题 | M3-01 已删除，本次确认无残留 |
| ② 移除 10px 厚外壳与装饰点，改细外框 | 厚壳已不存在；**新增** 1px 暖白外框 + 四角 2×2 铆钉（任务书 §5.2 要求） |
| ③ 保留顶栏 / 左栏 / 中央舞台 / 右栏 / ReelDock / SPIN 结构 | 未改结构，仅调尺寸 |
| ④ 调整 Margin、最小尺寸与间距，接近概念图比例 | Margin 6→5；内容纵向间距 1→2；主行间距 3→4；左右栏 76/84→88/88 |
| ⑤ 转轮居中，不改参考游戏布局 | 保持不变（`ReelCenter` 居中） |
| ⑥ 保留商店/下一房按钮的禁用与间歇逻辑 | 未触碰，回归覆盖 |
| ⑦ 同步更新受影响的 `$节点路径` | **无节点改名/移动，33 条路径全部有效** |

## 2. 改动清单

| 文件 | 改动 |
|---|---|
| `scenes/ui/battle_hud.tscn` | 新增 `Frame`（1px `#E2D7BD` 外框）+ `RivetTL/TR/BL/BR` 四角铆钉（`#A99D89` 2×2，`mouse_filter=IGNORE`）；`Margin` 6→5；`Content` sep 1→2；`MainRow` sep 3→4；`PlayerPanel` min 76→**88**；`EnemyPanel` min 84→**88**；`SpinButton` 104×24→**96×22**，新增金色主操作样式（2px `#D5A33D` 边框 + 金色文字，hover/pressed/disabled 三态） |
| `scripts/ui/battle_hud.gd` | 转轮格 `custom_minimum_size` 48→**42** |
| `scripts/ui/reel_spin_view.gd` | 滚动槽间距 `SPACING` 24→**21**（与 42px 格同步），注释同步 |
| `scripts/ui/type_scale.gd` | 仅注释（格子 42px） |

未改：节点层级/名称、`ReelSpinView` 结构、`symbol_cell.tscn`、任何战斗/成长/奖励代码。

## 3. 实测尺寸（Step 1 → Step 2）

| 项 | Step 1 | Step 2 | 说明 |
|---|---|---|---|
| 左栏宽 | 87 | **88** | 由 min 76 提升到 88，不再依赖内容撑开 |
| 右栏宽 | 84 | **88** | 与左栏等宽 |
| 中央舞台 | 291×234 | **286×235** | 左右各 +1~4px，换 Margin -1px 与纵向 +1px |
| 转轮格 | 48×48 | **42×42** | 向概念图 38 靠拢；16px 符号仍清晰 |
| SPIN | 104×24 中性 | **96×22 金色主操作** | 2px 金框 + 金字 |
| 外框 | 无 | **1px 暖白 + 四角铆钉** | `Frame` 全屏锚定，不拦截输入 |

## 4. 验收

- 480×270 下无重叠、裁切、非预期滚动：`step2/02_battle_960.png`、`03_boss_960.png` 目视通过；转轮滚动中（`08_spin_960.png`）符号仍纵向流动、角标/元素色不变。
- SPIN、转轮、右侧意图完整可见；BOSS 不遮挡转轮（128×128 立绘，舞台 286 宽）。
- 覆盖层（商店/奖励/铁砧/结算/整备）无位移或溢出：见 `step2/01,04,05,06,07`。
- 回归：见 §5。

## 5. 回归结果

`run_smoke.bat`：**13/13 ALL GREEN，exit 0**（Step 2 实跑）

| 套件 | 结果 |
|---|---|
| 1/13 L0 intent act-gating | PASSED 42 / FAILED 0 |
| 2/13 L0 boss loot theme | PASSED 234 / FAILED 0 |
| 3/13 L1 content math lint | PASSED 393 / FAILED 0 |
| 4/13 L2+L3 full-run smoke | PASS（checks=3863, fails=0） |
| 5/13 T8 drop channels | PASSED 20 / FAILED 0 |
| 6/13 T7 acquisition weighting | PASSED 10 / FAILED 0 |
| 7/13 curriculum | PASSED 99 / FAILED 0 |
| 8/13 charge gating | PASSED 8 / FAILED 0 |
| 9/13 M1 reward suite | PASSED 51 / FAILED 0 |
| 10/13 M2 growth | PASSED 51 / FAILED 0 |
| 11/13 M2 weapon mastery | PASSED 41 / FAILED 0 |
| 12/13 M3 binding | PASSED 12 / FAILED 0 |
| 13/13 M4 demo config | PASSED 48 / FAILED 0 |

合计 4872 条断言，0 失败，与 Step 0/1 逐套一致。
副作用同前：整局 smoke 改写 `anvil_points`（本次 6899 → 7210），已备份并还原为 6899。

## 6. 已知遗留

- 顶栏仍显示「本局加成」而非概念图的金币/回合重排——属 Step 5 信息层级。
- 右栏「下一意图」仍为单意图一行（引擎限制）。
- 转轮格 42 与概念图 38 仍有 4px 差；若继续缩会压缩 16px 图标留白，建议止步于此。
- 外框铆钉仅四角，未做上下边装饰。
