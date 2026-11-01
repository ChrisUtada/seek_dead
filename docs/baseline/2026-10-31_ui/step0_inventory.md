# 战斗 UI 重构 · Step 0 基线与引用检查（2026-10-31）

> 依据：《战斗UI重构_执行方案与AI任务书》（`docs/战斗UI重构_执行方案与AI任务书.md`）
> 本步只做**只读**检查与截图，不改任何游戏逻辑、数值、资源绑定。
> 采集工具：`tools/ui_capture_step0.gd` / `.tscn`（新增，仅工具，随 `tools/*` 排除出包）
> 产物目录：`docs/baseline/2026-10-31_ui/`

---

## 1. 基线截图清单

> 文件位于 `before/`（Step 0 采集，改造前）；Step 1 换肤后按同一工具、同一流程重采到 `after/`，用于前后对照。

| 文件 | 内容 | 分辨率 |
|---|---|---|
| `01_loadout_960.png` | 整备（启动软默认） | 960×540 |
| `02_battle_960.png` | 普通房刚入场（回合 1，满血） | 960×540 |
| `03_boss_960.png` | 样板 BOSS 冰封铁瓮（内存替换为 `frozen_urn`，`art_scale 2.0`） | 960×540 |
| `04_shop_960.png` | 商店覆盖层 | 960×540 |
| `05_reward_960.png` | 房奖励三选一 | 960×540 |
| `06_anvil_960.png` | 铁砧 | 960×540 |
| `07_meta_960.png` | 局末元进度结算 | 960×540 |
| `08_spin_960.png` | 转轮滚动中（SPIN 后 0.18s） | 960×540 |
| `08b_spin_960.png` | 转轮滚动中（+1.2s，观察纵向滚动节奏） | 960×540 |
| `09_battle_1440.png` | 普通房 | 1440×810（3×） |
| `10_boss_1440.png` | 样板 BOSS | 1440×810（3×） |
| `11_battle_1920.png` | 普通房 | 1920×1080（4×） |

配套数据：`capture_data.txt`（视口/窗口、栏宽、转轮格尺寸、立绘与舞台实测、转轮状态）。

采集口径：

- BOSS 截图把本局某个 BOSS 席位**在内存里**替换为 `resources/rooms/frozen_urn.tres`，不写资源、不写存档，保证改造前后是同一只 BOSS、同一幕数。
- 转轮滚动截图放在最后：**SPIN 不会自动停**，必须逐列按停；脚本在截完两张后调用 `finish_spin()` 收尾（会触发一次敌回合，不再截图）。
- 采集工具不改存档：实跑前后 `lobby_data.json` 逐字节一致。

## 2. 实测尺寸与关键结论

| 项 | 实测值 | 备注 |
|---|---|---|
| 逻辑分辨率 | 480×270 | `canvas_items` 拉伸，窗口 960/1440/1920 均为整数倍（2×/3×/4×），截图无插值模糊 |
| 左栏宽 | **87**（`custom_minimum_size` 仅 76） | 被内容撑开（`HP100/100`、`Lv.1 · 0/3`、`技能: 无`），任务书写 90–92，实际只差 3–5px |
| 右栏宽 | 84 | 与任务书 90 差 6px |
| 中央舞台 | 291×234 | 左右栏再各加宽 6–8px 会挤掉约 14px 舞台 |
| 转轮格 | 48×48 | 任务书写约 38×38 |
| 玩家立绘 | `assets/characters/viking/idle_01~03.png`（48×48）→ 容器 96×96（2×） | **不是** `knight1.png` |
| 敌人立绘 | `assets/enemy.png`（16×16）→ 64×64（4×） | 普通房默认图 |
| BOSS 立绘 | `assets/bossbf.png`（48×48）× `art_scale 2.0` = 128×128 | `resources/rooms/frozen_urn.tres` |
| 顶栏高度 | 约 22px（含 9px 按钮） | 与任务书 21–23px 一致 |
| 外框 / 常驻标题 | **均不存在** | M3-01 已删除，当前只有 `Bg` + 6px `Margin` |
| SPIN 自动停 | **不会自动停** | 需逐列按停；自动化截图必须显式 `finish_spin()` 收尾 |

