# Seek Dead — 游戏总览（面向 AI 的实现级说明）

> **用途**：让 AI 快速理解"这游戏怎么玩、有什么内容、代码在哪"，以便后续开发/修改。
> **权威性**：本文**以当前代码为准**（2026-11-18 核对）。`docs/游戏策划总纲.md` 等多份旧文档顶部已标注"部分过期"，
> 凡与本文冲突处，以本文标注的代码位置为准。本文刻意不重复长篇设计论证，只给可验证的事实与导航。
> **引擎**：Godot 4.7 / GDScript，纯代码 + `.tres` Resource 驱动，`E:\YID\seek_dead`。

---

## 1. 一句话概念

**老虎机当作武器地牢射击游戏**：玩家没有枪，手里是一台老虎机。转轮停下的符号就是这一发"弹药"，
带什么武器决定转轮带里有什么符号，元素克制决定打出去是 ×1.5 弱点爆发还是 ×0.85 被抗。
缝合「挺进地牢的 Roguelike 骨架」+「小丑牌的乘区爆炸与可读分解」+「真人老虎机的手动按停技巧」。

- 核心幻想：转轮就是你的枪，连线就是你的暴击。
- 设计诉求（用户拍板）：① 数值爆炸的爽感；② 玩法和计算不要过于复杂。
- 类型：回合制、单赔付线（3 列 × 1 行）、Roguelike 地牢。玩法分三层：
  **build 层（带什么）→ 技巧层（停得准不准）→ 结算层（大数字拆给你看）**。

---

## 2. 一局是怎么跑的（宏观流程）

```
整备 Loadout（选武器/技能/护符/消耗品）
   ↓
进入地牢：默认线性 3 幕 × 8 房 = 24 房，追加真·最终 BOSS = 25 房
   （另有 14×9 地图巡逻模式，board_system.enabled 控制，默认 false 走线性）
   ↓
每房：战斗 → 胜利结算 → 战利品三选一 → 商店 → 下一房
   ↓
每 8 房一幕：幕间锻魂（本局符号伤害 +8 / 最大 HP +20）
   ↓
通关真·最终 BOSS（hero_shadow，final_boss=true）
   ↓
局末结算 → 铁砧点 → 回整备开新局
```

- 一局结构常量：`resources/config/balance_config.tres:35-38`
  - `run_acts=3`，`run_act_layout=[normal,normal,normal,elite,normal,normal,elite,boss]`（8 房/幕）
  - `run_include_final_boss=true`（再 +1 房）
- 房间 `.tres` 池 61 个：36 普通 + 12 精英 + 13 BOSS（`resources/rooms/`）。每局按幕抽取。
- 单局时长目标 ~45–55 分钟（旧数据，未实测核实）。

**关卡组织两套并存**：
1. **线性**（默认）：`scripts/battle/run_setup.gd:21-54` 按布局数组排房。
2. **地图巡逻诱导**（11 月新系统，默认关）：14×9=126 格网格，玩家点 4 邻可行走格移动，
   踩战斗节点或撞巡逻怪触发战斗，有破甲陷阱、奖励格、武器藏库等。
   - 网格 `scripts/board/map_grid.gd:20-22`；三幕布局 `:52-76`；运行时 `map_runtime.gd`。
   - 门面 `board_system.gd:80-112`，`enabled` 切换，默认走线性。

---

## 3. 战斗：一回合到底发生什么

### 3.1 状态机与回合流程
- 全局 FlowState 只有 3 态：`PLAYING / WON / LOST`（`duel_controller.gd:298`）。
- 回合阶段在 `turn_flow.gd`：
  1. **回合开始** `begin_player_turn`：持续效果衰减 → 敌人声明意图 → gimmick 回合钩子 → 冻结列声明。
  2. **SPIN** `on_spin_pressed`（`:77`）：`reel_system.begin_spin()` → await `spin_finished`。
  3. **闪回暴走**：某些 BOSS/效果强制免费重转（`:85-90`）。
  4. **结算** `combat.evaluate()`（`:92`）：凑牌匹配 + 伤害计算。
  5. **DoT + 敌人行动**（`:105-116`）。
  6. **胜负判定** → 胜则 `hud._show_reward_screen(is_boss)`。
- 数值全部在 `combat_system.gd`；`duel_controller` 只做编排。

