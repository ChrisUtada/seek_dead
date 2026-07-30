# 《Seek Dead》代码与结构 Review 报告

> 审查日期：2026-07-08
> 最后更新：2026-07-08（P0 #2/#3/#4 已修复）
> 审查范围：83 个 GDScript 文件、42 个场景、41 个 Resource、整体架构
> 引擎版本：Godot 4.7

---

## 总体评价

项目架构**整体良好**：组件化设计清晰、数据驱动程度高（`.tres` 配置）、事件解耦（EventManager）到位、对象池已接通、架构待办文档维护规范。作为"迁移可行性验证原型"，它已经超额完成了验证目标。

但随着功能扩张（装备/技能/房间系统叠加），**技术债开始累积**：存在 3 个会直接影响游戏体验的 bug、2 处明显的代码分叉重复、52 处裸 `print()`、1 个完全空壳的系统。下面按优先级给出具体问题和改进方案。

---

## P0 — 必须修复（影响游戏正确性）

### 1. AudioManager 是空壳，游戏完全无声 ⏸ 暂缓（2026-07-08 用户决策）

**文件**：`autoload/audio_manager.gd` + `project.godot:29`

**问题**：AudioManager 注册为 `*res://autoload/audio_manager.gd`（纯脚本，非 `.tscn`）。它的 `@export var sfx_paths: Array[String]` 依赖编辑器配置，但纯脚本 autoload **无法在编辑器中设置 @export 值**，因此 `sfx_paths` 永远为空 `[]`。

`play_sfx()`（:57-69）在 `path == ""` 时直接 `return`，导致全项目 12 处 `AudioManager.play_sfx(...)` 调用**全部静默无效**。玩家听不到任何音效。

**修复方案**（二选一）：
- **方案 A（推荐）**：把 AudioManager autoload 改为 `.tscn`，在场景节点上配置 `sfx_paths`
- **方案 B**：删除 `@export`，改为脚本内硬编码音效路径字典：
  ```gdscript
  const SFX_PATHS := {
      SfxType.PLAYER_SHOT: "res://assets/sfx/shot.wav",
      # ...
  }
  ```

**状态**：⏸ 用户决策暂缓（2026-07-08）。当前项目无任何音效资源文件，`sfx_paths` 无可配置内容，AudioManager 空壳属合理现状。待后续补充音效资源后，再按方案 A（改为 `.tscn` 配置 `@export`）或方案 B（脚本内硬编码路径字典）落地即可。

### 2. GoldPickup 0.3 秒后自动收集（逻辑 bug） ✅ 已修复

**文件**：`scripts/equipment/gold_pickup.gd:17-18`

**问题**：`setup()` 末尾创建了 0.3 秒定时器并连接到 `_collect()`：
```gdscript
var timer = get_tree().create_timer(0.3, false)
timer.timeout.connect(_collect)
```
这意味着金币生成 0.3 秒后**无条件自动收集**，玩家根本不需要靠近。这几乎可以确定是 bug（可能是调试时为了测试掉落而加的自动收集，忘记删除）。

**修复**：删除这两行。若需要"吸附"效果，应实现磁吸逻辑（检测玩家距离后移动过去），而不是定时自动收集。

**状态**：✅ 已于 2026-07-08 修复，删除了 `setup()` 中的 0.3s 自动收集定时器。

### 3. GoldPickup 每次拾取都写盘存档（性能 bug） ✅ 已修复

**文件**：`scripts/equipment/gold_pickup.gd:60-62`

**问题**：每次捡金币都调用 `SaveSystem.load_lobby_data()` + `save_lobby_data()`，即一次文件读 + 一次文件写。一局游戏可能捡几十上百次金币，造成不必要的 IO 压力和存档竞争。

**修复**：金币只累加到 `GameManager.run_gold`（内存），在 `GameManager.end_run()` 时统一写盘（该函数已有此逻辑）。删除拾取时的存档读写。

**状态**：✅ 已于 2026-07-08 修复，删除了 `_collect()` 中的 `load_lobby_data`/`save_lobby_data` 调用，金币改由 `GameManager.end_run()` 统一持久化。

### 4. SkillPickup 失败时仍销毁拾取物（数据丢失 bug） ✅ 已修复

**文件**：`scripts/equipment/skill_pickup.gd:67-76`

**问题**：
```gdscript
_collected = true
var dup = skill.duplicate(true)
if sm.add_or_upgrade(dup):
    print(...)
    EventManager.skill_picked_up.emit({"skill": dup})
_collected = false              # 重置标记
var tween = create_tween()      # 但仍然播放消失动画
tween.tween_callback(queue_free) # 并销毁拾取物
```
当 `add_or_upgrade()` 失败（技能槽满且无法升级）时，`_collected` 被重置为 `false`，但**拾取物仍然被 `queue_free()` 销毁**。玩家什么都没拿到，技能球却消失了。

