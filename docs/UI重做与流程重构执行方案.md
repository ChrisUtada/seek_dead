# UI 重做与流程重构执行方案（P3c / 商店 opt-in / P4 动画）

> 状态：**Option C 已落地（`1e4772c`）；P3c 布局重构已落地（`061b974`）；转轮位置微调（ReelDock 上移进 CenterStage 战斗画面正下方居中）；玩家立绘已用 `assets/char.png` 替换（提前 P5）；**P4 动画骨架已落地（新增 battle_animator.gd + 玩家/敌人攻击·受击·暴击/核爆演出挂接结算点）；敌人立绘已用 `assets/enemy.png` 替换（EnemySprite TextureRect）**；商店抽屉（D2）/ P5 剩余 待实施**。均待用户 F6 复验
> 最后更新：2026-08-05
> 关联基线：`2a927ba`（含 `2864c00` 方案A 三连暴击 `crit_mult`）
> 前置已完成：P3b-2（5 套覆盖层抽独立 `.tscn`，`hide_screen()` 修复，`3f8aefb`）已推送

---

## 0. 背景与已拍板决策

### 0.1 现状痛点
- 主战斗 HUD 是「转轮在中栏 + 文字伤害分解刷一排」，玩家盯数字而非演出，**缺乏游戏感**。
- 每房（非最终 BOSS）强制全屏商店（`duel_controller.gd` L616/627/639 → `_show_shop_screen()`），无金币/无购买欲也得开一下点离开，**摩擦大**。
- 商店当前**兼任「房间间歇」**——它把"交易"和"两场战斗间的停顿"绑死。

### 0.2 已拍板的三大决策（对话锁定）
| 编号 | 决策 | 说明 |
|---|---|---|
| **D1** | 转轮移入战斗画面（CenterStage）正下方居中 + 中央动画舞台 | 转轮是重要视觉元素，须居中且不沉到屏幕最底；眼睛跟中央小人打架而非数字 |
| **D2** | 商店改为 opt-in，新增「房间歇态」+ 🛒 常驻入口 + 右侧抽屉 | 告别强制全屏商店；复用 `shop_screen.gd` 逻辑，仅改 `.tscn` 根节点 |
| **D3** | **间歇 = 闲置的主 HUD**，而非强制商店 | 关键澄清：强制商店只是"唯一全屏安全态"被借用作间歇；删掉强制商店后，停顿由"必须点 ▶ 下一房才前进"结构性保留，只需把商店从"强制"降为"可选" |

> D3 是 2026-08-05 最新澄清，解决了"改成主动弹出后战斗间没间歇"的担忧——**间歇不会消失，只是从强制商店搬到闲置主 HUD，且因棋盘全貌可见反而更舒服**。

---

## 1. 布局重构规格（P3c）

### 1.1 目标布局（ASCII 草图）
```
┌──────────────────────────────────────────────────────────┐
│ ❤75/175 🛡12 🏛5🔨 💰230   4/12 (Act I)  [🛒商店][▶下一房] │ ← 顶栏：玩家状态 + 进度 + 间歇态两按钮
├──────────┬───────────────────────────────┬────────────────┤
│          │       ★ 中央动画舞台 ★          │                │
│ 玩家立绘 │  (TextureRect / Control 区)     │   敌人立绘      │
│ 🔮护符   │  🗡️             💀            │   HP ▓▓▓░      │
│ 🛡增益   │  (攻击/受击/暴击⚡/核爆动画)      │   意图 ⚔        │
│          │  ┌─────────────────────────┐   │   护甲 🛡       │
│          │  │ ┃┃┃ 转轮（正下方居中）[▶SPIN]│   │                │
│          │  └─────────────────────────┘   │                │
├──────────┴───────────────────────────────┴────────────────┤
│ ▔▔▔ 半透明伤害日志条（薄，可卷动）▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔ │ ← 底部：伤害日志（薄）
└──────────────────────────────────────────────────────────┘
```
- **转轮从「中栏」搬入「中央舞台正下方居中」**（ReelDock 现为 `CenterStage` 子节点，StageRow 之下、BottomRow 之上）：仍是常驻（敌人回合/结算中也不消失），但作为重要视觉元素居中、不再贴 HUD 最底 dock。
- **中央挖出动画舞台**：玩家 + 敌人立绘（`TextureRect`），SPIN/MATCH/暴击/核爆时演出。
- **伤害分解降级**：从「中栏主视觉」→「底部薄日志条 + 中央浮空伤害数字」，文字退居辅助。
- **顶栏吞**：HP/盾/铁砧/金币/房间进度 + 间歇态三按钮。
- **左栏**：护符 + 增益；**右栏**：敌人 HP/意图/护甲。

