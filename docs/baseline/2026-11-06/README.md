# G0-01 · 当前可交付基线（2026-11-06）

> 对应计划：`docs/统一制作执行计划_2026-11-06.md` §4 G0-01
> 目的：固定「当前源码 → 可测包 → 测试说明」三者一致，后续 G1 人工验收不再混用旧包或线性/棋盘数据。

---

## 1. 交付物

| 类型 | 位置 | 说明 |
|---|---|---|
| 导出包 | `build/ACT1_Demo_2026-11-06/Seek Dead ACT1 Demo.exe` | 2026-11-06 11:36 导出，128,199,424 B |
| 包信息 | `build/ACT1_Demo_2026-11-06/BUILD_INFO.txt` | 版本、内容数量、启动方式、已知问题 |
| 源码状态 | `build/ACT1_Demo_2026-11-06/source_state.txt` | HEAD + 完整 `git status` / `diff --stat` |
| 启动脚本 | `build/ACT1_Demo_2026-11-06/启动_线性模式.bat` / `启动_棋盘模式.bat` | 双击启动，避免传参错误 |
| 回归日志 | `docs/baseline/2026-11-06/run_smoke_2026-11-06.log` + `smoke_logs/` | 16 套完整日志 |
| 实机截图 | `docs/baseline/2026-11-06/01..08_*.png` | 960×540，窗口模式采集 |
| 多分辨率截图 | `docs/baseline/2026-11-06_ui/` | G0-02：480×270 / 960×540 / 1440×810 × 5 屏 |
| 数据 | `docs/baseline/2026-11-06/baseline_data.txt` | 资源数量、线性房间序列、棋盘拓扑、关键平衡值 |
| 采集工具 | `tools/g0_baseline_capture.gd` / `.tscn` | 可重复采集（不写资源文件） |

历史包已归档到 `build/archive/`（见该目录 `README.md`），不再用于当前功能验收。

---

## 2. 源码状态

- HEAD：`b004c7b`（master），工作区有 185 个未提交改动。
- 包内包含：M1 战后成长三槽、M2 ACT1 棋盘、棋盘开关、本轮立绘/UI 改动。
- 完整性核对：导出包内可检索到 `board_system` / `board_screen` / `post_battle_system` 脚本路径。
- 导出预设 `ACT1 Demo`：`custom_features = act1_demo`，`tests/` 与 `tools/` 排除，PCK 内嵌单文件。

---

## 3. 资源数量（基线事实）

| 项 | 数量 |
|---|---:|
| 房间 | 61（ACT1 20 / ACT2 21 / ACT3 20） |
| BOSS | 13 |
| 武器 | 90 |
| 护符 | 45 |
| 消耗品 | 25 |
| 技能 | 17 |
| **装备合计（武器+护符+消耗品+技能）** | **177 / 200** |

导出包按 demo 白名单收窄：14 武器 / 10 技能 / 27 道具 / ACT1 20 房；单局线性 8 房。

---

## 4. 启动与模式区分

| 模式 | 启动方式 | 判定 |
|---|---|---|
| 线性（默认） | 双击 exe / `启动_线性模式.bat` | HUD 显示「ACT I · 房 x/8」 |
| 棋盘 | `启动_棋盘模式.bat` 或 `exe -- --board` 或整备底栏「🗺 棋盘✓」 | HUD 显示「ACT I · 节点 x/12」，开局为棋盘 |

- `resources/config/board_config.tres` 的 `enabled` 保持 `false`；棋盘只能显式开启。
- 线性与棋盘共用同一存档；BOSS 在棋盘固定 `ria=7`，不要与线性基线混算。

---

## 5. 自动验证证据

- `run_smoke.bat`：**16/16 ALL GREEN**，`SMOKE|RESULT PASS (checks=3617 fails=0)`。
- 日志：`run_smoke_2026-11-06.log`；每套明细在 `smoke_logs/`（16 个）。
- 导出包 headless 启动验证：`--headless --board --quit-after 120` → exit 0。

---

## 6. 截图

| 文件 | 内容 |
|---|---|
| `01_loadout.png` | 整备页，底栏含「🗺 棋盘」开关 |
| `02_linear_battle.png` | 线性首房（房 1/8） |
| `03_post_battle_growth.png` | M1 战后成长三槽 |
| `04_board_start.png` | 棋盘起点，12 节点与分支 |
| `05_board_legal_targets.png` | 掷骰 1，合法落点高亮 |
| `06_board_after_move.png` | 走子后节点消耗 |
| `07_board_battle.png` | 从棋盘进入战斗（节点 2/12） |
| `08_board_shop.png` | 棋盘商店格 |

重采集：

```powershell
D:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe --path . res://tools/g0_baseline_capture.tscn
```

> 必须窗口模式，headless 无帧缓冲；采集会写存档，前后按 §7 备份/还原。

---

## 7. 存档纪律

```text
%APPDATA%\Godot\app_userdata\Seek Dead Prototype\lobby_data.json
```

- 跑测/采集前复制备份，结束后还原并核对 SHA-256。
- 换包、换模式都共用该文件；失败实验不得直接使用玩家存档。
- 本基线采集前后已还原到采集前状态。

---

## 8. 已知问题（移交 G1 / G3）

1. ~~战后成长三槽卡标题竖排~~：**G0-02 已修复**。`ItemCard` 的 VBox 增加最小宽 76、卡高 84→96；
   修复前后对比见 `03_post_battle_growth.png`（修复前）与 `2026-11-06_ui/960x540_04_post_battle.png`（修复后）。
2. **棋盘连线只在分支处可见**：相邻节点之间的 `Line2D` 被节点按钮覆盖，见 `04_board_start.png`。
   归属：G3 地图化时统一重排，不单独修。
3. ~~**棋盘缺乏走棋感**（人工反馈）：落点由骰子唯一确定、棋子直线滑行。~~
   **2026-11-06 棋盘改版已处理**：1D3 改为步数预算、逐格结算；21 节点 / 两段岔路 / 4 个 BOSS 结局。
   本目录截图仍对应改版前的 12 节点旧棋盘，仅作历史基线；新版见 `docs/baseline/2026-11-06_board/`。

---

## 9. 下一步

- G0-02 已完成：真实攻击/tooltip/三槽卡布局修复（旧包 SHA-256 `340844fe…`）。
- **2026-11-06 棋盘改版已完成**：步数预算、21 节点、四 BOSS 分路；新包 `build/ACT1_Demo_2026-11-06_board/`
  （SHA-256 `7b25f381…`），回归 16/16 ALL GREEN，证据 `docs/baseline/2026-11-06_board/`。
- G1-01/G1-02/G1-03/G1-04：改用棋盘改版包做真人验收，记录表见
  `docs/G1_人工验收_执行清单与记录表_2026-11-06.md`。