### 3.2 转轮机制（`reel_system.gd`）
- `REELS=3, ROWS=1`（`duel_controller.gd:78-79`），仅 1 条 payline 的三格。
- 建带 `build_strips`（`:252`）：按符号族聚合权重 → 展开成格子（权重 ≥4→4 格、≥2→3 格、否则 2 格，`:374-380`），
  最小 30 格（`:29`），金币符号常驻 2 格（`:30`），3 列各自洗牌副本（`:320-327`）。
- 按停：空格键逐列 / 点击单列，取视觉中心（`:494-514`）+ 一拍输入缓冲，0.16–0.20s 吸附后落子（`:552-594`）。
  **无自动停止**——不停就一直转；难度来自转速越来越快 + 眼力手速 = "目押"技巧。

### 3.3 转轮凑牌系统（11 月新核心，与旧"三连计数"并存）
- 牌谱数据 `pattern_data.gd`：字段 kind / track（weapon_public、weapon_attack、skill_support）/
  pattern_tier / pattern_paths / match_rule / effect_id / sequence_id 等（`:14-46`）。
- 匹配 `pattern_matcher.gd`：通用牌谱 **G01 同源刻 / G02 同族刻 / G03 清一色**（`:38`），
  回溯求解把三张牌分配到条件（`:96-113`）；G04 顺子**只有字段、未实装**。
- 每轨最多命中一条牌谱，按 priority 降序 / id 升序（`pattern_system.gd:71`）。
- 资源仅 21 个牌谱（`resources/patterns/`）：W01-06、T01-03、S02、11 个 signature。
  G01-03 硬编码无资源。
- **与旧结算的关系**：旧的"同源三连取武器专精、同族三连 ×1.5"仍在（`combat_system.gd:90-98`），
  牌谱是叠加其上的一层（`:358 _apply_patterns`），两者并存。

### 3.4 伤害公式（`scripts/battle/combat_system.gd`，非 battle_math）
- 单符号：`dv = flat × 连线格数 × 元素倍率 × 暴击`（`:109`），
  `flat = 武器 power + 聚合 flat`（`:70`）。
- 回合级乘区（`:604-605`）：
  `(基础伤害 + special) × 强袭 × (护符/增益 damage_mult) × player_dmg_mult × 虚弱 × 镜面`
  （`battle_math.gd` 仅做聚合，`:26/:59`）。
- 元素克制（`element_counter.gd:24-47`）：火→冰/毒、冰→火、毒→暗、光→暗/毒、暗→光；
  **克制 ×1.5 / 抵抗或同元素 ×0.85 / 中性 ×1.0**。
- 护甲（`:977`）：非穿透先破甲后掉血，穿透直击 HP；破甲三连清甲 + 核爆 12.5% 最大 HP（`:994-1005`）。

> ⚠ **旧文档过期点**：`TEST_PLAYER_DMG_MULT`、`CHAIN_STEP`、`CHAIN_MAX` 在代码中**不存在**（仅见于
> `docs/游戏策划总纲.md`）。连锁重转已删除（`combat_system.gd:217 chain_mult 退役`）。
> `player_dmg_mult=1.5` 仍在，但已是正式常量而非"测试倍率"。

---

## 4. 装备与 Build（决定转轮带里有什么）

| 类别 | 数据类 | 槽位上限 | 进转轮池？ | 作用 |
|---|---|---|---|---|
| 武器 | `WeaponData`（`scripts/equipment/weapon_data.gd`） | 2（主+副，`loadout_system.gd:68`） | ✅ | 符号容器 `symbols:Array[SymbolWeight]`，带元素 |
| 技能 | `SkillData`（`scripts/items/skill_data.gd`） | 3（`:69`） | ✅ | 单个符号 `symbol+weight` |
| 护符 | `ItemData.category=passive` | 3（`CHARM_CAP`，`duel_controller.gd:69`） | ❌ | 全局乘区 `damage_mult`，唯一收集乘区 |
| 消耗品 | `ItemData.category=active` | 腰带 4（`CONSUMABLE_CAP`，`:68`），勾选 1 | ❌ | 可消耗资源 |

- **护符/消耗品已无独立类**，统一为 `ItemData`（`scripts/items/item_data.gd:4-6`）。
  符号直接以 Resource 引用挂在武器/技能上，无全局注册表。
