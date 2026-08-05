# Seek Dead · 老虎机对决 UI 最佳实践改造方案

> 文档版本：2026-07-31 · 基于真实仓库（基础版本 + 本会话 gameplay 功能）
> 目的：在不破坏现有可玩逻辑的前提下，把"全代码硬编码 UI"逐步改造为符合 Godot 4 最佳实践的、可维护、可扩展、可访问的 UI。
> 范围：仅老虎机对决链路（`duel_controller.gd` + 其构建的整备/奖励/铁砧/结算界面）。俯视角 RPG 残留文件不在本次范围。

---

## 一、现状盘点（基于真实仓库）

| 项 | 现状 | 依据 |
|---|---|---|
| 主入口 | `project.godot` 的 `run/main_scene` = `res://scenes/duel/duel.tscn` | 已改 |
| 唯一 UI 构建者 | `scripts/battle/duel_controller.gd`（**1793 行**） | 全部界面在此文件内 `new()` |
| 主题方式 | **77 处** `add_theme_*_override` 内联，无 `Theme` 资源 | `grep -c` 实测 |
| 屏幕脚手架 | 背景 `ColorRect` + `MarginContainer` + 根 `VBox` 样板重复 **4 套** | `_build_ui` / `_build_loadout` / `_build_reward` / `_build_anvil` 各写一遍 |
| 场景化 | 无 UI `.tscn`，仅 `duel.tscn` 挂脚本；整备/奖励/铁砧/overlay 全代码生成 | 场景树扫描 |
| 字体 | 无字体资源，依赖默认字体；字号靠逐控件 `add_theme_font_size_override` | `_label()` / 各处 |
| 调色板 | 颜色字面量散落（如标题 `Color(0.90,0.85,0.70,1)`、面板底 `Color(0.11,0.11,0.16,0.75)` 重复定义） | 多处 |
| 响应式 | 容器拉伸为主，但关键尺寸硬编码像素（`84×84` 格子、`130/170` 面板宽） | `_build_ui` |
| 可访问性 | 仅 SPIN 提示"空格"；日志/图例字号 10px；无焦点管理、无 tooltip | `_build_ui` / `_refresh_legend` |
| 表现性能 | `_refresh_legend` 每次 `remove_child`+重建；`_popup` 每次 `new Label+tween` 无对象池 | 对应函数 |

**核心矛盾一句话**：UI 的"结构、样式、内容、交互"与战斗逻辑全部耦合在 1793 行单文件里，且样式 100% 硬编码，导致**改一处配色要动几十处、加一个界面要复制整套样板、编辑器无法可视化调布局**。

---

## 二、问题诊断（按严重度）

### P0 — 维护性 / 可扩展性（必须解决，否则越改越乱）
1. **巨型控制器** `duel_controller.gd` 集战斗状态机 + 4 套界面构建 + 表现刷新于一身。新功能只能往里塞，认知负担与回归风险随行数线性上升。
2. **77 处内联主题覆盖、无统一 Theme**。任何全局视觉调整（主色、圆角、字号）需逐处搜索替换，极易遗漏且无法保证一致。
3. **4 套屏幕脚手架复制粘贴**（背景+margin+根容器，约 12 行 ×4）。DRY 严重违反；任一处布局微调都要同步 4 次。

### P1 — 视觉一致性 / 响应式
4. **魔法颜色与尺寸散落**：标题色、面板底、边框色在 `_make_side_panel` 与 legend 等各处重复 new `StyleBoxFlat` 设相同属性。
5. **无字体资源 / 字号阶梯混乱**：`10/11/12/13/14/17/18/30` 多种字号无体系，正文偏小（日志 10px）。
6. **固定像素 + 无安全区 / 断点**：小窗口下 `84×84` 格子与固定宽面板会挤压中间转轮；未处理不同分辨率/纵横比。
7. **角标与飘字硬编码定位**：角标用 `offset_right=-4; offset_top=2` 锚右上（修过但依赖写死偏移）；飘字用 `get_global_rect()` 算绝对坐标再减父 rect，脆弱且依赖 `add_child` 到 self。

### P2 — 体验 / 性能 / 可访问性
8. **日志/图例 10px 偏小**，长文本可读性、对比度存疑。
9. **键盘可访问性不足**：仅 SPIN 有"空格"提示，其余按钮无快捷键、无焦点顺序管理。
10. **无 tooltip**：转轮符号仅靠底部静态图例解释，hover 无即时说明。
11. **表现层无对象池**：`_refresh_legend` 每次重建子节点、`_popup` 每次 new 节点+tween，频繁刷新有瞬时开销与潜在泄漏。
12. **硬编码中文文案**：无 i18n 抽象（当前可接受，作为后续扩展点提一句）。

---

## 三、最佳实践改造建议（逐条，含落地）