### 1.2 节点锚定建议（`battle_hud.tscn`）
| 区域 | Control 类型 | 锚点/布局 | 备注 |
|---|---|---|---|
| 顶栏 | `HBoxContainer` | `anchors_preset=15`（全屏）+ `anchor_bottom=0.08` | 固定高度 ~56px；右侧塞 🔧/🛒/▶ 三按钮 |
| 中央舞台 | `Control`（含两个 `TextureRect`） | 占中，`size_flags_vertical=EXPAND_FILL` | 预留 `player_sprite` / `enemy_sprite` 节点供 P4 动画引用 |
| 左栏 | `VBoxContainer` | 左上，`anchor_right=0.22` | 护符 + 增益列表 |
| 右栏 | `VBoxContainer` | 右上，`anchor_left=0.78` | 敌人 HP/意图/护甲 |
| 转轮区（CenterStage 内） | `HBoxContainer`(ReelDock) | `CenterStage` 子节点（StageRow 下、BottomRow 上） | 消耗品腰带(4槽) + 转轮 + SPIN，居中 |
| 伤害日志条 | `ScrollContainer`（薄） | 中央舞台下方叠加 | 半透明，仅显示最近 N 行 |

### 1.3 不变部分
- **5 套 modal 覆盖层**（整备/奖励/元进度/商店/铁砧）继续全屏——它们是决策态用，与实时动作布局不冲突。P3b-2 抽独立 `.tscn` 正是为此铺垫，**本次布局重排零波及**。
- 共享卡片构造器（`_make_*_card` / `_label` / `_item_pool_of` / `_source_tag`）不动。

### 1.4 落地方式
纯 `battle_hud.tscn` 编辑器重排 + `battle_hud.gd` 节点引用迁移（29 节点 `$路径` 模式沿用，参照 P3b-1 经验）。低风险，是 P4 动画的地基——**必须早于 P4**。

---

## 2. 流程 / 状态机重构（opt-in 商店 + 房间歇态）

### 2.1 新增 `INTERROOM` 相位
- controller 现有 `game_state` 字符串 + `in_loadout` 布尔（L195）。**新增镜像布尔**：
  ```gdscript
  var in_interroom := false   # 房间歇态：奖励结算后、进下一房前
  ```
- SPIN / 点击转轮 的闸门（现 `L1303`/`L1664`/`L1731` 的 `if in_loadout or game_state != "playing" or _busy:`）改为追加 `or in_interroom`：
  ```gdscript
  if in_loadout or in_interroom or game_state != "playing" or _busy:
  ```

### 2.2 信号变更清单（`battle_hud.gd` 顶部，接 L30 后）
新增 2 个意图信号（沿用 P2 信号解耦范式）：
```gdscript
signal shop_requested                          # 🛒 打开商店抽屉（间歇态）
signal next_room_requested                     # ▶ 下一房（间歇态）
```
> `_on_reload_loadout_pressed`（L602）已存在并调 `_show_loadout_screen()`，直接复用为 🔧 整备按钮，无需新信号。

### 2.3 函数改动清单（`duel_controller.gd`）
| 函数 | 现状 | 改为 |
|---|---|---|
| `_on_reward_chosen` (L608) | 末尾强制 `_show_shop_screen()` | 改为 `_enter_interroom()` |
| `_on_reward_skip_pressed` (L620) | 末尾强制 `_show_shop_screen()` | 改为 `_enter_interroom()` |
| `_on_boss_reward_chosen` (L631) | 末尾强制 `_show_shop_screen()`（非最终 BOSS 时） | 非最终 BOSS 时改为 `_enter_interroom()` |
| **新增** `_enter_interroom()` | — | `in_interroom = true`；`_show_hud_idle()`（中央舞台平息、转轮待机）；点亮 🔧/🛒/▶ 三按钮（`hud.set_interroom_enabled(true)`） |
| `_on_shop_leave_pressed` (L1101) | `hide_shop + _start_room(next)` | **拆开**：`hide_shop` 后回 `_enter_interroom()`（重新点亮按钮，**不前进**） |
| **新增** `_on_next_room_pressed()` | — | `in_interroom = false`；`_start_room(room_index + 1)` |
| `_on_reload_loadout_pressed` (L602) | 开整备屏 | 保留；确认配装（`_confirm_loadout`）后回 `_enter_interroom()` 而非直接进战斗 |