**结论：骨架（顶栏 + 三栏 + 中央三转轮 + SPIN）已经成立，与概念图一致。差距集中在配色、线框、图标与信息层级，不需要重做布局。**

## 3. `battle_hud.tscn` 结构树

```text
BattleHud (Control, anchors 全屏)
├── Bg (ColorRect #1F171F)
└── Margin (MarginContainer, 6px)
    └── Content (VBoxContainer, sep 1)
        ├── InfoBar (HBoxContainer, sep 4)
        │   ├── RoomLabel / TurnLabel / InfoSpacer / RunLabel
        │   ├── ShopBtn (60×18, ui_button 实例, 默认 disabled)
        │   └── NextRoomBtn (64×18, ui_button 实例, 默认 disabled)
        ├── NextRoomBar (Label, 间歇态专用, 默认隐藏)
        └── MainRow (HBoxContainer, sep 3)
            ├── PlayerPanel (PanelContainer, min 76, sb_panel_compact)
            │   └── VBox
            │       ├── PlayerTitle / PlayerHpLabel / PlayerLevelLabel
            │       ├── GearBox
            │       │   ├── WeaponsRow (VBox)  └── WeaponsTag「武」
            │       │   ├── CharmsRow (HBox)   └── CharmsTag「护」
            │       │   └── SkillsRow (HBox)   └── SkillsTag「技」
            │       ├── ConsumableTitle
            │       ├── ConsumablePanel (Grid 2 列) └── Cell1..Cell4 (28×18)
            │       ├── PlayerBuffLabel / GoldLabel / PlayerSpacer
            ├── CenterStage (VBox, 扩展)
            │   ├── StageRow (HBox, sep 8)
            │   │   ├── PlayerCenter └── PlayerSprite (96×96)
            │   │   └── EnemyCenter  └── EnemySprite (64×64, 运行期按 art_scale 改尺寸)
            │   └── ReelDock (VBox)
            │       ├── TopRow └── ReelCenter └── GridContainer (3 列, sep 6)
            │       └── SpinBar └── SpinButton (104×24)
            └── EnemyPanel (PanelContainer, min 84, sb_panel_compact)
                └── VBox
                    ├── EnemyTitle / EnemyElementLabel / BossBadge
                    ├── EnemyNameLabel / EnemyHpLabel / EnemyArmorLabel
                    ├── EnemyWeakLabel / EnemyResistLabel / EnemyIntentLabel
                    └── EnemyStatusLabel / EnemyChargeLabel
```

## 4. 脚本节点引用清单（改名/移动必须同步）

`scripts/ui/battle_hud.gd` 中共 **33** 处 `$` 硬编码路径，全部以 `Margin/Content/...` 开头：

| 分组 | 路径（相对 `Margin/Content`） | 数量 |
|---|---|---|
| 顶栏 | `InfoBar/RoomLabel`、`InfoBar/TurnLabel`、`InfoBar/RunLabel`、`InfoBar/ShopBtn`、`InfoBar/NextRoomBtn` | 5 |
| 间歇横幅 | `NextRoomBar` | 1 |
| 转轮 | `MainRow/CenterStage/ReelDock/TopRow/ReelCenter/GridContainer`、`.../ReelDock/SpinBar/SpinButton` | 2 |
| 玩家栏 | `MainRow/PlayerPanel/VBox/` 下 `PlayerHpLabel`、`PlayerLevelLabel`、`PlayerBuffLabel`、`GoldLabel`、`GearBox/WeaponsRow`、`GearBox/CharmsRow`、`GearBox/SkillsRow`、`ConsumablePanel/Cell1..4` | 11 |
| 敌人栏 | `MainRow/EnemyPanel/VBox/` 下 `EnemyNameLabel`、`EnemyHpLabel`、`EnemyArmorLabel`、`EnemyIntentLabel`、`EnemyStatusLabel`、`EnemyChargeLabel`、`EnemyElementLabel`、`EnemyWeakLabel`、`EnemyResistLabel`、`BossBadge` | 10 |
| 立绘 | `MainRow/CenterStage/StageRow/PlayerCenter/PlayerSprite`、`.../EnemyCenter/EnemySprite` | 2 |
| 面板引用 | `MainRow/PlayerPanel`、`MainRow/EnemyPanel` | 2 |