- 多带武器/技能的代价：符号密度被稀释、目标符号难按停、克制乘区吃不满（"带得少反而好打"）。
- 常量：`CHARM_CAP=3`、`CONSUMABLE_CAP=4`（`duel_controller.gd:68-69`）。

---

## 5. 战后三选一（胜利后拿什么）

**两套并存**，分叉在 `battle_hud.gd:738 _show_reward_screen(is_boss)`：

| 房间 | 系统 | 内容 |
|---|---|---|
| 普通 / 精英 | `GrowthLootOffer`（Step 7 成长三选一） | 武器训练 / 符号灌注 / 技艺 / 待选成长 / 最大 HP / 护盾 / 回血 |
| BOSS | `roll_boss_rewards`（旧专属屏） | 主题武器（≤3）+ Boss 信物 + 铁砧结晶兜底 |

- 品质来源表 `loot_source_weights`（`balance_config.tres:42`）：
  normal 70/25/5/0、elite 20/50/27/3、boss 0/10/60/30、chest 35/40/22/3。
- 精英房额外必掉"精简剪"（`room_flow.gd:23-40`）。
- 详细内容见 `docs/战后三选一内容总览_2026-11-18.md`。

---

## 6. 成长与经济

- **历练/技艺** `growth_system.gd`：房胜经验 1/2/3，等级门槛 3/7/12/20/30（Lv6 满，`:11-32`）；
  Lv2/4/6 各一次技艺三选一；技艺池 8 项（`PERKS`：坚韧/守势/备用药剂/回春/积蓄/落点吸附/宽判窗口/废铁豁免）。
- **熟练/铭印** `weapon_mastery.gd`：R1–R4，门槛 3/7/12；R2/R3 欠铭印，
  铭印 4 种：锋铸(forge)/调律(tune)/校准(calibrate)/暴虐(tyrant)（`:13-32`）。
- **金币**：起始 4，每局清零；来源清房 +5 / BOSS +10 + 利息（每 5 金 +1，上限 5）。
- **商店** `shop_screen.gd`：仅 **2 页签**（购入 / 卖出），升级页已迁出为 BOSS 战后训练房（`:35-37`）。
- **铁砧点**：跨局 gacha 货币，10 点/抽、保底 10（`anvil_system.gd:33-44`）；drip 来源精英 3 / BOSS 5 / 终战 8，上限 40。
- **元进度**：`meta_store.gd`（跨局存档、初始收藏、脏数据自愈）；`anvil_system.gd`（gacha/图鉴里程碑）。
  通关三选一**已退化为仅铁砧点数**（`reward_system.gd:56-70`）。

> ⚠ **旧文档过期点**：总纲 §8 的"武器 base / 护符 mult 双轨元进度"已不存在；商店非三页签。

---

## 7. BOSS 机制

- 基类 `boss_gimmick.gd`，钩子：`on_room_start / on_turn_begin / on_damaged / on_special_triple`。
- 具体实现在 `scripts/battle/gimmicks/`（约 18 个）：锈蚀护甲、深渊侵蚀、茧居循环、双相、玻璃大炮、
  镜面投影、终局守望者等。普通怪也用 `normal_trait_gimmick.gd` 挂个性机制。
- BOSS 主题池品质补齐见 `resources/rooms/*.tres` 的 `boss_reward_weapons` / `boss_relic_path` / `final_boss` 字段。
- 真·最终 BOSS = `hero_shadow.tres`（`final_boss=true`），绑定末幕 BOSS。

---

## 8. 内容量（resources/ 下 .tres 计数，2026-11-18 实测）

| 目录 | 数量 | 目录 | 数量 |
|---|---|---|---|
| `weapon_templates/` | 90 | `symbols/` | 76 |
| `charms/` | 45 | `skills/` | 40 |
| `consumables/` | 26 | `rooms/` | 61 |
| `archetypes/` | 15 | `patterns/` | 21 |
| `intents/` | 6 | `statuses/` | 4 |
| `synergies/` | 3 | `rewards/` | 9（+ elite/3） |

> 注意：武器 `.tres` 在 `weapon_templates/`，**没有 `weapons/` 目录**。

---

## 9. 技术架构与重要铁律（改代码前必读）

