# 基线：全量 56 套回归（Step 6 界面收口后，2026-11-14）

## 1. 用途

按设计稿（1080×608 等比稿）把地图界面改成 14×9 整图后的全量基线。
上一版 55 套见 `docs/baseline/2026-11-14_smoke_55/`。

套数从 55 增到 56，是因为新增第 56 套 `board_ui_test`（界面契约，80 项）。

## 2. 结论

| 项 | 值 |
|---|---|
| 触发方式 | `run_smoke.bat` |
| 套件 | 1–56，编号连续、无缺号、无重复 |
| 结果 | **56 / 56 `ok`，0 `FAIL`** |
| 结尾 | `[smoke] RESULT: ALL GREEN` |
| 退出码 | 0 |
| 耗时 | **14 分 44 秒**（含修完两个结算 bug 后的重跑） |

## 3. 本版变化

| 项 | 变化 |
|---|---|
| `board_screen.gd` | 14×9 整图入屏（格 16.6px）、统一单字、A/B/C 区域标注、图例条、右侧「当前局面」、底部说明条；删除 1D3 死代码与 16px 图标层 |
| 计划 §4.1–4.3 | 按设计稿重写：整图入屏、右侧三段式、操作与文案 |
| 第 56 套 | 新增 `board_ui_test`（87 项）：区域不越界 / 面板不相交 / 按钮不重叠 / 文本块高度有效 / 单字覆盖全类型 / 真实结算文案 / 源码无废弃概念 / **点击→确认→进战斗链路** |
| `duel_controller.gd` | `_on_board_node_entered()` 的 match 补齐新类型名（battle / chest / event），与旧名共存 |
| `board_system.gd` | `advance_to()` 移动成功后同步 `current_id`（此前位置永远停在起点） |
| `run_smoke.bat` | 注册第 56 套，分母改 56 |

## 4. 判读要点

- 第 56 套「文本块高度有效」变红：说明某个 Label 又被 autowrap 压成 1px，
  检查 `_info_label()` 是否仍设置 `custom_minimum_size.y = 字号 × 1.5 × 行数`。
- 第 56 套「地图面板与右栏不重叠」变红：`INFO_RECT` 与 `MAP_PANEL` 的边界被改动，
  两者必须保持 4px 间隙（320 + 5 + 147 = 472 ≤ 480）。
- 第 56 套「源码不含废弃概念」变红：注释或文案里又写了扫雷 / 行动点 / 掷骰 / 巡猎 / 倒计时。
- 第 56 套 G 组（进入战斗链路）变红：先看 `DuelController._on_board_node_entered()` 的 match
  是否漏了新类型名，再看 `BoardSystem.advance_to()` 是否仍同步 `current_id`。这两处任一缺失，
  表现为「点进入战斗又被弹回地图」或「走一步后棋子不动」。
- 第 54 套镜头断言仍然存在：它测的是 `MapRuntime.camera_origin()` 运行时契约，
  与界面是否整图入屏无关，不要因为界面改了就去改第 54 套。
- 退出期 `ObjectDB leaked` / `resources still in use` 属 Godot 告警，历史一致。

## 5. 附

- `board_ui_480x270.png`：本次界面在 480×270 下的实际渲染（离屏 SubViewport 截取）。