**外部脚本同样持有硬编码路径**（改结构必须一起改，任务书 §4.2 只点了 `battle_hud.gd`，此处补全）：

| 文件 | 引用 |
|---|---|
| `scripts/ui/battle_animator.gd:45-46` | `Margin/Content/MainRow/CenterStage/StageRow/PlayerCenter/PlayerSprite`、`.../EnemyCenter/EnemySprite` |
| `tools/ui_capture_step0.gd` | `Margin/Content/MainRow/CenterStage`（仅工具，不入包） |

其他子屏（`loadout_scene` / `reward_screen` / `shop_screen` / `anvil_screen` / `meta_screen`）由各自脚本持有引用，本任务不重构其结构，仅在 Step 5 验证换肤后未被破坏。

**可安全增删、不破坏脚本的节点**：`InfoSpacer`、`PlayerTitle`、`ConsumableTitle`、`WeaponsTag/CharmsTag/SkillsTag`、`PlayerSpacer`、`EnemyTitle`（无脚本引用，仅 tscn 静态内容）。

## 5. 主题与 StyleBox 清单（Step 1 换肤对象）

| 文件 | 样式块 | 现状 | 目标 |
|---|---|---|---|
| `theme/battle_theme.tres` | `StyleBoxFlat_panel` | 2px 边框 `#C7B89E`，底 `#261C24`@85%，margin 8 | 1px `#E2D7BD`，底 `#1D1219` 实色，margin 4 |
| `theme/battle_theme.tres` | `StyleBoxFlat_tooltip` | 2px `#C7B89E`，底 `#1A121A`@96% | 1px `#A99D89`，底 `#1D1219`@98% |
| `theme/battle_theme.tres` | Label / RichTextLabel / Tooltip 字体 | 10px Vonwaon + zpix | 不变（保持 9/10 缓存档） |
| `scenes/ui/battle_hud.tscn` | `sb_panel_compact` | 2px **偏蓝灰** `#38384D`，底 `#261C24`@85% | 1px `#A99D89`，底 `#1D1219` 实色 |
| `scenes/ui/battle_hud.tscn` | `Bg` ColorRect | `#1F171F` | `#160D13` |
| `scenes/ui/ui_button.tscn` | normal / hover / pressed / disabled | 1px 蓝灰 `#38384D`，底 `#292938` | 1px `#A99D89`；hover 亮一档；pressed 底压暗；disabled 同时降边框与文字 |
| `scenes/ui/symbol_cell.tscn` | normal / disabled | 2px `#38384D`，底 `#2E2E3D` | 1px，暖白；**注意：战斗内该样式会被运行期 `_cell_style()` 完全覆盖**，需同步改 `palette.gd` 才在实机生效 |
| `scenes/ui/item_card.tscn`、`anvil_cell.tscn`、`reward_screen.tscn`、`loadout_scene.tscn` | 各自局部 StyleBox | 蓝灰系 | 只做配色对齐，不改结构（Step 5 回归） |

运行期样式入口（改主题必须一起改，否则实机不生效）：

- `battle_hud.gd:_cell_style()` → `Palette.CELL_BG` + `Palette.PANEL_BORDER` + `Palette.BORDER_WIDTH`，覆盖 `symbol_cell.tscn` 的 normal/hover/pressed/disabled（第 800–868 行）
- `battle_hud.gd` 符号 tooltip 局部 StyleBox（第 598 行附近）
- `battle_hud.gd` 替换弹层 / 成长选择器局部 StyleBox（第 1014、1022 行附近）
- `battle_hud.gd:_popup()` 飘字颜色来自 `Palette.POP_*`