### 建议 1 — 引入 `Theme` 资源（最高杠杆）
**原则**：Godot 的 `Theme` 资源是"一套样式管全局"的正确机制；`add_theme_*_override` 只应做例外覆盖。
**反模式**：77 处内联覆盖。
**方案**：
- 新建 `theme/battle_theme.tres`，在其中定义 `Label` / `Button` / `PanelContainer` 的 `default_font_sizes`、`colors`（font_color）、`styles`（Panel/Button 的 `StyleBoxFlat`）。
- 在 `duel.tscn` 根节点 `theme = battle_theme.tres`，或 `project.godot` 的 `[gui]` 段设 `theme = res://theme/battle_theme.tres`，让所有子控件自动继承。
- 代码里只保留"数据驱动的差异"（如元素高亮色），其余一律删掉 override，交给 Theme。
**落地位置**：新增资源 + `duel_controller.gd` 删减 60+ 处 override。

### 建议 2 — 建立调色板与字号常量（Palette + TypeScale）
**原则**：颜色/字号集中管理，避免魔法字面量。
**方案**：
- 新建 `scripts/ui/palette.gd`（`const` 颜色：`BG`、`PANEL_BG`、`PANEL_BORDER`、`TITLE`、`PLAYER`、`ENEMY`、`ACCENT_GOLD`、`ELEMENT_*`）。
- 新建 `scripts/ui/type_scale.gd`：`TITLE=18, SUBTITLE=14, BODY=13, SMALL=11, CELL=30` 等阶梯常量。
- 所有 `_label(text, size)` 的 `size` 改为引用 `TypeScale.*`；所有 `Color(...)` 改为 `Palette.*`。
**落地位置**：`duel_controller.gd` + 各构建函数。

### 建议 3 — 提取可复用 UI 组件场景
**原则**：Godot 最佳实践是用 `.tscn` 做组件，而非代码 `new()` 控件。
**方案**（优先级排序）：
- `scenes/ui/ui_button.tscn`：封装默认 `StyleBoxFlat`（普通/悬停/按下/禁用）、统一最小尺寸、字号取自 Theme。所有按钮改 `preload`+`instance()` 后设 `text`/`connect`。
- `scenes/ui/ui_panel.tscn`：封装 `_make_side_panel` 的 `StyleBoxFlat` 外观，暴露 `min_width` 与内部 `VBox`。
- `scenes/ui/symbol_cell.tscn`：封装转轮格子 + 角标 `Label`（右上锚定用 `Layout` 百分比而非写死 offset），暴露 `symbol_id` / `match_count` 属性。
**落地位置**：替代 `_make_side_panel`、`_build_ui` 中格子循环、`_refresh_cell` 的 StyleBox new。

### 建议 4 — 关注点分离：UI 独立成子场景 / 子控制器
**原则**：战斗逻辑（状态机、结算）与表现（节点树、刷新）分离。
**方案**：
- 将 `_build_ui` + `_refresh_*` + `_popup` + `_update_match_badges` + `_refresh_legend` 抽到 `scripts/ui/battle_hud.gd`（作为一个挂到 `duel.tscn` 的子节点 `BattleHud`），通过 `set_*` 方法 / 信号与 `duel_controller` 通信。
- `duel_controller` 只负责"算"，`BattleHud` 负责"画"；两者之间用 `hud.set_enemy_hp(...)`、`hud.popup_damage(...)` 等方法或 `signal` 解耦。
**落地位置**：新增 `battle_hud.gd` + `scenes/ui/battle_hud.tscn`，`duel_controller.gd` 删去对应构建/刷新代码（预计砍掉 400+ 行）。

### 建议 5 — 屏幕脚手架复用（ScreenScaffold）
**原则**：重复 4 套的"背景+margin+根容器"抽成模板。
**方案**：
- 提供 `scripts/ui/screen.gd` 辅助：`func build_scaffold(parent) -> VBoxContainer`，内部统一 new `ColorRect(full_rect)` + `MarginContainer` + 根 `VBox` 并应用 Theme。
- 或更进一步：整备/奖励/铁砧做成独立 `.tscn` 子界面，`duel_controller` 用 `add_child`/移除切换，而非每套都重写背景样板。
**落地位置**：覆盖 `_build_loadout` / `_build_reward` / `_build_anvil` / `_build_overlay`。

### 建议 6 — 响应式与锚点策略
**原则**：用 `size_flags` + 安全区，而非写死像素；保证常见分辨率（1280×720 / 1920×1080）下不挤压。
**方案**：
- 转轮 `GridContainer` 用 `CENTER` 包裹、`size_flags_horizontal = EXPAND_FILL`，格子尺寸改为 `min(84, 视口宽/列数)` 或保持 84 但允许整体缩放。
- 左右面板用 `size_flags_horizontal = EXPAND_FILL` 而非固定 `custom_minimum_size` 宽，仅在窄屏时退化。
- 考虑 `get_tree().root.content_scale_mode = CANVAS_ITEMS` + `content_scale_size` 做整体缩放（在 `project.godot` 设 base resolution）。
**落地位置**：`_build_ui` 的 `main` / 各 `custom_minimum_size`。

