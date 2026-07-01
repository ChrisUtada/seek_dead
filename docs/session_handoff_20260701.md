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

### 关键修复

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
