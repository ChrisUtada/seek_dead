# 战斗 UI 重构纠偏 · 执行报告（2026-10-31）

> 依据：`docs/战斗UI重构_纠偏执行任务书.md`（C0–C6 + 附录 A）
> 目标图：`docs/mockups/battle_ui_concept_1440.png`
> 纠偏前截图：`docs/baseline/2026-10-31_ui/correct0/`（同工具、同固定普通房）
> 纠偏后截图：`docs/baseline/2026-10-31_ui/correct1/`（含 480×270 原生、1×/2×/3×/4× 整数放大）
> 工作区：未提交改动全部保留；未使用 reset / checkout / clean；未覆盖原始素材。

---

## 1. C0–C6 完成状态

| 项 | 状态 | 证据 |
|---|---|---|
| C0 保护现场与基线 | ✅ | `correct0/` 普通房（辉光游侠 HP100/100）+ 冰封铁瓮（532/532）；引用清单仅 `battle_hud.gd` / `battle_animator.gd` 持有立绘路径；纠偏前回归 13/13 |
| C1 角色尺寸 | ✅ | 玩家实机 48×48；普通敌人 48×48；冰封铁瓮 96×96（`art_scale = 2.0` 整数倍）；见 `03_boss_960` 与 `capture_data.txt` |
| C2 左栏大图标卡片 | ✅ | 双武器 39×38 两列卡片（24 art → 16 icon → emoji）；技能/护符同规格并排卡片；消耗品 34×30 2×2 方格；左栏仍 88 |
| C3 顶栏重排 | ✅ | `ACT 1 冰封 · 房 1/25` → 金币图标+数值 → 回合 → 商店 → 下一房；`RunLabel` 已移除（`RunLabel 仍存在=false`），本局加成转入左栏弱信息行 tooltip |
| C4 右栏图标化 / 中央 HP / 机制摘要 | ✅ | HP/护甲/充能图标行；名称→HP→护甲→弱/抗→意图→充能→状态→机制；玩家/敌人立绘下方实时 HP 同一地面线（y=172）；冰封铁瓮摘要 3 行且与 `gimmick_params` 交叉核对一致 |
| C5 普通敌人红色风格化 | ✅ | 新增 `assets/enemy_ember.png`（16×16 RGBA，红色少色，保留原透明与像素位置）；`DEFAULT_ENEMY_TEXTURE` 与场景默认纹理均指向副本；原始 `assets/enemy.png` 未改 |
| C6 实机对比 / 回归 / 交付 | ✅ | 同房同状态前后截图、480/960/1440/1920、`run_smoke.bat` 13/13（4872 断言，fails=0），存档已还原 |

---

## 2. 结构性改动

### 2.1 场景 `scenes/ui/battle_hud.tscn`

- **立绘**：`PlayerSprite` 96→48；`EnemySprite` 64→48（纹理改 `enemy_ember.png`）。
- **中央**：`PlayerCenter` / `EnemyCenter` 由 CenterContainer 改为 VBoxContainer（**节点路径不变**，避免大面积改脚本），底部对齐（`alignment=2`），内建立绘 + 实时 HP 行；两个 HP 行同处 y=172。
- **顶栏**：新增 `GoldIcon` + `GoldLabel`（金币移到左侧），`RoomLabel` 改为 `ACT n 主题 · 房 i/N`，`TurnLabel` 保留在右段，删除 `RunLabel` 节点；商店/下一房文案去掉 emoji 并收窄到 54/58。
- **左栏**：`HpRow`（16px hp 图标 + 10px 数值）、`ShieldRow`（16px shield + 9px `盾 N`，无盾隐藏）；`WeaponsRow` 改 GridContainer(2 列)；新增 `GearCards` 承载并排的 `SkillsRow` / `CharmsRow`；消耗品 4 格 34×30，配 1px 紧凑 StyleBox（`sb_cell` / `sb_cell_disabled`）。
- **右栏**：`NameRow`（名称 + 元素）；`HpRow`（hp 图标 + 数值）；`ArmorRow`（armor 图标 + 数值，无甲隐藏）；弱/抗；意图；`ChargeRow`（charge 图标 + 数值，0 充能隐藏）；状态；新增 `EnemyMechanicLabel`（默认隐藏，空值不占位）。
- `load_steps` 同步为 18。

### 2.2 脚本