- **数据即 Resource**：符号/物品/房间 = `.tres`，`@export` 直接引用；加内容 = 新建 `.tres`，不改代码、不碰全局注册表。
  目录扫描发现 `resource_scan.gd`。
- **表现/逻辑分离**：`duel_controller` 纯逻辑编排，`battle_hud` 纯 UI；经只读快照 `BattleState` + 信号单向驱动。
- **纯结算抽离** `battle_math.gd`（全 static，不碰节点）。
- **拆分中**：`duel_controller` 正在拆成 RefCounted 子系统（MetaStore / AnvilSystem 已完成，Shop/Reward/Loadout 待办）；
  子系统 `_init(ctrl)` 注入、不持有 meta，每步单独 commit + F6。
- 🔴 **战斗演出不得消耗全局 RNG**：用 `RandomNumberGenerator` 实例 / `Px.Rng`，禁 `randf()`。
- 🔴 **扫 `res://` 目录必须用 `ResourceLoader.list_directory`**，禁 `DirAccess.get_files()`（导出后 PCK 里会扫空）。
- 🔴 **九宫格 margin**：判据是"内腔整体等于背景色"，金雕花框实测最小干净 margin=15（现用 10 会漏花）。详见 `docs/UI资源_风格兼容评估_2026-11-17.md` §8。
- 复古掌机 UI：viewport 480×270 + nearest + 像素字 VonwaonBitmap→zpix，TypeScale 9–13px；改尺寸须同步所有 tscn/gd 字面值。
- 特效一律走 `pixelfx-godot` skill（vendor 在 `.workbuddy/vendor/pixelfx-godot-main`），烘焙优先。

---

## 10. 代码导航（改哪类需求看哪个文件）

| 需求 | 文件 |
|---|---|
| 战斗回合流程 / 胜负 | `scripts/battle/turn_flow.gd`、`duel_controller.gd` |
| 转轮旋转 / 按停 / 建带 | `scripts/battle/reel_system.gd` |
| 伤害 / 结算 / 凑牌效果 | `scripts/battle/combat_system.gd`、`scripts/battle/battle_math.gd` |
| 牌谱定义 / 匹配 | `scripts/battle/pattern_data.gd`、`pattern_matcher.gd`、`pattern_system.gd` |
| 元素克制 | `scripts/battle/element_counter.gd` |
| 房间 / 一局结构 | `scripts/battle/run_setup.gd`、`room_data.gd`、`room_flow.gd` |
| 地牢地图 | `scripts/board/map_*.gd`（grid / runtime / patrol / trap / reward / progress / board_builder） |
| 装备 / 槽位 | `scripts/systems/loadout_system.gd`、`scripts/equipment/`、`scripts/items/` |
| 成长 / 铭印 / 技艺 | `scripts/systems/{weapon_mastery,growth_system}.gd` |
| 战利品三选一 | `scripts/systems/{reward_system,loot_offer,growth_loot_offer}.gd`、`scripts/battle/room_flow.gd` |
| 商店 / 铁砧 / 存档 | `scripts/systems/{shop_system,anvil_system,meta_store}.gd` |
| BOSS 机制 | `scripts/battle/gimmicks/`、`boss_gimmick.gd` |
| HUD / 覆盖层 UI | `scripts/ui/battle_hud.gd` + `scenes/ui/*.tscn`、`card_factory.gd` |
| 数据定义 | `scripts/items/*.gd`（RewardData 等）、`resources/` 各目录 |

---

## 11. 当前未完成 / 待办（供 AI 接手时留意）

- 用户手动 F6 真机验证（AI 不跑无头，除字体/解析诊断）；Godot 路径 `D:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe`。
- `duel_controller` 子系统拆分收尾（Shop/Reward/Loadout）。
- 地图巡逻模式默认关闭，需与线性模式做取舍/验收。
- 四个覆盖层（reward/shop/anvil/loadout）面板仍是代码 `StyleBoxFlat` 灰框，未换 UI 皮。
- `REEL_SLOT_X` 在当前新转轮结构下是否仍出框，需重新核对（旧坐标偏差记录已随 38fd080 重构失效）。
- 多份旧 docs 与代码冲突（总纲、公式速查等），修改相关系统时以代码为准，必要时更新对应文档。