### 2.4 HUD 侧改动（`battle_hud.gd` + `.tscn`）
- 顶栏新增 🔧整备 / 🛒商店 / ▶下一房 三按钮，连线：
  ```gdscript
  reload_btn.pressed.connect(controller._on_reload_loadout_pressed)
  shop_btn.pressed.connect(shop_requested.emit)
  next_btn.pressed.connect(next_room_requested.emit)
  ```
- 新增公开接口 `set_interroom_enabled(on: bool)`：统一置三按钮 `disabled = not on`，并在战斗/转轮旋转时强制 `false`。
- controller `_ready` 订阅：`hud.shop_requested.connect(_on_shop_requested)` / `hud.next_room_requested.connect(_on_next_room_pressed)`。
- `_on_shop_requested`：仅当 `in_interroom` 时 `hud._show_shop_screen()`（抽屉态，见 §2.5）。

### 2.5 商店抽屉化（D2，可后置）
- `shop_screen.tscn` 根节点从「全屏」改「右侧 docked 面板」（保留 `shop_screen.gd` 全部逻辑：三页签/卡片/`_roll_shop` 一行不动）。
- 离开抽屉（`_on_shop_leave_pressed`）→ 回间歇态，**不**自动进房。
- **最小验证先做 Option C**：商店暂不重排（仍全屏），只把强制 `_show_shop_screen()` 换成点亮 🛒；手感对了再上抽屉。

### 2.6 相位闸门（防崩）
🛒/🔧/▶ 下一房 在战斗中全部 `disabled`（`set_interroom_enabled(false)` + `in_interroom=false`），仅 `INTERROOM` 相位亮起——杜绝 SPIN 中途卖正在用的武器导致状态炸裂。

---

## 3. 战斗动画规格（P4）

### 3.1 新增 `battle_animator.gd`
- `class_name BattleAnimator`，持有 `hud` 引用，定位中央舞台的立绘节点（实际节点名 `PlayerSprite` / `EnemySprite`，已分别引用 `assets/char.png` / `assets/enemy.png`）。
- 全部用 `Tween` 驱动，**先占位图形（彩色方块/圆圈）跑通手感**，立绘资源（P5）后替换 `TextureRect.texture`，与 P3c/P4 解耦。
- 挂点：在 `_evaluate` / `_contribute` / 敌人意图结算处调用对应动画方法。

### 3.2 动画档位（按优先级）
| 档位 | 动画内容 | 触发点 | 实现要点 |
|---|---|---|---|
| **P0** | 玩家前冲 + 武器挥砍 → 敌人红闪 + 浮空伤害数字 | 每次连线结算 | `Tween` position 偏移 + `modulate` 红闪 + `Label` 上浮淡出 |
| **P0** | 屏幕轻微震动 + 中央 "⚡暴击 ×N" 大字 | 三连（`crit_mult`） | `camera`/`Control` 抖动 + 居中 `Label` 缩放弹入 |
| **P1** | 敌人反击动画 → 玩家红闪（盾先掉） | 敌人意图结算 | 反向前冲 + 玩家 `modulate` 红闪 |
| **P1** | 敌人护甲碎裂粒子 + 追击穿透 | 克制元素三连核爆 | `GPUParticles2D` 或简单碎片 `Tween` |
| **P2** | 敌人溶解 + 金币雨 | 击杀 | `modulate.a` 渐隐 + 多 `Label` 金币下落 |

### 3.3 与结算解耦原则
动画**只读**结算结果（伤害值/是否暴击/是否克制），**不改** `BattleMath` 纯结算函数（已在 `battle_math.gd`，P0 优化）。浮空数字颜色随克制关系（`ElementCounter`）着色。

