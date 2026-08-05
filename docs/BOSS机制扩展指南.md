# BOSS 机制扩展指南（S10 T2 落地版）

> 状态：**T2 已落地（commit `8006198`，本地未推送）**。本文档面向"想自己新增 / 修改 BOSS 机制"的开发者，描述基于 `duel_controller.gd` 钩子系统的数据驱动扩展方式。
> 配套设计见 `数值膨胀与策略深度设计框架.md` §12.3（防无脑化四机制）。

---

## 0. 核心结论

新增一个 BOSS **几乎不需要改动核心战斗代码**。整套机制是数据驱动的：

- 每间 BOSS 房在 `RoomData` 里用 `gimmick_script` 字段指向一个机制脚本；
- `duel_controller._start_room` 进房时自动 `r.gimmick_script.new()` 实例化并赋值 `current_gimmick`；
- 之后每个回合 / 事件自动回调 4 个钩子：**非 BOSS 房一律跳过**（调用处均已显式 `!= null` 判空，不会崩）。

因此"加 BOSS" = **写一个脚本 + 给房间 `.tres` 挂上它**，无需登记到任何数组 / 字典（Phase D 的 `ResourceScan` 自动扫描 `resources/rooms/`）。

---

## 1. 文件清单

| 文件 | 作用 |
|---|---|
| `scripts/battle/gimmicks/boss_gimmick.gd` | BOSS 机制基类（4 个空钩子，必须 `extends` 它） |
| `scripts/battle/gimmicks/rust_armor_gimmick.gd` | 幕一·锈蚀傀儡「熔铸护甲」示例 |
| `scripts/battle/gimmicks/whisper_lock_gimmick.gd` | 幕二·呓语教徒「呓语锁轮」示例 |
| `scripts/battle/gimmicks/abyss_erosion_gimmick.gd` | 幕三·深渊监视者「深渊侵蚀」示例 |
| `scripts/battle/room_data.gd` | 房间数据，`gimmick_script: Script` 导出字段 |
| `scripts/battle/duel_controller.gd` | 战斗核心（接线点见 §6，正常不用改） |

---

## 2. 核心架构

```
RoomData (.tres)
  └─ gimmick_script: Script  ──→  BossGimmick 子类实例 = current_gimmick

duel_controller 生命周期：
  _start_room(idx)
      ├─ if BOSS 房 and gimmick_script != null:
      │     current_gimmick = r.gimmick_script.new()
      │     current_gimmick.on_room_start(self)
      └─ else: current_gimmick = null   ← 所有钩子调用处判空跳过

  _begin_player_turn()                 ← 每回合开始
      ├─ boss_atk_mult = 1.0           ← 先重置（见 §5 坑①）
      └─ current_gimmick?.on_turn_begin(self)   ← 护甲成长等逐回合效果（rust_armor 在此叠甲）

  _evaluate()（结算）
      ├─ _apply_enemy_damage(total, pierce)   ← 先破甲后掉血；pierce 直接扣 HP（见 §10.6）
      ├─ current_gimmick?.on_damaged(self, total)   ← 敌人受伤后
      └─ if 三连: current_gimmick?.on_special_triple(self) + _on_counter（破甲/核爆，见 §10.6）

  _enemy_deal_damage()                 ← 敌人→玩家
      └─ eff *= boss_atk_mult

  _build_strips()                      ← 转轮带构建
      └─ 注入 boss_trash 格/列废铁
```

---

## 3. 新建一个全新 BOSS（3 步）

### 步骤① 写机制脚本

新建 `scripts/battle/gimmicks/你的_boss_gimmick.gd`：