**修复**：失败时应 `return`，保留拾取物供玩家稍后再试：
```gdscript
if sm.add_or_upgrade(dup):
    print(...)
    EventManager.skill_picked_up.emit({"skill": dup})
    var tween = create_tween()
    tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.1)
    tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.15)
    tween.tween_callback(queue_free)
else:
    _collected = false  # 失败，允许重试
```

**状态**：✅ 已于 2026-07-08 修复，成功才播放动画+销毁，失败时重置 `_collected` 保留拾取物供重试。

### 5. KEY_K 调试代码残留在生产代码中 ⏸ 暂缓（2026-07-08 用户决策）

**文件**：`scripts/battle/player_controller.gd:209-214, 270-301`

**问题**：按 K 键会生成"调试头盔"并**满血**（`state.hp = state.max_hp`），含 4 处 `print("[装备调试]...")`。这在正式游戏中是作弊后门。

**修复**：用 `OS.is_debug_build()` 守卫，或直接删除：
```gdscript
if OS.is_debug_build() and Input.is_key_pressed(KEY_K):
    ...
  ```

**状态**：⏸ 用户决策暂缓（2026-07-08）。调试后门（按 K 生成调试头盔 + 满血）用户选择暂时保留，后续自行优化。建议在正式发布前用 `OS.is_debug_build()` 守卫或删除，避免生产环境作弊入口。

---

## P1 — 高优先级（影响可维护性）

### 6. room_builder.gd 与 room_generator.gd 是重复分叉 ✅ 已修复

**文件**：`scripts/rooms/room_builder.gd`（377 行，已删除）vs `scripts/rooms/room_generator.gd`（420 行，现唯一实现）

**问题**：两个文件是同一套房间生成工具的复制粘贴分叉，共享相同的常量（`DOOR_SCENE`、`ROOMS_DIR`、`WALL_THICKNESS`）、相同的 `enum RoomSize`、几乎相同的内部类。维护时改一个忘改另一个，极易产生不一致。

**修复**（2026-07-08 执行）：经 grep 确认 `room_builder.gd` 未被任何 `.tscn` 引用，且项目文档 `房间环境碰撞体实施计划.md` 已明确将其标记为**已弃用**（旧方案，因 StaticBody2D 定位 bug + ownership 未递归设置）。其内部的 25 个 `room_01~25` 房间定义从未生成进 `scenes/rooms/` 或 `resources/rooms/`，属于被新方案取代的早期设计；已发布房间 `room_1~4 + room_boss` 也不含其 `_interactables()` 等能力，故无线上功能损失。

→ **已 `git rm` 删除 `scripts/rooms/room_builder.gd`（及 `.uid`）**，保留 `room_generator.gd` 为唯一权威生成器，并在其文件头补注说明。分叉彻底解决。

### 7. 52 处裸 print() 散落在生产代码中 ✅ 已修复（2026-07-08）

**分布**：`effect_executor.gd`(11)、`hud.gd`(7)、`room_generator.gd`(6)、`player_controller.gd`(4，全调试) 等。（注：`room_builder.gd` 已于 2026-07-08 删除，其 5 处 print 随之移除。）

**问题**：`print()` 在 Godot 中有性能开销（尤其在 `_process` 中调用时），且污染日志输出。`effect_executor.gd` 的 11 处全是战斗效果执行日志，每次命中都打印。

**修复**（2026-07-08 执行）：新建 `scripts/utils/debug.gd`（`class_name Debug`），用 `OS.is_debug_build()` 做开关——debug/编辑器构建自动打印，release 导出构建自动静默。提供 `Debug.log()`（普通调试日志）、`Debug.warn()`（→ `push_warning`）、`Debug.error()`（→ `push_error`，用于真正缺陷）。

全项目 47 处裸 `print()`（实测数，含已删 `room_builder.gd` 后的剩余量）全部接管：
- 45 处普通调试日志 → `Debug.log(...)`（覆盖 effect_executor 11、hud 7、player_controller 4、room_generator 6、room_manager 3、game 3、equipment_pickup 2、set_bonus 2、weapon_previewer 2 等）
- 2 处"未实现效果 / SPAWN_PROJECTILE 待实现"（`effect_executor.gd:31`、`:169`）→ 升级为 `Debug.error(...)`，作为真正需要暴露的缺陷

多参 `print("x", y)` 已合并为单字符串 `Debug.log("x" + y)`。验证：游戏代码中已无裸 `print()`（仅 `debug.gd` 内部 `print(msg)` 与文档注释），共 47 处 `Debug.log/error` 调用。

### 8. 拾取物系统高度重复，缺公共基类 ✅ 已修复（2026-07-08）