---

## 4. 美术（P5）
- 玩家/敌人立绘为 `TextureRect` 资源，替换 P4 占位图形，零重构风险。
- 敌人 roster 按 `room_data.gd` / 敌人规划文档（§14）出图，立绘节点命名与 §3.1 一致即可即插即用。
- 不影响任何布局/流程/动画逻辑。

---

## 5. 落地节奏 / 分阶段提交计划
> 每阶段 = 1 个 commit + **F6 真机复验通过**再进下一阶段（项目铁律）。

| 阶段 | 内容 | 范围 | 风险 |
|---|---|---|---|
| **Option C**（最小验证） | 强制商店→点亮 🛒 + ▶下一房（商店仍全屏） | `duel_controller` L608/620/631/1101 + 新增信号 + HUD 三按钮 | 低 |
| **P3c**（布局重构） | 转轮沉底 + 中央舞台 + 顶/左/右栏重排 | `battle_hud.tscn` + `battle_hud.gd` 节点引用 | 中（编辑器重排） |
| **P4**（动画骨架） | `battle_animator.gd` + 占位图形 P0 档 | 新增脚本 + 挂结算点 | 中 |
| **商店抽屉**（D2 完成） | `shop_screen.tscn` 根节点改 docked | `shop_screen.tscn` 仅 | 低 |
| **P5**（美术） | 立绘替换占位 | 资源 + `TextureRect.texture` | 低 |

---

## 6. 风险登记
| 风险 | 说明 | 缓解 |
|---|---|---|
| ⚠ `TEST_PLAYER_DMG_MULT=1.5` / `TEST_STATUS_DMG_MULT=3.0` | 正式平衡须改回 `1.0` | 待 F6 全链路通过后统一改；本次 UI 重构不碰 |
| ⚠ 覆盖层脚本勿覆原生方法 | P3b-2 F6 曾因 `func hide()` 撞 `CanvasItem.hide()` 编译失败（已改 `hide_screen()`） | 新增脚本（如 `battle_animator`）避免定义 `show/hide` 等原生同名方法 |
| ⚠ 相位闸门 | SPIN 中途卖装备会炸状态 | `in_interroom` 闸门统一锁三按钮 + SPIN |
| ⚠ 手写 `.tscn` parent 路径 | P3b-1 教训：`parent` 须根起完整路径，`%Name` 不可靠 | 沿用 `$节点路径`；改完跑 `verify_overlays.py` |

---

## 7. 文件改动速查
| 文件 | 阶段 | 改什么 |
|---|---|---|
| `scripts/battle/duel_controller.gd` | Option C / §2 | 新增 `in_interroom`；`L608/620/631` 强制商店→`_enter_interroom()`；新增 `_enter_interroom`/`_on_next_room_pressed`/`_on_shop_requested`；改 `_on_shop_leave_pressed` 拆开；SPIN 闸门加 `or in_interroom` |
| `scripts/ui/battle_hud.gd` | Option C / §2 | 顶部新增 `shop_requested`/`next_room_requested` 信号；顶栏三按钮 + `set_interroom_enabled()`；`_ready` 订阅新信号 |
| `scenes/ui/battle_hud.tscn` | P3c | 转轮沉底 dock + 中央舞台 + 顶/左/右栏节点 |
| `scripts/ui/battle_animator.gd` | P4 | 新增动画脚本（占位图形先上） |
| `scenes/ui/shop_screen.tscn` | 抽屉 | 根节点全屏→docked（逻辑不动） |
| `docs/代码审查与优化建议.md` / `docs/数值膨胀与策略深度设计框架.md` | 每阶段末 | 路线图状态列 + §15.1 台账 + 提交指针同步 |

---

## 8. 执行前确认清单（implementation kickoff）
- [ ] 用户拍板从哪个阶段先开刀（建议 **Option C** 先验证手感）
- [ ] 确认 `game_state` 现有取值（"playing" 之外还有哪些），避免 `in_interroom` 与既有状态冲突
- [ ] 中央舞台 `player_sprite`/`enemy_sprite` 节点命名在 P3c 落地时即固定，供 P4 引用
