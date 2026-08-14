# BOSS 机制扩展指南

> 状态：2026-08-14 修订（对齐 T20 intents / T24 gimmick_params / T10 13 BOSS 现状，旧版扁平字段示例已废弃）。
> 本文档面向「想自己新增 / 修改 BOSS 机制」的开发者，描述基于 `current_gimmick` 钩子系统的数据驱动扩展方式。
> 配套设计见 `BOSS设计规范.md`（规范总纲）与 `数值膨胀与策略深度设计框架.md`（数值基线）。

---

## 0. 核心结论

新增一个 BOSS **几乎不需要改动核心战斗代码**。整套机制是数据驱动的：

- 每间 BOSS 房在 `RoomData` 里用 `gimmick_script`（Script）字段指向一个机制脚本，数值参数全进 `gimmick_params`（Dictionary，T24）；
- `duel_controller._start_room` 进房时自动 `r.gimmick_script.new()` 实例化并赋值 `current_gimmick`，随后调用 `on_room_start`（duel_controller.gd:955-957）；
- 之后每个回合 / 事件自动回调 **7 个钩子**；非 BOSS 房一律跳过（调用处均已显式 `!= null` 判空，不会崩）。

因此「加 BOSS」= **写一个脚本 + 给房间 `.tres` 挂上它 + 把 `.tres` 丢进 `resources/rooms/`**。`ResourceScan` 自动扫描该目录收集房间，无需登记到任何数组 / 字典；`_build_run`（duel_controller.gd:836）按 act/kind 抽房，BOSS 槽从本幕候选池按 `boss_role` 加权抽 1（fixed 6 / rotating 3 / hidden 2，见 `BALANCE.run_boss_weights`）。

---

## 1. 文件清单

| 文件 | 作用 |
|---|---|
| `scripts/battle/gimmicks/boss_gimmick.gd` | BOSS 机制基类（7 个空钩子，必须 `extends` 它） |
| `scripts/battle/gimmicks/*.gd` | 13 个 BOSS 机制实现（速查见 §8；`cocoon_sentinel_gimmick.gd` = 茧居 v1 保留回退版，未被引用） |
| `scripts/battle/room_data.gd` | 房间数据（字段全集见 §3 步骤②） |
| `scripts/battle/intent_data.gd` | 意图定义（`id/display_name/icon/desc/weight/purifiable/value_mult/duration`） |
| `scripts/battle/duel_controller.gd` | 战斗核心（接线点见 §2，正常不用改） |
| `scripts/battle/combat_system.gd` | 结算核心（`evaluate`：三连 / 伤害 / `on_damaged` / `on_turn_resolved` 钩子点） |
| `scripts/battle/enemy_system.gd` | 敌人行动（`take_turn`：意图执行，经 `combat.enemy_deal_damage` 应用 `boss_atk_mult`） |
| `scripts/systems/consumable_system.gd` | 消耗品使用（`on_consumable_used` 钩子点） |
| `scripts/battle/status_system.gd` | 意图抽取（`roll_intent`：房间表 → archetype 表 → kind 默认表，见 §3 步骤②） |
| `scripts/battle/reel_system.gd` | 转轮带构建（`boss_trash` 废铁落实点） |
| `resources/rooms/*.tres` | 房间数据（BOSS 共 13 间） |
| `resources/intents/*.tres` | 共享意图（attack/heavy/jam/lock/chaos） |

---

## 2. 核心架构

```
RoomData (.tres)
  ├─ gimmick_script: Script      ──→  BossGimmick 子类实例 = current_gimmick
  └─ gimmick_params: Dictionary  ──→  on_room_start 里 p.get(key, 默认)（T24 调参零代码）

duel_controller 生命周期：
  _start_room(idx)                          duel_controller.gd:894
    ├─ current_gimmick = null               :952
    ├─ if kind=="boss" 且 gimmick_script != null:
    │     current_gimmick = r.gimmick_script.new()    :956
    │     current_gimmick.on_room_start(self)         :957
    └─ _begin_player_turn()                  :958

  _begin_player_turn()                      duel_controller.gd:981
    ├─ boss_atk_mult = 1.0                 :998   ← 每回合重置（见 §5 坑①）
    └─ current_gimmick?.on_turn_begin(self) :999-1000

  _on_spin_pressed()（停轮后、结算前）        duel_controller.gd:1035 / :1044
    └─ current_gimmick?.consume_flashback()  → true 则本次停轮作废、强制免费重转

  combat.evaluate()                        combat_system.gd
    ├─ 任意三连: on_special_triple(_ctrl)   :230-231
    ├─ 先破甲后掉血（apply_enemy_damage）    :276/278
    ├─ 敌人受伤: on_damaged(_ctrl, total)   :280-281
    └─ 结算后: on_turn_resolved(_ctrl)      :300-301（敌人行动前；空转/MISS 也触发）

  敌人行动  enemy_system.take_turn()        enemy_system.gd:21 → combat.enemy_deal_damage
    └─ eff = raw × boss_atk_mult            combat_system.gd:389-393

  消耗品使用  consumable_system.use()       consumable_system.gd:48-49
    └─ current_gimmick?.on_consumable_used(_ctrl, effect)

  转轮带构建  reel_system.build_strips()    reel_system.gd:161（注入 boss_trash 废铁格）
```