**文件**：`scripts/equipment/pickup_base.gd`（新建）、`gold_pickup.gd`、`health_pickup.gd`、`skill_pickup.gd`、`equipment_pickup.gd`

**问题**：四个拾取物类的 `setup()` 碰撞设置、`_build_visual()`（碰撞形状 + ColorRect + Label）、`_on_body_entered`/`_on_area_entered`、tween 销毁动画几乎完全相同，仅数值和颜色不同，维护时需四处同步。

**修复**：新建 `PickupBase`（`class_name PickupBase`，`extends Area2D`），统一收口：
- `_init_pickup()`：碰撞层/掩码、`set_deferred` 监控状态、信号连接、`call_deferred("_build_visual")`
- `_on_body_entered` / `_on_area_entered` → `_on_player_touched(target)`：`_collected` 守卫 → `_player_valid(target)` 校验 → `_apply_effect(target)` 业务 → 成功才 `_play_collect_animation()`
- 外观辅助方法 `_add_collision_shape` / `_add_orb` / `_add_border` / `_add_label`，消除 4 处逐行重复的 ColorRect/Label 构建
- 子类钩子 `_player_valid(target)`（默认校验 `players` 组，金币可重写只校验 GameManager）、`_apply_effect(target) -> bool`（失败返回 `false` 即保留拾取物供重试）

四个子类现在平均从 ~75 行降到 ~25 行，只保留：数据字段、`setup()` 的数据赋值 + `_init_pickup()` 调用、`_build_visual()`（外观）、`_apply_effect()`（业务）。**原有行为完全保留**——金币入库、血球治疗、技能 `add_or_upgrade` 失败保留（P0 #4）、装备背包满保留等逻辑均不变；外部调用契约（`.new()` + `.setup(...)`）未变。

### 9. _get_wave_property 用字符串访问代替类型化属性 ✅ 已修复（2026-07-08）

**文件**：`scripts/rooms/room_manager.gd`（`_get_wave_property` 及 8 处调用）、`scripts/rooms/room_config.gd`、`resources/rooms/*.tres`

**问题**：`WaveConfig` 已有类型化的 `@export` 属性，但 `room_manager.gd` 把 wave 当作 `Resource` 并用 `wave.get("spawn_marker_groups")` 字符串反射访问。这丢失了类型检查，重构时极易出错（属性改名或拼错无编译期报错）。

**修复**（2026-07-08 执行）：
- `RoomConfig.waves` 从 `Array[Resource]` 收紧为 `Array[WaveConfig]`（已确认所有 `.tres` 的 wave 子资源均 `script = wave_config.gd`）
- `room_manager.gd`：`_active_waves`、`wave`、`next_wave` 全部收紧为 `WaveConfig` 类型
- 删除 `_get_wave_property()` 函数，8 处调用改为直接类型化访问：`wave.spawn_marker_groups` / `wave.enemy_count` / `wave.announce` / `wave.delay` / `next_wave.trigger` / `next_wave.trigger_value`
- 同步更新 3 个含 wave 的 `.tres`（room_3_medium / room_4_large / room_boss）的 `Array[Resource]` → `Array[WaveConfig]`，保持类型一致、避免加载告警

**行为完全保留**：原 `_get_wave_property` 的默认值仅在属性为 null 时生效，类型化的 `WaveConfig` 属性永不为 null（均有 `@export` 默认值），故 `int()` 包裹、`trigger` 枚举按 0/1/2/3 匹配、三处 `trigger_value` 默认值等均等价无变化。

### 10. _spawn_skill_reward 是死代码 ✅ 已修复（2026-07-08）

**文件**：`scripts/rooms/room_manager.gd`（原 :549-562）

**问题**：`_spawn_skill_reward()` 已定义但全项目无任何调用，且与 `_spawn_skill_pickup()` 逻辑重复（仅落点偏移不同，核心逻辑 100% 一致）。

**修复**（2026-07-08 执行）：已从 `room_manager.gd` 直接删除该函数（约 14 行），`_spawn_equip_drop` 前移到原位置，文件结构完整无空档。grep 确认全项目无任何调用残留。若日后需要"清房掉技能"奖励机制，应复用现有 `_spawn_skill_pickup()` 而非新增副本。

---

## P2 — 中优先级（改善结构与可读性）

### 11. 8 处硬编码房间中心坐标 ✅ 已修复（2026-07-08）

**文件**：`scripts/rooms/room_manager.gd`（:261, :274, :296, :371, :543, :562, :605, :616）

**问题**：`Vector2(320, 180)` 和 `Vector2(320, 200)` 作为兜底位置硬编码 8 处，对应 640×360 视口的中心。改分辨率或房间尺寸时需要全局搜索替换。

**修复**：提取常量并从配置推导：
```gdscript
const ROOM_CENTER := Vector2(320, 180)
# 或动态计算
var viewport_size := get_viewport_rect().size
var room_center := viewport_size * 0.5
```