### 建议 7 — 可访问性（字体下限 / 对比度 / 键盘 / tooltip）
**原则**：正文不小于 12px、前景/背景对比度 ≥ 4.5:1、核心操作可键盘触发、符号可 hover 解释。
**方案**：
- 日志/图例字号下限提到 12px（建议 13）。
- 用 `Palette` 统一前景色，避免浅灰小字（`Color(0.70,0.70,0.75)` 在深色底 OK，但 10px 仍偏小）。
- 给整备/重置按钮加 `shortcut`（如 `Ctrl+E` / `Ctrl+R`），并设 `focus_mode` 与合理 `focus_neighbor`。
- 净化按钮已废除（净化完全走消耗品「净化药剂」，从 4 格子腰带主动点击使用）—— 故无 `Ctrl+P` 绑定。
- 转轮格子 `mouse_default_cursor_shape = CURSOR_HELP`，hover 时 `hud.show_tooltip(symbol_id)` 弹出名称/类型/元素/元素关系。
**落地位置**：`symbol_cell.tscn` + `_build_ui`。

### 建议 8 — 表现层性能（对象池 / diff 刷新）
**原则**：避免每帧/每次刷新 new+free 节点。
**方案**：
- `_refresh_legend`：只在 `pool`/`enemy_element` 变化时重建；或预建固定条目、仅改 `text`/`color`（diff 刷新）。
- `_popup`：用 `Label` 对象池（预建 N 个，借出/归还 + tween 复位），避免瞬时 new。
- 飘字改挂到独立 `CanvasLayer`（或 `Control` 浮层），用局部坐标定位，去掉 `get_global_rect()` 的脆弱计算。
**落地位置**：`_refresh_legend` / `_popup`。

---

## 四、分阶段路线图（不破坏现有可玩性）

### Phase 0 — 快速见效（零逻辑改动，1~2 小时）
- [ ] 新建 `theme/battle_theme.tres`，把通用字号/颜色/StyleBox 搬进去；`duel.tscn` 挂 theme。
- [ ] 新建 `scripts/ui/palette.gd` + `type_scale.gd`，替换魔法字面量（颜色/字号集中）。
- **收益**：后续所有视觉调整一处生效；为 Phase 1 打底。

### Phase 1 — 组件化与脚手架（中等改动）
- [ ] 提取 `ui_button.tscn` / `ui_panel.tscn` / `symbol_cell.tscn`，替换代码 `new()`。
- [ ] 提取 `screen.gd` 脚手架，干掉 4 套背景样板。
- **收益**：新增/修改界面成本大幅下降；编辑器可可视化调组件。

### Phase 2 — 关注点分离（结构性）
- [ ] 抽 `battle_hud.gd` + `battle_hud.tscn`，`duel_controller` 只留逻辑。
- [ ] 整备/奖励/铁砧做成独立子界面 `.tscn`，由 `duel_controller` 切换。
- **收益**：`duel_controller` 大幅瘦身（预计 -400~600 行），回归风险降低。

### Phase 3 — 响应式与可访问性打磨
- [ ] 响应式缩放 + 安全区；键盘快捷键 + 焦点链；符号 tooltip。
- [ ] 图例/飘字对象池与 diff 刷新。
- **收益**：体验与性能达标，达到上线级 UI。

> 每阶段结束都在真机 F6 验收后再进入下一阶段；Phase 2 改动最大，建议单独 commit。

---

## 五、风险与注意事项

1. **保持可玩性优先**：本次改造是"换皮不换脑"，战斗结算逻辑（`_evaluate` / `_on_spin_pressed` 异步分段 / 属性克制）一行不动，只在 Phase 2 抽 `BattleHud` 时把"刷新调用"改为"方法/信号调用"。
2. **Theme 覆盖优先级**：`add_theme_*_override` 优先级高于 `Theme` 资源；Phase 0 引入 Theme 后，需逐个删除冗余 override，否则 Theme 不生效。先全局搜 `add_theme_` 确认清单。
3. **`.tscn` 资源路径**：组件场景用 `preload("res://...")` 固定路径；若之后移动文件需同步改 preload。
4. **本环境 git 不可靠**：改造过程请在真机 commit/push；本环境只改物理文件 + 静态核对（括号配平 / 跨文件 grep）。
5. **不要顺手删俯视角 RPG 残留**：它们虽不被加载，但 force-push 会不可逆；本次仅动老虎机链路文件。

---

## 附：建议新增/修改文件清单

**新增**
- `theme/battle_theme.tres` — 统一主题
- `scripts/ui/palette.gd` — 调色板常量
- `scripts/ui/type_scale.gd` — 字号阶梯
- `scripts/ui/screen.gd` — 屏幕脚手架辅助
- `scripts/ui/battle_hud.gd` + `scenes/ui/battle_hud.tscn` — HUD 子节点
- `scenes/ui/ui_button.tscn` / `ui_panel.tscn` / `symbol_cell.tscn` — 复用组件

**重构（削减）**
- `scripts/battle/duel_controller.gd` — 删 77 处 override、4 套样板、UI 构建与刷新代码（抽到上述文件）