---

## 3. 新建一个全新 BOSS（3 步）

### 步骤① 写机制脚本

新建 `scripts/battle/gimmicks/你的_boss_gimmick.gd`：

```gdscript
extends BossGimmick

const ICON := "🔮"   # 下一房预告横幅的机制图标（battle_hud 经 get_script_constant_map 读取）

# 只覆写需要的钩子；不用的钩子不写即可（基类是空 pass）。
# 参数 ctrl = DuelController 实例，动态访问，不要给 ctrl 标类型。
# T24：数值参数一律在 on_room_start 从 gimmick_params 读取（p.get(key, 默认)），
#       不要在脚本顶部写 const 常量；参数缺省 = 默认行为（教学位回归）。

var _amount := 8

func on_room_start(ctrl) -> void:
    var p: Dictionary = ctrl.ROOMS[ctrl.room_index].gimmick_params if (ctrl.room_index >= 0 and ctrl.room_index < ctrl.ROOMS.size()) else {}
    _amount = int(p.get("amount", 8))
    ctrl.hud._log("🔮 我的 BOSS 登场")

func on_turn_begin(ctrl) -> void:
    # 例：每回合给敌人叠护甲（敌人护甲是扁平池，先破甲后掉血；增/减都在 enemy_armor / enemy_armor_max 上操作）
    ctrl.enemy_armor_max += _amount
    ctrl.enemy_armor += _amount

func on_damaged(ctrl, dmg: int) -> void:
    pass
```

要点：
- 只在 `on_turn_begin` 里设置 `boss_atk_mult`（在 `on_room_start` 设的会被回合开始重置，见 §5 坑①）。
- 阶段切换用 `on_damaged` 阈值一次性触发（标准写法见 §5 坑③）。
- `on_room_start` 的标准参数读取写法见上方（`ctrl.ROOMS[ctrl.room_index].gimmick_params`，带越界兜底）。

### 步骤② 给房间 `.tres` 挂脚本

参考 `resources/rooms/grand_inquisitor.tres` 的实际结构。**关键：`.tres` 里脚本引用用 `path` + `ExtResource`，不要写 `uid`。** 完整示例：

```ini
[gd_resource type="Resource" script_class="RoomData" load_steps=6 format=3]

[ext_resource type="Script" path="res://scripts/battle/room_data.gd" id="1"]
[ext_resource type="Script" path="res://scripts/battle/gimmicks/你的_boss_gimmick.gd" id="2"]
[ext_resource type="Script" path="res://scripts/battle/intent_data.gd" id="3"]

[sub_resource type="Resource" script_class="IntentData" id="intent_attack"]
script = ExtResource("3")
id = "attack"
display_name = "攻击"
icon = "⚔"
weight = 60.0
purifiable = false
value_mult = 1.0

[sub_resource type="Resource" script_class="IntentData" id="intent_jam"]
script = ExtResource("3")
id = "jam"
display_name = "注废"
icon = "❌"
weight = 40.0
purifiable = true
value_mult = 0.0

[resource]
script = ExtResource("1")
name = "你的新BOSS"
hp = 200
atk = 18
element = "fire"
kind = "boss"
act = 1
boss_role = "rotating"
armor = 20
intents = Array[IntentData]([SubResource("intent_attack"), SubResource("intent_jam")])
gimmick_script = ExtResource("2")
gimmick_params = {"amount": 8}
boss_reward_weapons = Array[String](["res://resources/weapon_templates/xxx_sword.tres", "res://resources/weapon_templates/iron_sword.tres"])
boss_relic_path = "res://resources/charms/你的信物.tres"
```