## 6. 颜色替换表（现状 → 任务书色板）

实测确认：`Color(r,g,b)` 浮点值与 8bit sRGB 一一对应（截图像素 `Color(0.12,0.09,0.12)` = `#1F171F`），因此 Step 1 可直接用 `Color("#hex")` 书写。

| `palette.gd` 常量 | 现值 | 渲染色 | 目标 | 用途说明 |
|---|---|---|---|---|
| `BG_MAIN` | 0.12,0.09,0.12 | `#1F171F` | `#160D13` | 全屏/中央舞台 |
| `PANEL_BG` | 0.15,0.11,0.14 @0.85 | `#251B23` | `#1D1219`（实色） | 左右栏、卡片、按钮 |
| `PANEL_BORDER` | 0.78,0.72,0.62 | `#C7B89E` | `#E2D7BD` | 主文字/主线框 |
| `CELL_BG` | 0.20,0.16,0.20 | `#332933` | `#1D1219` | 转轮格底 |
| `TITLE` | 0.90,0.85,0.70 | `#E5D9B3` | `#E2D7BD` | 标题 |
| `PLAYER` | 0.88,0.87,0.84 | `#E0DED6` | `#B9B8B0` | 玩家灰白 |
| `ENEMY` | 0.95,0.55,0.55 | `#F28C8C` | `#E35B50` | 敌人红 |
| `MUTED` | 0.70,0.70,0.75 | `#B3B3BF` | `#A99D89` | 次级文字 |
| `MUTED_DIM` | 0.65,0.65,0.75 | `#A6A6BF` | `#6E5F57` | 弱信息 |
| `ACCENT_GOLD` | 1.00,0.85,0.30 | `#FFD94D` | `#D5A33D` | 交互金（SPIN/匹配/奖励） |
| `ARMOR` | 0.75,0.80,0.90 | `#BFCCE6` | `#62A1C2` | 护盾/护甲 |
| `POP_HEAL` | 0.50,0.95,0.60 | `#80F299` | `#A4BC4D` | 治疗 |
| `POP_DAMAGE` | 1.00,0.50,0.40 | `#FF8066` | `#E35B50` | 伤害 |
| `POP_SHIELD` | 0.55,0.70,0.95 | `#8CB3F2` | `#62A1C2` | 护盾 |
| `POP_GOLD` | 1.00,0.80,0.15 | `#FFCC26` | `#D5A33D` | 金币 |
| `BORDER_WIDTH` | 2 | — | 1（选中/SPIN/奖励用 2） | 需同步改 `_cell_style()` |
| 新增 | — | — | `#3A222B` 深描边、`#8C3438` 敌人暗红 | 内部隔断、危险框 |

未在任务书色板中定义、需保留现状的：`RARITY_*`（common/uncommon/rare/epic）、`POP_STATUS`、`POP_BUFF`、`CARD_SEL_*`、`BG_LOADOUT/BG_REWARD/BG_ANVIL`（Step 5 再决定是否统一）。

## 7. 图标与文字回落清单（Step 4 依据）

| 对象 | 现状 | 缺口 |
|---|---|---|
| `SymbolData.icon_tex` | 字段已存在；**48 个符号资源中 0 个赋值** | 转轮格全部走 emoji 文字（`🔥`/`🗡`/`💎`/`MISS`），实机可行但尺寸随系统 emoji 字体变化 |
| `LoadoutItem.icon_tex` / `.art` | 字段已存在；武器/护符/技能资源**均未赋值** | 左栏武器 = `🗡️ + 元素 emoji`；护符 = 资源 `icon`（emoji）；技能 = 资源 `icon` |
| `ItemCard.set_art()` | 接口已存在，`_icon_rect` 隐藏逻辑完备 | 商店/奖励卡片无主图 |
| 元素图标 | `player_panel_view.element_icon()`：🔥 / ❄ / ☠ / ✨ / 🌑 | 与概念图图标风格不一致 |
| `RoomData.art` | 仅 `frozen_urn` 等 BOSS 绑定；默认 `assets/enemy.png`（16×16） | 普通/精英敌人风格不统一 |
| 受击闪色 | `battle_animator.gd` 已用暖白 `Color(1.75,1.70,1.55)` | **Step 3 第 7 项已满足**，红 BOSS 上可见 |

