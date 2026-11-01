# 战斗 UI 重构 · Step 4 武器与转轮图标样板（2026-10-31）

> 依据：`docs/战斗UI重构_执行方案与AI任务书.md` §6 Step 4
> 范围：只做样板图标（火焰剑 / 战斧 / 火斩 / 灼烧 / 金币 + 基础语义），只绑定个别资源；不改战斗数值、不改数据字段
> 截图：`docs/baseline/2026-10-31_ui/step4/`（同工具、同流程；新增 12–16 号取证图）
> 原则：缺图标一律回落原有 emoji/文本，`icon_tex` / `art` 为空即旧表现

---

## 1. 任务书条目对照

| 任务书 Step 4 条目 | 处理 |
|---|---|
| ① 少量图标：火焰剑/战斧/攻击/火焰 + HP/护盾/金币/护甲/充能 | 16×16 手绘 **10 枚**：`fire_slash`(火斩) `burn`(灼烧) `axe_slash`(斧斩) `fire_sword` `battle_axe` `hp` `shield` `gold` `armor` `charge` |
| ② 卡片主图 24×24 或 48×48；转轮图标必须独立 16×16 | 转轮/左栏用 **16×16**；卡片主图 **24×24**（16px 图标居中 + 1px 深描边框），**未做任何缩放**（16→24 与 48→16 都只做排布，不做插值） |
| ③ 不将 48×48 主图直接缩成 16×16 | 16 与 24 两套均为独立手绘；24 版由 16 版**原尺寸居中 + 外框**组成，不是拉伸 |
| ④ 通用 `art/icon` 绑定，不引入武器小人与动画字段 | 复用既有 `SymbolData.icon_tex` / `LoadoutItem.icon_tex` / `LoadoutItem.art` / `RewardData.art`，零新增字段 |
| ⑤ 复用 `ItemCard.set_art()`；无图保持 emoji 回落 | `ItemCard.set_art()` 增加可选 `min_size`（默认仍是 48）；奖励卡 24px 图格走该接口；`MISS` 符号、无图消耗品、无图武器全部保持旧 emoji/文本 |
| ⑥ 转轮新增图标时保留角标/元素色/锁轮/冻结/tooltip | 角标未动（`16_badges_960` 实测 ×2 与图标不重叠）；**元素色改由格底 2px 色条表达**（见 §5）；冻结/干扰/锁轮 3px 边框与 tooltip 未动 |
| ⑦ 只做样板绑定，不批量替换 | 绑定 4 个符号 + 2 把武器 + 3 个奖励类型；其余 44 个符号、22 把武器、其余奖励仍为旧表现 |

## 2. 新增资源

| 文件 | 规格 | 用途 |
|---|---|---|
| `assets/icons/16/fire_slash.png` | 16×16 | 转轮符号·火斩 |
| `assets/icons/16/burn.png` | 16×16 | 转轮符号·灼烧 |
| `assets/icons/16/axe_slash.png` | 16×16 | 转轮符号·斧斩 |
| `assets/icons/16/gold.png` | 16×16 | 转轮符号·金币 |
| `assets/icons/16/fire_sword.png` | 16×16 | 左栏武器·火焰剑 |
| `assets/icons/16/battle_axe.png` | 16×16 | 左栏武器·战斧 |
| `assets/icons/16/hp.png` `shield.png` `armor.png` `charge.png` | 16×16 | 基础语义（HP/护盾/护甲/充能）；**当前仅备料，尚未绑定到标签**（见 §7） |
| `assets/icons/24/fire_sword.png` `battle_axe.png` `hp.png` `shield.png` `gold.png` | 24×24 | 卡片主图 |

生成脚本：`tools/art_pipeline/make_icons.py`（字符网格 → PNG，确定性输出）。

图标配色只用任务书色板 + 每色相 1 个暗阶：

| 语义 | 亮/主 | 暗阶 |
|---|---|---|
| 暖白/次级/弱/深线 | `#E2D7BD` / `#A99D89` / `#6E5F57` / `#3A222B` | — |
| 敌人红 | `#E35B50` | `#8C3438`（色板自带） |
| 交互金 | `#D5A33D` | `#8C6A24` |
| 生命绿 | `#A4BC4D` | `#6E8230` |
| 护盾蓝 | `#62A1C2` | `#37617A` |

## 3. 数据绑定（只这 9 个资源）

| 资源 | 字段 | 值 |
|---|---|---|
| `resources/symbols/fire_slash.tres` | `icon_tex` | `icons/16/fire_slash.png` |
| `resources/symbols/burn.tres` | `icon_tex` | `icons/16/burn.png` |
| `resources/symbols/axe_slash.tres` | `icon_tex` | `icons/16/axe_slash.png` |
| `resources/symbols/gold.tres` | `icon_tex` | `icons/16/gold.png` |
| `resources/weapon_templates/fire_sword.tres` | `icon_tex` / `art` | `icons/16/fire_sword.png` / `icons/24/fire_sword.png` |
| `resources/weapon_templates/battle_axe.tres` | `icon_tex` / `art` | `icons/16/battle_axe.png` / `icons/24/battle_axe.png` |
| `resources/rewards/heal.tres` | `art` | `icons/24/hp.png` |
| `resources/rewards/shield.tres` | `art` | `icons/24/shield.png` |
| `resources/rewards/gold.tres` | `art` | `icons/24/gold.png` |