> ⚠ `kind` 必须写 `"boss"`，否则 `_is_boss_room` 判定失败（duel_controller.gd:820-821）、机制不触发。
> ⚠ `.tres` 的 `[resource]` 段内**不要写 `#` 注释**，Godot 会把它拼进类型名导致解析报错。
> ⚠ `load_steps` 不用手算，保存时 Godot 会自动重算（现有文件里该值新旧不一均能正常加载）。

意图（`RoomData.intents: Array[IntentData]`，T20）说明：
- **空表 = 按 kind 取默认表**：boss 默认 attack 60 / heavy 40（`status_system.gd:19-23`）。
- 房间想特化 → 填自己的 `Array[IntentData]`；共享 `resources/intents/*.tres` 的 weight 恒 1.0（≈33/33/33），要自定义权重就内联 `sub_resource`（如上示例）。
- 干扰类（jam/lock/chaos）务必 `purifiable = true`，供净化药剂对策（净化只抵消干扰意图，见 `consumable_system.use_purify`）。
- `RoomData` 字段全集：`name/hp/atk/archetype/intents/armor/element(none|fire|ice|poison|light|dark)/kind(normal|elite|boss)/gimmick_script/gimmick_params/act/boss_role(fixed|rotating|hidden)/final_boss/boss_reward_weapons/boss_relic_path/art/art_scale`（room_data.gd:8-26）。

### 步骤③ 把 `.tres` 丢进 `resources/rooms/`

`ResourceScan` 在 `_ready` 自动扫描该目录收集房间，无需手动登记。BOSS 槽抽取见 §0（`_pick_boss`，duel_controller.gd:869）。

---

## 4. 修改现有 BOSS 机制

直接编辑对应 `.tres` 的 `gimmick_params` 或脚本，无需动 `duel_controller.gd`：

| BOSS | 脚本 | 可调参数（`gimmick_params` 键） |
|---|---|---|
| 冰封铁瓮 | `rust_armor_gimmick.gd` | `interval` / `per_stack` / `max_stacks` / `two_cols_chance` |
| 碎裂石像鬼 | `glass_cannon_gimmick.gd` | `reflect_ratio` / `reflect_cap` |
| 酸蚀恶鬼 | `acid_bomb_gimmick.gd` | `dot_per_turn` / `dot_base` / `bomb_stacks` / `bomb_dmg` |
| 茧居石雕 | `cocoon_cycle_gimmick.gd` | `cycle_period` / `shell_armor` / `open_armor` / `heal_per_turn` / `open_heavy_mult` |
| 呓语教徒 / 迷宫低语者 | `whisper_lock_gimmick.gd` | `lock_every` / `attack_mult` / `phase2_hp_ratio` / `phase2_lock_every` / `phase2_attack_mult` / `phase2_chaos_chance`（`phase2_hp_ratio=0` = 单阶段） |
| 躁怒元素使 | `bipolar_phase_gimmick.gd` | `manic_atk_mult` / `manic_self_damage_pct` / `phase2_hp_ratio` / `depressed_atk_mult` / `p2_armor` |
| 天平审判官 | `compulsion_rule_gimmick.gd` | `rule_pool` / `rule_every` / `rule_reward_atk_mult` / `rule_punish_mult` / `phase2_hp_ratio` / `p2_atk_mult` / `p2_armor` / `p2_lock_consumable` |
| 无名虚空 | `emotional_vacuum_gimmick.gd` | `phase2_hp_ratio` / `deprive_charms` / `deprive_skills` / `p2_atk_mult` / `p2_armor` |
| 深渊监视者 | `abyss_erosion_gimmick.gd` | `base_ratio` / `low_hp_bonus` / `max_trash` / `phase2_hp_ratio` / `phase2_trash_mult` / `phase2_flashback_chance` / `phase2_armor` / `phase3_*` |
| 碎裂魔王 | `split_ego_gimmick.gd` | `phase2_hp_ratio` / `phase3_hp_ratio` / `anger_atk_mult` / `fear_atk_mult` / `fear_armor_step` / `fear_armor_cap` / `grief_dot_per_turn` / `grief_dot_base` |
| 耻辱审判官 | `shame_counter_gimmick.gd` | `sin_atk_per` / `phase2_hp_ratio` / `phase2_atk_mult` / `phase3_hp_ratio` / `phase3_atk_mult` / `low_hp_ratio` / `low_hp_mult` |
| 勇者的阴影 | `shadow_projection_gimmick.gd` | `projection_every` / `mirror_base_per` / `phase2_hp_ratio` / `phase3_hp_ratio` |