**状态**：✅ 已于 2026-07-08 修复。原报告列 8 处，其中 2 处位于当时已删除的 `_spawn_skill_reward()`（见 #10），剩余 6 处。在 `room_manager.gd` 顶部 const 区新增：
```gdscript
const ROOM_CENTER := Vector2(320, 180)                # 640×360 视口中心，见 project.godot:34-35
const DROP_CENTER := ROOM_CENTER + Vector2(0, 20)     # 掉落物兜底落点：房间中心下方一点
```
- boss/elite 生成兜底、玩家入场兜底 → `ROOM_CENTER`
- `_spawn_rewards` / `_spawn_enchantment_table` / `_spawn_skill_pickup` 的 `center` 兜底 → `DROP_CENTER`

grep 确认全文件已无 `Vector2(320, 180/200)` 使用残留（仅常量定义本身）。改分辨率或房间尺寸时只需调整 `ROOM_CENTER` 一处。

### 12. hud.gd 过大（1030 行），职责过多

**文件**：`scenes/ui/hud.gd`

**问题**：单文件 1030 行，承担 HP/能量/体力/热量条、技能栏、技能升级/选择弹窗、伤害飘字、装备触发飘字等多重职责。

**修复**：按职责拆出 4 个 `class_name` 子组件，均在 `hud.gd` 的 `_ready()` 中 `.new()` 并 `add_child()`（HUD 是代码生成式 UI，非场景子节点）：
- `scenes/ui/status_bars.gd`（`StatusBars`）— HP/能量/体力/热量四条状态条及告警、熔毁动画。`connect_player(st)` 注入玩家状态后自动更新。
- `scenes/ui/damage_number_spawner.gd`（`DamageNumberSpawner`）— 伤害数字 + 装备触发/套装激活浮动文字。`connect_player_equipment(player)` 绑定装备信号。
- `scenes/ui/skill_bar.gd`（`SkillBar`）— 技能栏 2 槽位与冷却遮罩，自带 `_process` 每帧刷新。`connect_manager(sm)` 注入 SkillManager。
- `scenes/ui/skill_choice_ui.gd`（`SkillChoiceUI`）— 技能升级/选择弹窗（暂停游戏 + 鼠标点击卡片选择），自身处理 `_input`，不依赖 HUD。`set_skill_manager(sm)` + `show_skill_upgrade(sm)` / `show_skill_choice(choices)`。

`hud.gd` 现保留职责：准星/覆盖层/受击闪屏、弹药显示、逃脱/功能按钮条、装备面板、输入处理（暂停/重开/背包/返回大厅）、技能替换弹窗，以及转发入口 `show_skill_upgrade` / `show_skill_choice` / `spawn_damage_number` / `spawn_floating_text`（供 `room_manager` 等经 `find_child("HUD")` 调用）。**行数 1030 → 581**，外部 API 不变。

### 13. room_manager.gd 过大（664 行），混合多职责

**文件**：`scripts/rooms/room_manager.gd`

**问题**：承担房间切换、波次生成、拾取物生成、门控制、技能奖励等多职责。

**修复**（2026-07-08 执行）：按职责拆出 2 个 `class_name` 子组件，均在 `room_manager.gd` 的 `_ready()` 中 `.new()` 并 `add_child()`（RoomManager 是 autoload 单例，子组件随其树存在；`init(self)` 注入引用以读取当前房间/配置/玩家与 `ROOM_CENTER`/`DROP_CENTER` 常量）：
- `scripts/rooms/wave_spawner.gd`（`WaveSpawner extends Node`）— 波次触发与敌人（含 Boss/精英）生成：`spawn_wave` / `process_waves`（每帧由 RoomManager._process 调用，清房后广播 `EventManager.room_cleared`）/ `check_wave_triggers` / `spawn_next_wave` / `show_wave_announce` / `clear_dead_bosses` / `reset_state`，及全部波次状态变量。
- `scripts/rooms/pickup_spawner.gd`（`PickupSpawner extends Node`）— 拾取物与技能弹窗生成：`on_enemy_died`（敌死掉落，原 `_on_enemy_died`）/ `show_skill_upgrade` / `show_skill_choice` / `spawn_rewards` / `spawn_equip_drop` / `spawn_health_pickup` / `spawn_gold_pickup` / `spawn_enchantment_table` / `spawn_skill_pickup` / `get_player_inventory`。