## 4. 代码改动

| 文件 | 改动 |
|---|---|
| `scripts/ui/battle_hud.gd` | ① 转轮格新增 `ElemStrip`（格底 2px 元素色条，`_refresh_cell` 内按有效元素显隐）；② 奖励卡主图优先取候选物品自身 `art`/`icon_tex`，其次 `rw.art`；③ 有主图时不重复显示 emoji 前缀；④ 奖励卡最小尺寸 84×60 → **84×84**（24 图 + 标题 + 描述会顶出原卡片）；⑤ `_cell_element()` 改读实时 `controller.grid_elem` |
| `scripts/ui/player_panel_view.gd` | 武器图标分支补回元素小字：旧 emoji 回落是「🗡️ + 元素 emoji」，换图标后元素信息会丢失，现为「图标 + 元素 emoji + R 角标」 |
| `scripts/ui/item_card.gd` | `set_art(tex, min_size := Vector2(48,48))`——图格尺寸可调，图本身仍 1:1 居中不放大 |
| `scenes/ui/symbol_cell.tscn` | 根 Button `icon_alignment = 1`（图标居中）；主题新增 `Button/colors/icon_disabled_color = 白`（格子恒为 disabled，默认 40% 透明会把图标压暗） |
| `tools/ui_capture_step0.gd` | 新增 Step 4 取证截图（12/13/14/15/16）与元素条/角标日志 |

未改：`combat_system.gd`、`balance_config.tres`、任何战斗/成长/奖励逻辑；未新增数据字段；未改冻结/干扰/锁轮边框与 tooltip。

## 5. 元素色为何改为格底色条

原实现用 **文字颜色** 表达「有效元素」（`font_color = 符号色 lerp 元素色 0.55`）。图标模式没有文字可染，元素色会直接丢失。
新增格底 2px 色条（距左右各 4px、贴下边框上方），颜色取 `ElementCounter.color(elem)`，`elem == "none"` 时隐藏：

- 实测（`03_boss_960` 日志）：火元素格 `visible=true color=(1.0,0.45,0.2)`；金币符号 `visible=false`。
- 不占用图标区域（图标垂直中心 y13–29，色条 y40–42），不与右上角标（y2–18）重叠。

顺带修掉一个既有缺陷：`_cell_element()` 原先读只读快照 `state.grid_elem`，而 `reset_grid()` / `lock_reel()` 都是**先写数据再刷新格子、最后才 `invalidate_state()`**，导致房间开场的元素色落后一步（实测：格子已有图标但色条全 false）。改读实时 `controller.grid_elem` 后与写方顺序一致，tooltip 的元素判断同时受益。

## 6. 实机取证（480×270）

| 截图 | 内容 |
|---|---|
| `02_battle_960.png` | 普通房：金币图标 + 火斩图标 + `MISS` 文本（回落仍在）；火斩格底部橙色元素条 |
| `03_boss_960.png` | BOSS 房：火斩 / 金币 / 灼烧 三枚图标；两个火系格带橙色条 |
| `16_badges_960.png` | 真实旋转后出现 `×2` 匹配角标：角标在右上角，与金币图标不重叠（日志「匹配角标：×2」） |
| `14_reward_icons_960.png` | 奖励卡 24px 主图：生命（心）/ 护盾 / 金币；有图时不再叠加 emoji 前缀，文字不越出卡片 |
| `15_after_spin_960.png` | 逐列按停后的静止画面（图标 + 色条同时在场） |
| `08_spin_960.png` / `08b_spin_960.png` | 滚动条内同样是 16px 图标（`reel_spin_view` 既有 `sym.icon_tex` 分支） |

## 7. 回归结果

`run_smoke.bat`：**13/13 ALL GREEN，exit 0**

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

合计 4872 条断言，0 失败，与 Step 0–3 逐套一致。
副作用同前：整局 smoke 改写 `anvil_points`（6899 → 7320），已备份并还原（哈希一致）。

## 8. 已知遗留

- **图标与 emoji 混排尺寸不一致**：图标固定 16×16，emoji 字形约 16×14–18，但 emoji 是满色块，观感更大。全量符号都有图标后自然统一（本次只做样板）。
- **HP/护盾/护甲/充能 16px 图标已产出但未绑定**：左栏 HP/护盾仍为文本 + 水滴 emoji，右栏护甲/充能为文本；绑定它们需要改标签节点结构（Step 5 信息层级）。
- **奖励卡文字换行仍偏多**：卡片宽 84、内容区约 64px，"恢复 35% 最大 HP" 仍换 4 行；消耗品长描述会横向越出卡片（**Step 4 之前就存在**，非本次引入）。属 Step 5 细节收敛。
- **斧类图标辨识度一般**：16px 下单刃斧头易被读成锤，已用「头偏右 + 刃口在右」缓解；若后续要正式化建议按武器类别重绘。
- 普通敌人立绘仍是旧素材（Step 3 遗留）。