脚本内 `var` 在 `on_room_start` 读 params（`p.get(key, 默认)`），**已无顶部 const 可调**（T24 迁入）。数值 / 逻辑改动后立即在 Godot 内 F6 验证（`.gd` 热重载，无需重启编辑器）。

---

## 5. 必踩的坑

1. **`boss_atk_mult` 每回合会被重置**：duel_controller.gd:998 在每次 `_begin_player_turn` 调 `on_turn_begin` 前归 1.0（`on_room_start` 里设的也会被清掉）——所以只在 `on_turn_begin`（或 `on_turn_resolved` 对攻减半做乘法，见 compulsion_rule）里设置。敌人**护甲**是独立扁平池（`enemy_armor` / `enemy_armor_max`，来自 `RoomData.armor`），不随回合重置——想让护甲持续成长就在 `on_turn_begin` 里逐回合叠加（rust_armor 就是这么干的）。
2. **`pending_lock_reel` / `pending_jam_reel` 是"下一轮"一次性**：设置后于下一轮钉死/注废该列并自动清零，不是永久锁。设 `-1` 表示无锁。
3. **阶段切换标准写法**：`on_damaged` 里 `if not _phase2 and _phase2_hp_ratio > 0.0 and ctrl.enemy_hp <= int(float(ctrl.enemy_hp_max) * _phase2_hp_ratio):` 一次性触发（flag 防重复；`ratio=0` 兜底 = 单阶段，教学位零改动）。范例：whisper_lock_gimmick.gd:53。
4. **破甲三连清甲在 controller 统一处理**（`_on_counter("special")`，2026-08-07 起不绑定 special 符号），gimmick 无需重复实现；穿透符号绕过护甲直击 HP。
5. **`.uid` 文件**：Godot 打开项目后会为每个 `.gd` 生成同名 `.uid`。建议把它和脚本一起提交，保证跨机器一致。

---

## 6. 钩子与杠杆速查

### 7 个钩子（`boss_gimmick.gd` 基类全集）

| 钩子 | 定义处 | 调用时机（代码行号） | 已在用的实例 |
|---|---|---|---|
| `on_room_start(ctrl)` | boss_gimmick.gd:11 | 进房一次，实例化后立即（duel_controller.gd:957） | 全部 13 个：读 `gimmick_params`、开场日志、清状态、`boss_trash = 0`（rust_armor_gimmick.gd:21） |
| `on_turn_begin(ctrl)` | boss_gimmick.gd:15 | 每个玩家回合开始（duel_controller.gd:999-1000，`boss_atk_mult` 重置之后） | 叠甲 / 锁轮 / 注废 / 毒结算（rust_armor_gimmick.gd:31、whisper_lock_gimmick.gd:38、acid_bomb_gimmick.gd:26） |
| `on_damaged(ctrl, dmg)` | boss_gimmick.gd:19 | 玩家结算造成伤害后，先破甲后掉血之后（combat_system.gd:280-281） | 石屑反弹（glass_cannon_gimmick.gd:20）；HP 阈值阶段切换（whisper_lock_gimmick.gd:53、abyss_erosion_gimmick.gd:91） |
| `on_turn_resolved(ctrl)` | boss_gimmick.gd:24 | 玩家结算完成后、敌人行动前（combat_system.gd:300-301；空转 / MISS 回合也触发，可读 `ctrl.grid` 停轮结果） | 律法判定（compulsion_rule_gimmick.gd:73）、空转记罪（shame_counter_gimmick.gd:88）、和解检测（shadow_projection_gimmick.gd:101） |
| `consume_flashback() -> bool` | boss_gimmick.gd:29 | 玩家停轮后、结算前（duel_controller.gd:1044；返回 true 则本次停轮作废、强制免费重转，每回合至多一次） | 闪回暴走（abyss_erosion_gimmick.gd:113） |
| `on_consumable_used(ctrl, effect)` | boss_gimmick.gd:33 | 玩家使用消耗品后（consumable_system.gd:48-49；`effect` = 消耗品 effect 字段，显式判空） | P3 和解检测（shadow_projection_gimmick.gd:116） |
| `on_special_triple(ctrl)` | boss_gimmick.gd:37 | 玩家打出任意同符号三连（combat_system.gd:230-231；钩子名保留，2026-08-07 三连通用化后不限 special 符号） | P3 和解（shadow_projection_gimmick.gd:111）；rust_armor 三连清甲由 controller 统一处理（见 §5 坑④） |