```gdscript
extends BossGimmick

# 只覆写需要的钩子；不用的钩子不写即可（基类是空 pass）。
# 参数 ctrl = DuelController 实例，动态访问，不要给 ctrl 标类型。

var _turns := 0

func on_room_start(ctrl) -> void:
    _turns = 0
    ctrl.hud._log("💡 我的 BOSS 登场")

func on_turn_begin(ctrl) -> void:
    _turns += 1
    # 例：每 2 回合给敌人叠护甲（成长型护甲池；先破甲后掉血，见 §10.6 / 数值框架 §10.6）
    # 注意：护甲是敌人属性，增/减都在 enemy_armor / enemy_armor_max 上操作
    if _turns % 2 == 0:
        ctrl.enemy_armor_max += 8
        ctrl.enemy_armor += 8

func on_special_triple(ctrl) -> void:
    ctrl.hud._log("三连触发！")

func on_damaged(ctrl, dmg: int) -> void:
    pass
```

### 步骤② 给房间 `.tres` 挂脚本

参考 `resources/rooms/abyss_watcher.tres` 已挂好的写法。**关键：`.tres` 里脚本引用用 `path` + `ExtResource`，不要写 `uid`。**

```ini
[gd_resource type="Resource" script_class="RoomData" load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/battle/room_data.gd" id="1"]
[ext_resource type="Script" path="res://scripts/battle/gimmicks/你的_boss_gimmick.gd" id="2"]

[resource]
script = ExtResource("1")
name = "你的新BOSS"
hp = 200
atk = 18
jam = 0.2
lock = 0.2
chaos = 0.2
heavy = 0.2
element = "fire"
kind = "boss"
gimmick_script = ExtResource("2")
```

> ⚠ `load_steps = ext_resource 数量 + 1`。挂了 2 个 `ext_resource` 就写 `3`。
> ⚠ `.tres` 的 `[resource]` 段内**不要写 `#` 注释**，Godot 会把它拼进类型名导致解析报错。
> ⚠ `kind` 必须写 `"boss"`，否则 `_is_boss_room` 判定失败、机制不触发。

### 步骤③ 把 `.tres` 丢进 `resources/rooms/`

`ResourceScan` 在 `_ready` 自动扫描该目录收集房间，无需手动登记。

---

## 4. 修改现有 BOSS 机制

直接编辑对应脚本，无需动 `duel_controller.gd`：

| BOSS | 脚本 | 可调参数（脚本顶部 `const`） |
|---|---|---|
| 熔铸护甲 | `rust_armor_gimmick.gd` | `MAX_STACKS`（叠甲层数上限）、`ARMOR_PER_STACK`（每层护甲点数，叠加在 `RoomData.armor` 之上） |
| 呓语锁轮 | `whisper_lock_gimmick.gd` | `LOCK_EVERY`（锁轮频率回合）、`ATTACK_MULT`（强化倍数） |
| 深渊侵蚀 | `abyss_erosion_gimmick.gd` | `BASE_RATIO`、`LOW_HP_BONUS`、`MAX_TRASH`（废铁上限） |

数值 / 逻辑改动后立即在 Godot 内 F6 验证，无需重启编辑器（`.gd` 热重载）。

---

## 5. 三个必踩的坑

1. **攻击倍率每回合会被重置**：`duel_controller` 在每回合开始先把 `boss_atk_mult` 归 1.0（见源码）。敌人**护甲**是独立扁平池（`enemy_armor` / `enemy_armor_max`，来自 `RoomData.armor`），不在每回合重置——若想让护甲**持续成长**，在 `on_turn_begin` 里逐回合叠加（rust_armor 就是这么干的）；若想让护甲**被打掉后保持空窗**，靠 `_on_counter("special")`（special 三连）或穿透符号破甲即可，无需 gimmick 干预。一次性效果（如呓语只在第 3 回合 ×1.5）在命中时设即可。
2. **`pending_lock_reel` 是"下一轮固定该列"**：设置后于对应回合钉死该列并自动清零（源码 1029 行），不是永久锁。设 `-1` 表示无锁。
3. **`.uid` 文件**：Godot 打开项目后会为每个 `.gd` 生成同名 `.uid`。建议把它和脚本一起提交，保证跨机器一致（本仓库 T2 的 4 个 `.uid` 已随文档提交补全）。

---

## 6. 钩子与杠杆速查

