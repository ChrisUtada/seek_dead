# 战斗 UI 重构 · Step 1 统一色板与基础主题（2026-10-31）

> 依据：`docs/战斗UI重构_执行方案与AI任务书.md` §6 Step 1
> 范围：只换颜色与 StyleBox，不改布局、不改节点路径、不改任何战斗/成长/奖励逻辑
> 截图对照：`before/`（改造前）↔ `after/`（改造后），同一采集工具、同一流程

---

## 1. 改动文件

| 文件 | 改动 |
|---|---|
| `scripts/ui/palette.gd` | 按任务书 §5.1 重写色板；`BORDER_WIDTH` 2 → 1；新增 `FRAME_MAIN` / `DEEP_LINE` / `ENEMY_DARK` 语义常量 |
| `theme/battle_theme.tres` | PanelContainer 面板：2px → 1px、底色改实色 `#1D1219`、内容边距 8 → 4；Tooltip 同步；新增 Label 默认字色 `#E2D7BD`、RichTextLabel 默认色 |
| `scenes/ui/ui_button.tscn` | normal / hover / pressed / disabled 四态换色；禁用态同时压暗边框与文字 |
| `scenes/ui/symbol_cell.tscn` | 转轮格 2px → 1px、底色 `#1D1219`、角标金改为 `#D5A33D` |
| `scenes/ui/battle_hud.tscn` | `Bg` → `#160D13`；`sb_panel_compact` 2px 蓝灰 `#38384D` → 1px 暖 `#A99D89`；12 处文字颜色覆盖统一到色板 |

未改：`scenes/ui/ui_panel.tscn`（本身无局部样式，完全走 Theme）、任何 `.gd` 逻辑、任何 `.tres` 资源数据、任何节点树/路径。

## 2. 色板前后对照（渲染色）

| 语义 | 改造前 | 改造后 |
|---|---|---|
| 主背景 `BG_MAIN` | `#1F171F` | `#160D13` |
| 面板/格子底 `PANEL_BG` / `CELL_BG` | `#251B23`（85% 叠色）/ `#332933` | `#1D1219`（实色） |
| 次线框 `PANEL_BORDER` | `#C7B89E` | `#A99D89` |
| 主文字/主线框 `TITLE` / `FRAME_MAIN` | `#E5D9B3` | `#E2D7BD` |
| 玩家灰白 `PLAYER` | `#E0DED6` | `#B9B8B0` |
| 敌人红 `ENEMY` | `#F28C8C` | `#E35B50` |
| 次级文字 `MUTED` | `#B3B3BF` | `#A99D89` |
| 弱信息 `MUTED_DIM` | `#A6A6BF` | `#6E5F57` |
| 交互金 `ACCENT_GOLD` | `#FFD94D` | `#D5A33D` |
| 护盾/护甲 `ARMOR` | `#BFCCE6` | `#62A1C2` |
| 治疗飘字 `POP_HEAL` | `#80F299` | `#A4BC4D` |
| 伤害飘字 `POP_DAMAGE` | `#FF8066` | `#E35B50` |
| 护盾飘字 `POP_SHIELD` | `#8CB3F2` | `#62A1C2` |
| 金币飘字 `POP_GOLD` | `#FFCC26` | `#D5A33D` |
| 普通线框宽度 `BORDER_WIDTH` | 2px | 1px（选中/SPIN/危险仍 2–3px） |

## 3. 保留的语义例外（本步不动）

| 颜色 | 原因 |
|---|---|
| `POP_STATUS` 橙 / `POP_BUFF` 紫 / `RARITY_EPIC` 紫 | 新色板未定义，直接复用红/金会丢失「状态 vs 伤害」「增益 vs 治疗」区分；Step 5 再评估 |
| `RARITY_COMMON/UNCOMMON/RARE` | 稀有度轴，已对齐灰/绿/蓝 |
| 元素色（`ElementCounter.color`） | 火/冰/毒/光/暗是玩法语义，禁止统一 |
| `BG_LOADOUT` / `BG_REWARD` / `BG_ANVIL` | 非战斗界面底色，属 Step 5「全界面统一」范围 |
| 冻结/干扰/锁轮列的 3px 彩色边框 | 状态提示，不参与换肤 |

## 4. 实机效果（before ↔ after）

对照图（同流程、同 BOSS）：

- `before/02_battle_960.png` → `after/02_battle_960.png`：底更暗（`#1F171F`→`#160D13`），左右栏与转轮格由 2px 蓝灰线改为 1px 暖线，文字整体转暖白。
- `before/03_boss_960.png` → `after/03_boss_960.png`：BOSS 立绘与舞台尺寸不变（128×128 / 291×234）。
- `before/04_shop_960.png` → `after/04_shop_960.png`：覆盖层面板同样变薄变暖，无位移、无溢出。
- `before/01_loadout_960.png` → `after/01_loadout_960.png`：装备卡由绿底改为「深底 + 绿线」，选中态不再整块发绿。

**布局零变化**（两侧 `capture_data.txt` 逐项一致）：左栏 87 / 右栏 84 / 转轮格 48 / 舞台 291×234 / 玩家 96×96 / BOSS 128×128。

## 5. 回归结果

`run_smoke.bat`：**13/13 ALL GREEN，exit 0**（换肤后实跑，2026-10-31 17:05–17:11）

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

与 Step 0 基线逐套断言数完全一致（合计 4872，0 失败）。
同前次副作用：整局 smoke 把 `anvil_points` 6899 → 7001，已备份并还原。

## 6. 已知遗留

- ~~SPIN 按钮仍是中性色~~ → **Step 2 已改为金色主操作**（2px `#D5A33D` 边框 + 金字）。
- ~~一级外框未添加~~ → **Step 2 已加** 1px 暖白外框 + 四角铆钉。
- ~~转轮格 48px、左右栏 min 76~~ → **Step 2 已调** 转轮格 42、左右栏 88。
- 状态/增益飘字、epic 稀有度仍为旧紫橙（Step 5 再评估）。