### 可直接读写的字段（`ctrl.` 前缀）

| 字段 | 含义 |
|---|---|
| `enemy_armor` / `enemy_armor_max` | 敌人护甲扁平池（先破甲后掉血；可读写） |
| `boss_atk_mult` | 敌人→玩家伤害倍率（每回合重置为 1.0；只在 `on_turn_begin` / `on_turn_resolved` 设） |
| `boss_trash` | 额外废铁格数 / 列（`reel_system.build_strips` 落实，reel_system.gd:161；设上限防失控） |
| `pending_lock_reel` / `pending_jam_reel` / `pending_chaos` | 锁列 / 注废列 / 乱权（一次性，下一轮生效） |
| `enemy_hp` / `enemy_hp_max` / `enemy_atk` | 敌人当前 / 最大血量、攻击（可读取或扣减） |
| `enemy_element` | 敌人元素（阶段切换改弱点用，改后调 `ctrl.hud._update_enemy_element()`） |
| `enemy_intent` | 当前意图（可覆盖；走 `ctrl.status_system.roll_intent(room)` 掷表，room = 内联 RoomData，范例 abyss_erosion_gimmick.gd:83-89） |
| `pool` | 当前符号池（`pool.size()` 取规模，用于"池越大越狠"类机制） |
| `grid` / `grid_elem` | 停轮后格子（reel 顶格 = `grid[reel][0]`；`on_turn_resolved` 判定用，范例 compulsion_rule._rule_met） |
| `REELS` | 转轮列数 |
| `player_hp` / `player_hp_max` / `player_shield` | 玩家状态（惩罚语义可读 / 扣） |
| `deprived_level` / `locked_consumable_slot` / `player_frost` / `player_status` | 玩家侧惩罚支点（无名虚空 / 律法锁槽 / 寒霜冻结 / 毒层，先例见 §7） |
| `hud._log("…")` / `hud._popup("…", Palette.POP_*, anchor)` | 战斗日志 / 飘字（UI 反馈） |
| `combat.enemy_deal_damage(dmg)` | 敌人对玩家伤害唯一闸口（护盾可挡、飘字 / 受击动画自动，范例 acid_bomb_gimmick.gd:31） |
| `status_system.roll_intent(room)` / `status_system.status_def(id)` | 意图抽取 / 状态定义查询 |
| `resolve_peaceful_win()` | 非暴力和解通关（勇者的阴影 P3 专用，duel_controller.gd:1015） |

---

## 7. 何时才需要改核心代码

只要新机制只用上面 7 钩子 + 既有字段，就**零接触核心**。只有机制需要一种**前所未有的维度**时才加支点，先例：

| 支点 | 用途 | 先例 |
|---|---|---|
| `player_status` / `player_dot_bomb_stacks` | 玩家侧 DoT 叠层 + 爆炸 | acid_bomb_gimmick.gd:23 / split_ego P3 |
| `player_frost` | 玩家侧冻结列 | rust_armor_gimmick.gd:46（T30 寒霜） |
| `deprived_level` | 护符 / 技能剥夺开关 | emotional_vacuum_gimmick.gd:43/72 |
| `locked_consumable_slot` | 律法锁消耗品槽 | compulsion_rule_gimmick.gd:87 |
| `resolve_peaceful_win()` | 非暴力和解通关 | shadow_projection_gimmick.gd:109/114/119 |

加支点模式：`duel_controller` 声明 `var` → `_start_room` 重置 → 调用点应用 → `invalidate_state()`。**改动前先说明意图**，避免破坏既有结算链路。

---

## 8. 现有 13 个 BOSS 机制速查（设计意图）