## 8. 任务书 ↔ 代码 差异表与执行口径

| # | 任务书 | 实测 | 建议口径 |
|---|---|---|---|
| 1 | Step 2 删 `DeviceFrame` 厚外壳、常驻标题 | 两者已不存在（M3-01 删除） | 降级为「确认无残留」；省下的工作量转为**新增 1px 外框 + 少量角部铆钉**（任务书 §5.2 要求） |
| 2 | §7.3 验收 `run_smoke.bat` 8/8 | 实为 **13 套**（见 §9） | 验收口径改为 13/13 |
| 3 | 转轮格约 38×38 | 48×48 | 建议 42：介于现状与概念图之间，16px 图标仍可辨；若坚持 38 需同时缩小 `SPACING`（现 24）并复查 `ReelSpinView` |
| 4 | 左 90–92 / 右 90 | 左 87（min 76）/ 右 84 | 左右各 +3~6px 即可贴合概念图，舞台损失约 12px；**建议只把 min 提到 88/88**，不再加宽 |
| 5 | 右栏「下一意图」三行列表 | 引擎一回合只有 1 个 `enemy_intent` | 改为「当前意图（金色强调）+ 充能进度 + 状态」三段；不伪造多意图数据 |
| 6 | Step 3 以 `knight1.png` 为输入 | HUD 用 `viking/idle_01~03`（3 帧待机动画） | 风格化输入改为 viking 三帧（保持 48×48、整数倍率）；`knight1.png` 保持原样 |
| 7 | 底部短反馈行 | 无此节点；伤害分解仅 `Debug.log`，屏幕只有总伤害飘字 | Step 5 新增 1 行 Label；数据从 `combat_system` **只读暴露本击摘要**（不改公式/时序），失败时回落不显示 |

## 9. 基线回归结果

`run_smoke.bat`：**13/13 ALL GREEN，exit 0**（2026-10-31 16:52–16:58 实跑，改动前基线）

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

合计 4872 条断言，0 失败。

> **副作用记录**：`run_smoke.bat` 里的整局 smoke 会真实走房间结算与元进度入账，直接改写
> `%APPDATA%\Godot\app_userdata\Seek Dead Prototype\lobby_data.json` 的 `anvil_points`
> （本次基线期间 6899 → 7001）。**每次跑基线前后都要备份/还原存档**；本次已备份并在收尾后还原为 6899。

## 10. Step 0 结论与 Step 1 输入

1. 骨架已成立：顶栏 + 左栏 + 中央舞台 + 三转轮 + SPIN + 右栏，与概念图同构，**不需要重排**。
2. Step 2 缩减为三项：新增 1px 外框（含少量角部铆钉）、左右栏 min 调整为 88/88、微调 2/4px 间距；节点路径不变则无需改脚本，变则同步 §4 的 33 条 `$` 引用。
3. Step 1 可直接按 §6 表改 `palette.gd` + `battle_theme.tres` + `ui_button.tscn`；**必须同时改 `_cell_style()` 与 `BORDER_WIDTH`**，否则转轮格实机不换色。
4. Step 4 的真实工作量是「资源没有图标」而非「组件不支持」：`SymbolData.icon_tex`、`LoadoutItem.icon_tex/art` 字段与回落逻辑均已就绪，只需产出 16×16 转轮图标与 24/48 卡片图并绑到样板资源。
5. 待确认项（默认值见括号）：左右栏宽度（88/88）、转轮格尺寸（42）、玩家立绘（继续 viking idle 三帧）、底部反馈行（Step 5 做）。