### 4 个钩子

| 钩子 | 触发时机 | 典型用途 |
|---|---|---|
| `on_room_start(ctrl)` | 进房一次 | 清状态、`hud._log` 开场白、`boss_trash = 0` |
| `on_turn_begin(ctrl)` | 每个玩家回合开始 | 推栈 / 锁轮 / 注废铁 / 叠敌人护甲 / 设 `boss_atk_mult` |
| `on_damaged(ctrl, dmg)` | 敌人受玩家伤害后 | 读 `dmg`、`enemy_hp`、`pool`，做反伤 / 阶段转换 |
| `on_special_triple(ctrl)` | 玩家打出 special 三连 | 清层数、爆发、阶段切换 |

### 可直接读写的字段（`ctrl.` 前缀）

| 字段 | 含义 |
|---|---|
| `enemy_armor` / `enemy_armor_max` | 敌人护甲扁平池（先破甲后掉血；可被 `_on_counter`/穿透符号清零，见 §10.6） |
| `boss_atk_mult` | 敌人→玩家伤害倍率（每回合重置为 1.0） |
| `boss_trash` | 额外废铁格数 / 列，在 `_build_strips` 落实（注意设上限防失控） |
| `pending_lock_reel` | 锁定列索引（`-1` 无；生效一次后自动清零） |
| `enemy_hp` / `enemy_hp_max` | 敌人当前 / 最大血量（可读取或扣减） |
| `pool` | 当前符号池（`pool.size()` 取规模，用于"池越大越狠"类机制） |
| `REELS` | 转轮列数 |
| `hud._log("…")` | 打一行战斗日志（UI 反馈用） |

---

## 7. 何时才需要改 `duel_controller.gd`

只要新机制只用上面 4 钩子 + 既有字段，就**零接触核心代码**。

只有机制需要一种**前所未有的维度**时，才需要加支点，例如：
- 给玩家上 debuff（持续状态）
- 动态改变 payline 数量 / 转轮列数
- 每回合偷金币 / 改商店

做法：若新机制需要前所未有的维度（如给玩家上 debuff、改 payline），才在 `duel_controller.gd` 加 `var` + 在合适生命周期位置接线（参考既有支点：声明 → `_start_room` 重置 → 调用点应用 → 日志）。**改动前先说明意图**，避免破坏既有结算链路。敌人护甲类机制无需改核心——直接读写 `ctrl.enemy_armor` / `ctrl.enemy_armor_max` 即可（见 §10.6、`rust_armor_gimmick.gd`）。

---

## 8. 现有三个 BOSS 机制速查（设计意图）

| BOSS | 机制 | 设计意图 | 验证点 |
|---|---|---|---|
| 锈蚀傀儡·熔铸护甲 | 每 2 回合叠 1 层护甲（+8/层，上限 3 层，叠加在 `RoomData.armor` 之上）；special 三连清空全部护甲（开直击HP窗口）；穿透符号绕过护甲 | 教玩家主动追求 special 三连 / 用穿透符号破甲 | 打它先掉护甲再掉血；三连后日志「破甲！护甲清零」、后续伤害直击 HP |
| 呓语教徒·呓语锁轮 | 每 3 回合必锁 1 列（无视抗扰）+ 当回合敌人攻击 ×1.5 | 逼玩家在 4 格子腰带里为「净化药剂」留位 | 第 3/6 回合某列钉死、攻击段冒「呓语强化 ×1.5」 |
| 深渊监视者·深渊侵蚀 | 每回合按符号池大小比例注废铁，HP 越低注越快（上限 24 格/列） | 强化「稀释刹车」，与「进池类无天花板」对抗 | 带武器越多废铁越多；残血时注入加速 |

---

## 9. 提交 / 回退

- T2 提交号 `8006198`；如需回退：`git revert 8006198`。
- 新增 BOSS 机制脚本属纯增量，建议每个 BOSS 一个独立 commit，方便单独回退。
- 本仓库文档与脚本统一提交 `origin/master`。
