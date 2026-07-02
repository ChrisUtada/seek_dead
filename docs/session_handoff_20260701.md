# 会话交接 — 2026-07-01

## 本会话变更

### 技能系统最终定型（Pure DMD）

| 维度 | 旧状态 | 新状态 |
|------|--------|--------|
| 技能槽数 | 4（键位 1/2/3/4） | **2**（键位 1/2） |
| 治疗方式 | HealSkill 技能 | HealthPickup 血球（敌怪概率掉落） |
| 技能来源 | 仅精英三选一面板 | 房间清空 50% 技能光球 + 精英三选一面板 |
| 技能升级 | 拾取同名光球升级 Lv1→Lv4 | **取消升级**，纯拾取替换 |
| 满槽处理 | 替换弹窗（4 槽预览） | 替换弹窗（2 槽预览） |

### 已取消系统（策划清理）

- **PVP 模式** / **镶嵌系统** / **职业系统（驯兽师/炼金师/诗人）** / **基地系统** / **角色自定义**：从所有文档中标记为 ❌ 已取消，docs/*.md 同步清理

- **天赋树系统（Phase C）**：已完全移除，所有文件已删除，project.godot / player_controller / lobby 已回退

### 新增文件

| 文件 | 用途 |
|------|------|
| `scripts/equipment/health_pickup.gd` | 红色 + 血球拾取（碰触回血 `state.hp`） |
| `resources/bullets/elite_mage_bullet.tres` | 精英法师子弹（speed=600） |
| `resources/bullets/fire_boss_bullet.tres` | 火Boss子弹（speed=400） |
| `resources/bullets/limb_boss_bullet.tres` | 四肢Boss子弹（speed=600） |

### 修改文件

| 文件 | 变更 |
|------|------|
| `scripts/battle/skill_manager.gd` | `MAX_SLOTS` 4→2 |
| `scripts/rooms/room_manager.gd` | 敌死血球掉落（读 EnemyConfig.drop_heal/chance）、清空50%技能光球、精英三选一 |
| `scripts/resources/enemy_config.gd` | 新增 `drop_heal` / `drop_heal_chance` / `bullet_data` 字段 |
| `scenes/ui/hud.gd` | 技能栏 4→2 + 居中布局，替换弹窗适配 |
| `scripts/battle/player_controller.gd` | 技能键 4→2（1/2），删除 `_input` 合并到 `_unhandled_input` |
| `scripts/equipment/effect_executor.gd` | `_execute_spawn_pool`/`_execute_fire_aura`/`_execute_slow_enemies` flushing queries 修复 |
| `scripts/equipment/skill_pickup.gd` | 修复 `can_process` 检查 + `call_deferred` 构建 |
| `scripts/equipment/health_pickup.gd` | 修复 `call_deferred("_build_visual")` |
| `resources/enemies/*.tres` | 所有敌怪配置 `drop_heal` + `drop_heal_chance` |
| `resources/bosses/limb_boss.tres` | 含 `bullet_data`/`drop_heal`/`drop_heal_chance` |
| `scripts/battle/elite_mage.gd` | `bullet.data` 从 `config.bullet_data` 读取 |
| `scripts/battle/boss_enemy.gd` | `_make_bullet_data()` 回退 |
| `scripts/bosses/limb_boss.gd` | 同上 |
| `project.godot` | 回退天赋树 Autoload |
| `scenes/ui/lobby.gd` + `lobby.tscn` | 回退天赋树面板/入口 |

### 架构问题修复

- **Boss 配置数据流统一**：`boss_enemy.gd` 删除 `_apply_boss_config()` 硬编码，加入 `@export var config: BossConfig`，`_ready()` 走 `apply_config(config)` 数据驱动路径
- **RoomManager fallback 扩展**：硬编码 fallback 从 2 个房间（room_1/room_2）扩展为全部 5 个已知房间
- **子弹对象池**：确认已接通（`GameManager.get_bullet_pool()` 预分配 30 发，`weapon_node.gd` 远程攻击调用池 acquire）
- **visual_scene 冗余字段**：确认代码中已移除，无残留引用
- **tool_path 无效引用**：确认代码中已移除
- **技能硬编码**：确认已通过 Pure DMD 路线解决
- 以上所有项均更新 `docs/*.md` 对应条目为 ✅ 已修复

- **三选一面板居中**：手动视口坐标计算替代锚点预设
- **暂停/点击**：合并双 `_input`、`_choice_panel = null` 清理、PROCESS_MODE_ALWAYS 保活
- **flushing queries**：`health_pickup`/`skill_pickup`/`effect_executor` 用 `call_deferred` 加入场景树 + `monitoring=false` 初始关闭
- **config 引用**：`enemy.get("config")` → `"config" in enemy`

### 碰撞层

| Layer | 名称 | 值 |
|-------|------|-----|
| 1 | Player | 1 |
| 2 | Enemy | 2 |
| 3 | Environment | 4 |
| 4 | Pickup | 8 |
| 5 | Hazard | 16 |
| 6 | Hurtbox | 32 |
| 7 | Hitbox | 64 |

### 输入映射

| 动作 | 键 |
|------|-----|
| 技能槽 1 | 1 |
| 技能槽 2 | 2 |
| 武器主手 | Q |
| 武器副手 | E |
| 撤离 | Z |
| 闪避 | Shift |
| 冲刺 | Ctrl |

### 启动新会话注意事项

- 技能 2 槽，快捷键 1/2，替换弹窗自动适配
- `get_tree().paused = true` 在三选一面板弹出时暂停，HUD `process_mode = PROCESS_MODE_ALWAYS`
- `EnemyConfig` 的 `drop_heal > 0` 且 `randf() < drop_heal_chance` 时掉落血球
- `call_deferred("_build_visual")` 用于 Area2D 碰撞体创建
- 所有非逃跑技能通过 `SkillDatabase` 自动发现 `resources/skills/` 目录加载
- `SkillDatabase` 在 `SkillManager.MAX_SLOTS` 中屏蔽 EscapeSkill
- **最小改动原则**，先读所有 `docs/*.md`
- 编码约定：GDScript only, 640×360, NEAREST, no comments

---

## 前次会话 (2026-06-30)

### 当时已完成的装备系统 (Phases 0–7)

| 阶段 | 内容 |
|------|------|
| 0 | 房间波次刷新 + EquipmentBase/Enums |
| 1 | 基础装备架构（EquipmentManager, Inventory, Pickup, Drop） |
| 2 | 词缀系统（30条 affix, 9种 EffectExecutor 动作） |
| 3 | 掉落与品质（RarityTable, EquipmentDrop, RoomContext 缩放） |
| 4 | 套装系统（6套, 2pc stat + 3pc trigger, SetDatabase） |
| 5 | UI（EquipmentPanel 拖拽换装, ComparePopup, FloatingText, 快捷栏） |
| 6 | 大厅（Lobby.tscn NPC交互, Forging, Collection, SaveSystem） |
| 7 | 武器-装备统一（WeaponData Resource, archetype, 模板池） |

### 当时技能系统状态（Phase A+B 完成）

- ✅ SkillBase Resource（can_use/use/tick/冷却/能量）
- ✅ SkillManager（add_or_upgrade + 升星逻辑 + 替换信号）
- ✅ SkillPickup 场景+脚本
- ✅ 技能面板 UI（当时 4 槽，含等级小数字、冷却遮罩、能量不足变暗）
- ✅ 替换选择弹窗
- ✅ 掉落集成（精英三选一）
- ✅ EscapeSkill 独立不占槽
- ✅ 旧 DMD 桥接代码清理完毕
- ⚠️ 天赋树系统 Phase C 当时待办（本会话已删除）

### 当时待办（与本会话无关）

- 场景环境碰撞体
- RoomManager 硬编码 fallback
- 子弹对象池未接通
- Boss 配置数据流混乱
- 各武器碰撞体精细调整

### 当时碰撞层与输入

| Layer | 值 |
|-------|-----|
| Player | 1 |
| Enemy | 2 |
| Environment | 4 |
| Pickup | 8 |
| Hazard | 16 |
| Hurtbox | 32 |
| Hitbox | 64 |

| 输入 | 当时键位 |
|------|---------|
| inventory | I |
| return_lobby | U |
| 武器主/副手 | Q / E |
| 技能槽 1-4 | 1-4（本会话改为 2 槽） |