`room_manager.gd` 现保留职责（279 行）：房间配置加载、房间切换与过场、玩家定位、门连接/解锁、波次与掉落的**协调**（_process 委托 `_wave_spawner.process_waves`；`_do_switch` 委托 `spawn_wave`/`spawn_enchantment_table`；`_on_room_cleared` 委托 `spawn_rewards`/`show_skill_upgrade`；`enemy_died` 信号改连 `_pickup_spawner.on_enemy_died`），并新增共享状态访问器 `get_current_room`/`get_current_config`/`get_player`/`get_room_center`/`get_drop_center`（`ROOM_CENTER`/`DROP_CENTER` 仍只定义一处）。**行数 644 → 279**，外部 API 不变（`get_current_room_size`/`get_current_wave_index`/`enter_first_room`/`escape_current_room` 仍由 room_context.gd / game.gd / escape_skill.gd 经 autoload 调用）。

> 注：原 #14（_spawn_wave 内部敌人生成重复）在拆分 `wave_spawner.gd` 时已随结构重组自然消解——wave 敌人块与 min_enemies 兜底块同处 `spawn_wave` 内、逻辑已清晰，无需再额外抽函数；标为随 #13 一并处理。

### 14. _spawn_wave 内部敌人生成逻辑重复

**文件**：`scripts/rooms/wave_spawner.gd`（原 `room_manager.gd:218-247`，#13 拆分后迁入）

**问题**：`spawn_wave` 内 wave 敌人生成（`if wave` 块）与 `min_enemies` 兜底生成（`elif` 块）是几乎相同的循环代码。

**修复**（2026-07-08 实际落地）：提取 `_spawn_enemies_at_markers(room, markers, count, enemy_pool)` 辅助函数（含 `markers.is_empty()`/`count<=0` 早退、`markers.shuffle()` + 取模复用 marker 的循环），两处调用统一委托它。`enemy_pool` 为 `Array[PackedScene]`（与 helper 的 `Array` 形参协变兼容）。净减 ~14 行重复，行为逐字等价。

### 15. Autoload 散落在 4 个不同目录

**文件**：`project.godot:24-30`

**问题**：7 个 autoload 分布在 `autoload/`、`scripts/systems/`、`scripts/utils/`、`scripts/rooms/` 四个目录。另外 `scripts/autoload/object_pool.gd` 不是 autoload 却放在 autoload 目录。

**修复**（✅ 已执行）：
- 用 `git mv` 将 `EntityRegistry`（`scripts/systems/→autoload/`）、`SaveSystem`（`scripts/utils/→autoload/`）、`RoomManager`（`scripts/rooms/→autoload/`）三个脚本连同 `.uid` 一并迁入 `autoload/`；7 个 autoload 现全部集中于 `autoload/`。
- 将非 autoload 的 `object_pool.gd`（`scripts/autoload/→scripts/utils/`）归位，原 `scripts/autoload/` 目录已清空删除。
- `project.godot` 的 `[autoload]` 三项路径同步更新为 `res://autoload/...`。
- 因所有 autoload 均经单例名/`class_name` 访问（无任何 `preload` 指向旧路径），迁移零引用断裂。

### 16. DamageSystem 用 Dictionary 传递战斗属性，类型不安全

**文件**：`scripts/battle/damage_system.gd:34`

**问题**：`calculate(attacker_stats: Dictionary, defender_stats: Dictionary, ...)` 用无类型 Dictionary 传递攻防属性，键名拼写错误无法在编译期发现。

**修复**（✅ 已执行）：
- 新增 `scripts/battle/combat_stats.gd`（`class_name CombatStats extends RefCounted`）：把 8 类攻击加成 / 8 类防御减免 / `crit_rate` / `crit_damage` / `innate_type` 提升为强类型字段，并提供 `bonus_for(dt)` / `defense_for(dt)` 按 `DamageSystem.DamageType` 取值。
- `DamageSystem.calculate(attacker: CombatStats, defender: CombatStats, ...)` 与 `calculate_simple(target: CombatStats = null)` 改为接受类型化参数；删除 `_bonus_keys` / `_defense_keys` / `_keys_initialized` / `_init_type_keys` 及基于字符串键的 `_get_attack_bonus` / `_get_defense_ratio` 机制。
- `CombatStats.from_dict(d)` 兼容旧式 Dictionary（来自 `.tres` / `EnemyConfig.defenses` / 装备 `bonuses`），并对**未知键发出 `Debug.warn` 告警**——从而把拼写错误从「静默生效」变为「加载/换装时可见」。
- `state_component.gd` 的 `take_damage` 用 `CombatStats.from_dict(defenses)` / `from_dict(bonuses)` 包装后再传入 `calculate`；`status_effect.gd` 的 `calculate_simple` 两参调用仍兼容（target 默认 null）。
- **范围说明**：`EnemyConfig.defenses` 仍为 `@export var defenses: Dictionary`（由约 10 个 `.tres` 序列化），本次**未改为 `CombatStats` 导出字段**，以避免批量改写 `.tres` 子资源带来的风险。类型安全已在 `DamageSystem` 边界达成，`.tres` 内的拼写错误由 `from_dict` 的告警兜底捕获；彻底的 Resource 化可作为后续中期任务。