| 文件 | 改动 |
|---|---|
| `scripts/ui/battle_hud.gd` | `ENEMY_SPRITE_SIZE` 48×48；`DEFAULT_ENEMY_TEXTURE` → `enemy_ember.png`；全部 `@onready` 路径同步新结构；`_refresh_meta()` 写入左右栏图标行、中央 HP、机制摘要、金币；本局加成改挂 `player_buff_label.tooltip_text`；护盾/护甲/充能改为整行显隐 |
| `scripts/ui/player_panel_view.gd` | 新增 `_make_gear_card()`：1px 细框 + 24/16 图标或 emoji + 单行 clip 短名 + 完整 tooltip；武器卡取 `art → icon_tex → emoji`，R2/熟练/铭印进 tooltip；技能/护符各一张主卡，多余条目与技艺进 tooltip；消耗品格改「居中图标 + ×N」，律法锁显示 `⚖N` |
| `scripts/battle/room_data.gd` | 新增纯展示字段 `mechanic_summary`（空 = 不占位），注释说明只影响显示、必须与 `gimmick_params` 一致 |
| `resources/rooms/frozen_urn.tres` | `art_scale` 2.25→2.0；`mechanic_summary = "每3回合\n叠甲+8 · 上限3层\n火系可破"`（与 interval=3 / per_stack=8 / max_stacks=3 一致） |
| `tests/m2_weapon_test.gd` | C2 改动后旧断言（武器行 R 角标、技艺独立图标）失效；按任务书「R/熟练进 tooltip、技艺进 tooltip」改为校验新结构的 tooltip 内容，断言数仍为 41 |
| `tools/ui_capture_step0.gd` | 固定普通房改为**开战后**替换并 `_start_room(0)`（`_confirm_loadout` 会重建 ROOMS）；新增 480×270 原生截图、卡片/方格/HP 行/顶栏/机制一致性日志；转轮取证移到 BOSS 房；截图前收起悬停 tooltip |
| `tools/art_pipeline/make_icons.py` | 按附录 A 重绘 12 枚 16×16 + 6 枚 24×24；脚本内强制校验画布安全区与 ≤3 实体色；输出 1×/2×/4×/剪影/24 卡图 contact sheet |
| `tools/art_pipeline/stylize_sample.py` | 增加 `assets/enemy.png` → `assets/enemy_ember.png`（16×16、EMBER_RAMP、保留 alpha；不覆盖原图） |

未改：伤害/成长/奖励/掉落/房间机制/存档/RNG、`balance_config.tres`、武器与 BOSS 数值、符号与物品数据。

---

## 3. 尺寸与结构实测（`correct1/capture_data.txt`）

```
普通房：玩家 48×48；敌人 48×48（enemy_ember）；art_scale 1.0
BOSS  ：玩家 48×48；冰封铁瓮 96×96；ENEMY_SPRITE_SIZE=(48,48)；art_scale 2.0
左栏宽 88；武器卡 2 张 39×38；技能卡 39×38；护符卡 39×38；消耗品 34×30
中央 HP 行 y：玩家 172 / 敌人 172（同一地面线）
顶栏：ACT 1 冰封 · 房 1/25 | 金币 4 | 回合 1；RunLabel 仍存在=false
左栏弱信息 tooltip：技能: 无 / 本局加成: 无
机制一致性：interval=3 在摘要=true；per_stack=8 在摘要=true；max_stacks=3 在摘要=true
```

前后对照（同一固定普通房 `a1_striker_light.tres`，辉光游侠，HP 100/100）：

| | 纠偏前 `correct0/02` | 纠偏后 `correct1/02` |
|---|---|---|
| 玩家 | 96×96 | 48×48 |
| 普通敌人 | 64×64（旧 `enemy.png`） | 48×48（`enemy_ember.png`） |
| 顶栏 | 房间 / 回合 / 本局加成 | ACT·房 / 金币图标+数值 / 回合 / 商店 / 下一房 |
| 左栏 | 小图标横向小行、34×20 扁消耗品 | 双武器大卡片、技能/护符卡片、34×30 2×2 方格 |
| 右栏 | 纯文字列表 | HP/护甲/充能图标行 + 机制摘要 |
| 中央 | 无 HP | 双方立绘下实时 HP |

BOSS：`correct0/03` 144×144（art_scale 2.25）→ `correct1/03` 96×96（art_scale 2.0）；比例恒为玩家 1:2。

---

## 4. 图标附录 A 验收