| 幕 | BOSS（房间 .tres） | 角色 | 机制 | 验证点 |
|---|---|---|---|---|
| A1 | 冰封铁瓮（frozen_urn.tres） | fixed | 熔铸护甲：每 `interval` 回合叠 1 层甲（`per_stack`/层，上限 `max_stacks`）+ T30 寒霜冻结 1-2 列（`two_cols_chance`）；special 三连清甲 | 先掉护甲再掉血；三连后日志「破甲！护甲清零」 |
| A1 | 碎裂石像鬼（brittle_gargoyle.tres） | rotating | 玻璃大炮：高攻低甲 + 受击反弹石屑（`reflect_ratio`，上限 `reflect_cap`）；击杀一击无反弹 | 护盾同挡重击与反弹；爆发抢杀即收益 |
| A1 | 酸蚀恶鬼（acid_ghoul.tres） | rotating | 酸蚀挂毒：玩家侧 DoT 叠层（`dot_per_turn`/`dot_base`）+ 层数爆炸（`bomb_stacks`/`bomb_dmg`） | 清净药剂可清零；速杀或清净二选一 |
| A1 | 茧居石雕（cocoon_sentinel.tres） | hidden | 开合节律：闭合×3（厚甲 `shell_armor` + 回血 + jam）→ 开合×1（甲 0 + 强制重击 ×`open_heavy_mult`） | 唯一输出窗口 = 开合回合；攒爆发进窗口 / 穿透全程直击 |
| A2 | 呓语教徒（whispering_cultist.tres） | fixed | 呓语锁轮（单阶段）：每 `lock_every` 回合锁 1 列 + 当回合攻击 ×`attack_mult` | 第 3/6 回合某列钉死、攻击段冒「呓语强化 ×1.5」 |
| A2 | 迷宫低语者（maze_whisperer.tres） | rotating | 呓语锁轮双阶段：P2 锁轮加速 + 每回合概率乱权（`phase2_*`） | HP 阈值触发 P2 一次性；意图可净化 |
| A2 | 躁怒元素使（manic_elementalist.tres） | rotating | 躁抑交替：P1 高攻 ×`manic_atk_mult` + 自扣血（竞速）→ P2 切冰（弱火）+ 厚甲 `p2_armor` + 注废剖面 | P1 冰武 ×1.5 → P2 换火武 ×1.5（弱点切换验收） |
| A2 | 天平审判官（scale_inquisitor.tres） | rotating | 律法强迫：每 `rule_every` 回合宣告纯律/清规/杀律——达成 → 攻 ×`rule_reward_atk_mult`（安全窗口）；违逆 → 重击 ×`rule_punish_mult`；P2 严刑锁消耗品槽 | 按律法停轮读 grid 判定；锁槽 1 回合自动解锁 |
| A2 | 无名虚空（nameless_void.tres） | hidden | 情感剥离：P1 护符被动全部失效（`deprived_level=1`）→ P2 技能出池（=2，转轮重建） | 只剩武器/消耗品/目押；高 base 武器裸输出 |
| A3 | 深渊监视者（abyss_watcher.tres） | fixed | 深渊侵蚀三阶段：P1 注废（池大小 × 比例，HP 越低越快）→ P2 闪回暴走（`consume_flashback` 强制重转 + 注废加速 + 护甲 40）→ P3 深渊吞噬（废铁翻倍 + 攻击 ×1.3 + 护甲 45） | 带武器越多废铁越多；残血注入加速 |
| A3 | 碎裂魔王（shattered_king.tres） | rotating | 人格裂变三阶段：愤怒·火（高攻）→ 恐惧·冰（每回合叠甲）→ 悲伤·毒（挂毒） | 三元素切换 = 弱点三连翻转（火→冰→毒） |
| A3 | 耻辱审判官（grand_inquisitor.tres） | hidden | 罪业清算三阶段：受击 / 空转记罪（攻击 ×(1+罪业×`sin_atk_per`)）→ 拷问心防剥盾 → 终极审判血线 ×2 | 失误问责：罪业来自玩家自己的受击/空转 |
| 终 | 勇者的阴影（hero_shadow.tres） | final_boss | 万象投影：实例复用前 10 个既有 gimmick 机制 + P2 镜像回敬玩家符号 + P3 非暴力和解（任意三连 / 治疗符号 / 恢复净化消耗品） | 复刻验收；HP 锁 1 无法击杀，和解通关 |

（`cocoon_sentinel_gimmick.gd` = 茧居 v1 叠盾版，保留可回退，未被任何 `.tres` 引用；`gimmicks/` 目录共 14 个脚本 = 13 个实现 + 基类。）

---

## 9. 提交 / 回退

- T2 钩子系统落地提交号 `8006198`；如需回退：`git revert 8006198`。
- 新增 BOSS 机制脚本属纯增量，建议每个 BOSS 一个独立 commit，方便单独回退。
- `.gd` 与配套 `.uid` 一并提交；`.tres` 改动随对应 BOSS commit。
- 本仓库文档与脚本统一提交 `origin/master`。