---

## P3 — 低优先级（锦上添花）

### 17. 非 autoload 脚本缺少 class_name ✅ 已修复（autoload 部分已回退）

**问题**：如 `boss_enemy.gd`、`projectile.gd`、`room_generator.gd` 等缺少 `class_name`，跨脚本引用只能靠 `preload`。

**修复**（✅ 已执行，2026-07-08）：为全部 **19 个非 autoload** 脚本补上 `class_name`（`BossEnemy`/`Projectile`/`Goblin`/`EliteMage`/`EliteGoblin`/`EliteArcher`/`LimbBoss`/`Knight`/`EnemyHpBar`/`Shadow`/`PoolArea`/`SlowArea`/`AuraArea`/`MainMenu`/`Lobby`/`Game`/`HUD`/`RoomGenerator`/`WeaponPreviewer`）。命名取文件名 PascalCase；`knight.gd`（字符串 `extends`）与 `@tool` 脚本（`room_generator.gd`/`weapon_previewer.gd`）的 `class_name` 均置于正确位置。

⚠️ **autoload 脚本不应加与单例同名的 `class_name`**（教训，2026-07-08 回退）：初版曾给 7 个 autoload（`GameManager`/`EventManager`/`SaveSystem`/`EntityRegistry`/`RoomManager`/`AudioManager`/`SceneManager`）也补了同名 `class_name`，但 Godot 中全局标识符会优先解析为 `class_name` 而非 autoload 单例，导致：
- 编辑器告警 `Class "X" hides an autoload singleton`；
- 代码里 `SaveSystem.load_lobby_data()` 这类把单例当全局调用的写法报错 `Cannot call non-static function ... on the class "SaveSystem" directly`（被解析成了类而非实例）。

故已将 7 个 autoload 的 `class_name` **全部回退移除**——autoload 仍通过注册名全局访问（无需 `class_name`），且 `scripts/` 下其余非 autoload 脚本的 `class_name` 不受影响。

### 18. 全项目零 TODO/FIXME 标注 ✅ 已修复

**问题**：缺失功能没有任何 TODO 标注，反而难以追踪待办。

**修复**（✅ 已执行，2026-07-08）：在代码层为已知未完成项添加 `# TODO:` 注释，供 IDE 任务面板追踪：
- `scripts/rooms/room_generator.gd` 的 `_make_walls()`（几何参考用）—— 正式房间已改为手工维护的 `.tscn`（room_1/2/3_medium/4_large），均含 `StaticBody2D` 墙体碰撞与 `NavigationPolygon`，房间碰撞体问题已于 2026-07-08 解决（详见架构待办 #7 ✅）。
- `scripts/battle/weapon_visual_base.gd` 的 `_draw()` —— 武器外观当前为调试占位绘制（红色圆点/线框），后续替换为真实贴图与挥砍动画。
（注：ResourceManager 的"未完成"已在 #19 中决议移除，故不作为代码 TODO。）

### 19. ResourceManager 文档中提及但完全不存在 ✅ 已修复

**文件**：`docs/项目实施规划.md` 提到 ResourceManager autoload，但无文件、无注册、无引用。

**修复**（✅ 已执行，2026-07-08）：经 grep 确认代码中无任何 ResourceManager 文件/注册/引用，且 `ResourceLoader.load()`/`preload()` 已满足需求。故决议不实现，从规划文档中移除该幽灵项：
- `docs/项目实施规划.md:19` 的"ResourceManager ✅ 基础完成"行改为 `❌ 已决议移除` 并注明原因。
- `docs/游戏策划文档.md:460` 的"通过 ResourceManager 管理配置数据"更正为直接 `load()`/`preload()` 加载。

### 20. project.godot 输入配置仅支持键鼠 ⏸ 暂缓（2026-07-08 用户决策）

**问题**：`[input]` 段所有动作仅绑定键盘/鼠标，无手柄支持。

**修复**：⏸ 用户明确指示暂不添加手柄支持，跳过此项。后续如需要可添加 JoyButton/JoyAxis 绑定。

---

## 架构层面建议

### A. 房间碰撞体问题（来自架构待办 #7）✅ 已解决（2026-07-08）

**根因**：原运行时加载的 `room_1.tscn` 等遗留场景无 `StaticBody2D` 墙体（`room_generator.gd` 产出的含墙场景 `room_small_test.tscn` 等因命名不一致未被 `.tres` 引用），导致玩家可穿墙。