- 文件：`assets/icons/16/{hp,shield,armor,gold,fire_slash,burn,axe_slash,fire_sword,battle_axe,potion,charge,star}.png`（16×16 RGBA，主体限制 x=2…13 / y=1…14，四周透明）；`assets/icons/24/{fire_sword,battle_axe,hp,shield,gold,potion}.png`（16 主体原尺寸居中，不拉伸）。
- 每枚 ≤3 实体色（实测：1–3 色），仅使用附录指定色板与同族暗阶，无半透明过渡像素、无抗锯齿。
- 逐图标造型：心形/平顶盾/肩甲/阶梯方孔金币/对角剑与斧/错峰火焰+金芯/短盖窄颈方瓶/折线闪电/四角星，均按 A.3 制作。
- contact sheet：`docs/baseline/2026-10-31_ui/correct1/icon_contact_sheet.png`，含 1×、2×、4×、纯黑剪影与 24 卡图；剪影下剑/斧、火焰/药剂、护盾/金币可区分。
- 使用面：转轮（金币/火斩/灼烧/斧斩）、左栏武器卡（24）、右栏 HP/护甲/充能、顶栏金币、奖励卡（24 hp/shield/gold）。
- 图标未被元素色条/角标遮挡：元素条固定在格底 2px，16px 图标垂直居中不重叠。

---

## 5. 自动回归（本次实跑）

`run_smoke.bat`：**13/13 ALL GREEN，exit 0**。

| 套件 | 断言 |
|---|---|
| 1/13 L0 intent act-gating | PASSED 42 / FAILED 0 |
| 2/13 L0 boss loot theme | PASSED 234 / FAILED 0 |
| 3/13 L1 content math lint | PASSED 393 / FAILED 0 |
| 4/13 L2+L3 full-run | `SMOKE|RESULT PASS (checks=3863 fails=0)` |
| 5/13 T8 drops | PASSED 20 / FAILED 0 |
| 6/13 T7 acquisition | PASSED 10 / FAILED 0 |
| 7/13 curriculum | PASSED 99 / FAILED 0 |
| 8/13 charge gating | PASSED 8 / FAILED 0 |
| 9/13 M1 reward suite | PASSED 51 / FAILED 0 |
| 10/13 M2 growth | PASSED 51 / FAILED 0 |
| 11/13 M2 weapon mastery | PASSED 41 / FAILED 0 |
| 12/13 M3 binding | PASSED 12 / FAILED 0 |
| 13/13 M4 demo config | PASSED 48 / FAILED 0 |

合计 **4872 断言，0 失败**。副作用：整局 smoke 改写 `anvil_points`；已用 `$TEMP\lobby_data.bak_correct.json` 还原，SHA-256 与运行前一致（`D75508FC…0665A`）。

---

## 6. 硬门槛核对

- [x] 玩家 48×48、冰封铁瓮 96×96，整数倍率
- [x] 双武器为大图标槽位（39×38，24 art）
- [x] 消耗品为 2×2 方格（34×30）而非扁按钮
- [x] 顶栏为房间/金币/回合/商店/下一房，无旧「本局加成」主信息位
- [x] 右侧有 HP、护甲、充能图标化信息
- [x] 玩家与 BOSS 下方有实时 HP（同一刷新入口、同一地面线）
- [x] 冰封铁瓮摘要与真实机制一致（interval 3 / 叠甲 8 / 上限 3 层）
- [x] 普通敌人已红色风格化（`enemy_ember.png`）
- [x] 全部样板图标符合附录 A 画布/色数/造型/contact sheet
- [x] 480×270 无重叠、裁切和非预期滚动（`02b_battle_480` / `03b_boss_480`）
- [x] 自动回归实际通过（13/13，4872 断言）

---

## 7. 已知剩余差异 / 未验证项

1. **图标覆盖面**：仅样板资源有图标；其余武器、技能、消耗品仍按 emoji 回落（24 武器中仅火焰剑/战斧有 art；消耗品均无 `icon_tex`）。本任务按边界不批量铺量。
2. **技能/护符次要条目**：主技能/主护符各一张卡，其余条目与技艺按要求并入 tooltip；截图中看不到逐一图标，需悬停查看。
3. **商店抽屉仍压住左栏右半**：`04_shop_960.png` 可见，Step 5 前即存在，属抽屉宽度设计，未在本轮改动。
4. **奖励卡文字换行偏多**：`14_reward_icons_960.png`，Step 4/5 记录一致，未处理。
5. **顶栏房号是整局序列**（1/25），目标图示例为单幕 3/8；按任务书保留真实数据，未伪造 8 房分母。
6. **F6 人肉项未验证**：悬停 tooltip 在 480×270 的可读性、48px 立绘在真实连击/核爆演出中的观感、商店/铁砧/整备的完整点击路径（本轮只截图与自动回归）。
7. **底部反馈取证**：`17_feedback_960` 为治疗回合「治疗×2 / -15」；连击 + 克制 + 伤害的完整样例在 `19_counter_feedback_960`（「燃×2 / 克制×1.5 / -81」，同帧可见 ×2 角标、充能 1/6 与核爆大字淡出）。
8. **律法锁格（⚖N）未在本次截图状态中出现**：本次两个固定房的敌人不触发锁槽；锁定分支只做了代码路径检查，未做视觉取证。