**修复**：房间改为**手工维护的 `.tscn` 资产**（含纯几何 `StaticBody2D` 墙碰撞 + `NavigationPolygon` 导航网格 + `ColorRect` 占位地板与门光），不依赖美术资源；`room_generator.gd` 降级为几何参考工具。玩家 `collision_mask=4` 与墙 `collision_layer=4` 已匹配，`move_and_slide` 正常阻挡。
- `scenes/rooms/room_1.tscn` / `room_2.tscn` / `room_3_medium.tscn` / `room_4_large.tscn` 现已含墙体与障碍碰撞
- 未来房间设计直接在 Godot 编辑器细化这些 `.tscn`（门位、障碍、贴图）即可

### B. 敌人 config 访问方式不统一 ✅ 已修复（2026-07-08）

**原文件/代码**：`scripts/rooms/pickup_spawner.gd:24`（原审查文档误写为 `room_manager.gd:475`，#13 拆分后代码已搬迁）
```gdscript
# 旧：字符串探测属性，类型不安全
var cfg = enemy.config if "config" in enemy else (enemy._boss_config if "_boss_config" in enemy else null)
```
各敌人子类（`goblin`/`elite_*`/`boss_enemy`/`limb_boss`）存储配置字段名不统一（`config` vs `_boss_config`），迫使调用方做动态探测。

**修复**：在基类 `EnemyBase`（`scripts/battle/enemy_base.gd:13-20`）新增统一入口：
```gdscript
var _enemy_config: EnemyConfig = null
func get_config() -> EnemyConfig:
	return _enemy_config
```
6 个子类在各自的 `apply_config()` 第一行把入参赋给 `_enemy_config`（boss/limb 的 `_boss_config` 仍保留用于 BossConfig 专属相位值）。`pickup_spawner.gd:24` 改为：
```gdscript
var cfg = enemy.get_config() if enemy.has_method("get_config") else null
```
消除了类型不安全的属性探测，新增敌人子类只需在 `apply_config` 赋值即可被掉落/AI 模块统一读取。

### C. save_system 防御性处理并发 ✅ 已修复（2026-07-08）

GoldPickup 的频繁写盘问题（P0 #3）暴露了存档系统缺少节流/防抖机制。已于 `autoload/save_system.gd` 落地**内存缓存 + 防抖落盘**：

- 新增 `_lobby_cache` 内存缓存 + `_lobby_dirty`/`_lobby_flush_timer` 状态，`save_lobby_data()` 改为写缓存并启动 0.5s 防抖定时器（`LOBBY_FLUSH_INTERVAL`），由 `_flush_lobby()` 统一落盘（含 `FileAccess` 打开校验与 `push_error` 容错）。
- 新增 `flush_lobby_data()`（立即落盘并清脏标记）、`reset_lobby_data()`（同步清缓存 + 删文件）。
- `_exit_tree()` 兜底 flush，避免进程退出丢数据。
- 关键节点显式 flush：金币结算 `GameManager.end_run()`、附魔扣费 `EnchantmentTable` 均改为 `save_lobby_data()` + `flush_lobby_data()`，确保防抖窗口内不丢关键数据。

消除了此前「每次调用都读改写 + 直接落盘」带来的高频 IO 与潜在竞争；战斗内金币本就只在 `end_run` 落盘，符合「战斗内只存内存、结束统一持久化」原则。

---

## 优先级总览

| 优先级 | 编号 | 问题 | 工作量 | 状态 |
|--------|------|------|--------|------|
| **P0** | 1 | AudioManager 空壳 | 小 | ⏸ 暂缓（无音效资源，空壳为现状） |
| **P0** | 2 | GoldPickup 自动收集 bug | 极小 | ✅ 已修复 |
| **P0** | 3 | GoldPickup 频繁写盘 | 极小 | ✅ 已修复 |
| **P0** | 4 | SkillPickup 失败仍销毁 | 极小 | ✅ 已修复 |
| **P0** | 5 | KEY_K 调试后门 | 极小 | ⏸ 暂缓（用户保留，后续优化） |
| **P1** | 6 | room_builder/generator 重复 | 中 | ✅ 已修复（删除弃用分叉） |
| **P1** | 7 | 52 处裸 print() | 小 | ✅ 已修复（统一 Debug 工具接管） |
| **P1** | 8 | 拾取物缺基类 | 中 | ✅ 已修复 |
| **P1** | 9 | wave 属性字符串访问 | 小 | ✅ 已修复 |
| **P1** | 10 | _spawn_skill_reward 死代码 | 极小 | ✅ 已修复（直接删除） |
| **P2** | 11 | 硬编码房间中心坐标 | 小 | ✅ 已修复（提常量 ROOM_CENTER/DROP_CENTER） |
| **P2** | 12 | hud.gd 过大（1030→581 行） | 中 | ✅ 已修复（拆 4 个 class_name 子组件） |
| **P2** | 13 | room_manager.gd 过大（644→279 行） | 大 | ✅ 已修复（拆 WaveSpawner/PickupSpawner 两个 class_name 子组件） |
| **P2** | 14 | _spawn_wave 重复 | 小 | ✅ 已修复（提取 `_spawn_enemies_at_markers` 辅助函数，消除两处重复循环） |
| **P2** | 15 | Autoload 目录散落 | 小 | ✅ 已修复（7 个 autoload 统一到 autoload/，object_pool 归位 scripts/utils/） |
| **P2** | 16 | DamageSystem Dictionary | 中 | ✅ 已修复（新增 CombatStats 类型化类，calculate 改收 CombatStats，from_dict 对未知键告警） |
| **P3** | 17-20 | class_name/TODO/手柄 | 中 | ✅ #17-19 已修复；#20 暂缓（用户跳过手柄） |

---

## 做得好的地方

为了平衡，也列出项目**做得好的方面**，这些应保持：

1. **组件化架构清晰** — Movement/Weapon/StatusEffect/AI/Dodge/Sprint 七大组件解耦到位
2. **数据驱动彻底** — 武器/敌人/Boss/技能/装备/房间均用 `.tres` 配置，无硬编码数值散落
3. **对象池已接通** — 子弹池、粒子池（ColorRect）均已实现并使用，非空壳
4. **架构待办文档规范** — `docs/架构待办.md` 记录了 7 项技术债及解决状态，追踪良好
5. **EventManager 信号设计合理** — 系统间解耦通信，避免硬引用
6. **无注释掉的死代码** — 代码整洁度高
7. **错误处理有意识** — save_system、damageable 等核心系统有 `push_error` 使用

---

*报告结束。P0 的 #2/#3/#4 已修复；P1 的 #6（room_builder 分叉）、#7（裸 print）、#8（拾取物基类）、#9（wave 字符串访问）、#10（死代码）已全部修复；P2 的 #11（硬编码房间中心坐标）已修复为 `ROOM_CENTER`/`DROP_CENTER` 常量；P2 的 #12（hud.gd 过大）已拆分为 `StatusBars`/`DamageNumberSpawner`/`SkillBar`/`SkillChoiceUI` 四个 class_name 子组件，hud.gd 由 1030 行降至 581 行；P2 的 #13（room_manager.gd 过大）已拆分为 `WaveSpawner`/`PickupSpawner` 两个 class_name 子组件，room_manager.gd 由 644 行降至 279 行；P2 的 #14（_spawn_wave 内部敌人生成重复）已提取 `_spawn_enemies_at_markers` 辅助函数消除两处重复循环；P2 的 #15（Autoload 目录散落）已统一 7 个 autoload 到 `autoload/` 并将 `object_pool.gd` 归位 `scripts/utils/`；P2 的 #16（DamageSystem Dictionary）已新增类型化 `CombatStats` 类，`calculate`/`calculate_simple` 改收类型化参数，`from_dict` 对未知键告警以捕获拼写错误（`.tres` 序列化未强制改造，由告警兜底）。P0 剩余 #1（AudioManager 空壳）与 #5（KEY_K 调试后门）经用户决策暂缓处理——#1 因项目暂无音效资源、空壳属合理现状；#5 调试后门用户选择暂时保留、后续自行优化。P2 全部完成（#11~#16）；P3 的 #17（补全 class_name）、#18（TODO 标注）、#19（移除 ResourceManager 幽灵规划项）已修复，#20（手柄支持）经用户决策暂缓。架构层面建议 B（敌人 config 访问统一）已于 2026-07-08 通过 `EnemyBase.get_config()` 虚入口修复（消除字符串探测）；建议 C（save_system 并发防抖）亦于 2026-07-08 落地（内存缓存 + 0.5s 防抖落盘 + 关键节点显式 flush）。*

### 附：门失效回归（#13 验证中发现）

**问题**：清房后门会变绿（解锁），但走进门**没有任何反应**，无法推进 10 房间序列。

**根因**：`room_manager.gd` 的 `_on_door_entered` 把 `_load_room(door_direction)` 写在了 `if room_size == 3`（仅 BOSS 房）的分支内。序列为 `SMALL, SMALL, …BOSS…`，所以普通房间进门不触发换房，进度卡死。该守卫在拆分前即存在（非 #13 引入），但拆分后实测暴露。

**修复**（`scripts/rooms/room_manager.gd`）：
1. 把 `_load_room(door_direction)` 移出 BOSS 分支——**任意方向 / 任意房间**的门都通向序列下一房间，BOSS 房仅保留日志。
2. `_on_room_cleared` 改为**先 `_unlock_doors()` 再生成奖励**，即便奖励生成异常也不会把玩家卡在已清房间。

外部 API（`enter_first_room` / `escape_current_room` / `get_current_room_size` / `get_current_wave_index`）与门信号连接 `_connect_doors` 均不变。
