# 会话交接 — 2026-06-30

## 当前项目状态

### 已完成的装备系统 (Phases 0–7)

| 阶段 | 内容 | 状态 |
|------|------|------|
| 0 | 房间波次刷新 + EquipmentBase/Enums | ✅ |
| 1 | 基础装备架构（EquipmentManager, Inventory, Pickup, Drop） | ✅ |
| 2 | 词缀系统（30条 affix, 9种 EffectExecutor 动作, 条件/触发效果） | ✅ |
| 3 | 掉落与品质（RarityTable, EquipmentDrop, RoomContext 缩放） | ✅ |
| 4 | 套装系统（6套, 2pc stat + 3pc trigger, SetDatabase） | ✅ |
| 5 | UI（EquipmentPanel 拖拽换装, ComparePopup, FloatingText, 快捷栏） | ✅ |
| 6 | 大厅（Lobby.tscn NPC交互, Forging, Collection, SaveSystem, 流程重连） | ✅ |
| 7 | 武器-装备统一（WeaponData Resource, archetype, 模板池, 隐式修正） | ✅ |

### 武器系统关键决策

- **方向处理**：`WeaponComponent` 设 `scale.x = -1.0`（父级翻转），`WeaponVisualBase` 不设 scale.x（避免双重翻转抵消）
- **挥砍动画**：Tween 驱动，始终 `-half_arc → +half_arc`；碰撞体在 40% 处激活单帧
- **碰撞体**：在武器 `.tscn` 的 `HitboxArea` 子节点中可视化编辑，非代码生成
- **碰撞掩码**：melee hitbox `collision_mask = LAYER_HURTBOX`（原为 LAYER_ENEMY，从不被检测）
- **`monitoring`/`monitorable`** 修改用 `set_deferred`

### 文件结构

```
scripts/
├── battle/
│   ├── player_controller.gd        ← 主玩家逻辑，装备绑定的技能通过 EquipmentManager 下发给 PlayerSlots
│   ├── skill_manager.gd            ← SkillManager 节点，装备驱动的技能槽（最多4槽）
│   ├── skill_base.gd               ← SkillBase Resource，词缀/套装产出的技能效果
│   ├── skills/
│   │   ├── escape_skill.gd         ← 引导5s撤离技能（Z键, CD 90s，角色自带不占槽）
│   ├── weapon_node.gd              ← 通用武器节点（melee/ranged 分发）
│   ├── weapon_visual_base.gd       ← 武器视觉基类（GripPoint 锚点对齐）
│   ├── hitbox.gd / hurtbox.gd      ← 碰撞体脚本
│   ├── status_effect.gd            ← 状态效果系统
│   └── damage_system.gd            ← 伤害计算
├── components/
│   ├── weapon_component.gd         ← 武器组件（主副手, 方向翻转, 装备API）
│   ├── state_component.gd          ← 状态组件（hp, energy, stamina, move_speed 等）
│   ├── movement_component.gd       ← 移动组件
│   ├── dodge_component.gd          ← 闪避组件
│   └── sprint_component.gd         ← 冲刺组件
├── equipment/
│   ├── equipment_manager.gd        ← 装备管理器（信号路由, affix 触发, 全局修正）
│   ├── equipment_drop.gd           ← 掉落生成器
│   ├── equipment_pickup.gd         ← 地上拾取物
│   ├── forging.gd                  ← 锻造（升级/附魔/洗练/分解）
│   ├── collection.gd               ← 收藏系统（局外加成）
│   ├── effect_executor.gd          ← 词缀效果执行器
│   ├── weapon_data.gd              ← WeaponData Resource
│   └── ...
└── utils/
    └── save_system.gd              ← 存档（game_data + lobby_data 分离）
```

```
scenes/
├── player/knight.tscn              ← 骑士场景（含 WeaponComponent > Weapon > WeaponNode）
├── weapons/*.tscn                  ← 8个武器场景（5近战带HitboxArea + 3远程）
├── ui/
│   ├── lobby.tscn                  ← 大厅（door/NPC/exit + 铁匠/学者面板）
│   ├── equipment_panel.tscn        ← 装备面板（7槽位 + 6×2背包）
│   ├── compare_popup.tscn          ← 拾取对比弹窗（replace/keep/discard）
│   └── hud.tscn                    ← HUD
└── rooms/*.tscn                    ← 房间场景
```

```
resources/
├── weapon_templates/*.tres         ← 8个 WeaponData 资源模板
├── players/knight.tres             ← PlayerConfig（移动速度/血量/能量/体力）
├── rooms/*.tres                    ← RoomConfig 资源
├── affix_database.tres             ← 词缀数据库
├── set_database.tres               ← 套装数据库
└── bullets/default_bullet.tres     ← 默认子弹 BulletData
```

### 技能系统现状（纯 DMD 路线）

设计原则：技能是独立于装备的 blessing 式系统。技能作为独立掉落物拾取，直接进入技能槽。升级靠拾取同名技能。与装备系统完全解耦。

| 维度 | 说明 |
|------|------|
| 技能来源 | 独立掉落（SkillPickup 光球），不绑在装备上 |
| 技能槽 | 4 个主动技能槽，键位 1/2/3/4 |
| 升级方式 | 拾取同名技能光球 → 槽内技能等级 +1（Lv1→Lv4） |
| 替换规则 | 槽满且无同名 → 弹替换选择（替换某个已有技能或放弃） |
| 被动效果 | 词缀的 StatModifier/ConditionalBonus 直接作用于角色，不占技能槽 |
| EscapeSkill | 角色固有（Z键引导撤离，90s CD），不占 4 槽 |
| 构筑导向 | 技能是对词缀 synergy 的补充，通过独立拾取管线获取 |

当前实现：
- ✅ SkillBase Resource 框架就位（can_use/use/tick/冷却/能量）
- ✅ SkillManager 已重写（add_or_upgrade + 升星逻辑 + 替换信号）
- ✅ SkillPickup 场景+脚本已就位（光球+拾取检测+SkillManager.add_or_upgrade）
- ✅ 技能面板 UI：4槽底部居中，含等级小数字、冷却遮罩、能量不足变暗
- ✅ 升级浮动文字（"+1 Lv.X!"）
- ✅ 替换选择弹窗（4槽预览+放弃按钮）
- ✅ 掉落集成：精英怪死亡触发三选一技能面板
- ✅ EscapeSkill 独立为 player.escape_skill，不占 4 槽
- ⚠️ 旧 DMD 桥接代码保留待清理（Phase B） → ✅ 已清理

### 待办要点

1. **SkillPickup 实现（Phase A ✅）**：
    - [x] 新建 `scripts/equipment/skill_pickup.gd`（Area2D + 光球 + collision + 拾取检测 + SkillManager.add_or_upgrade）
2. **SkillManager 重写（Phase A ✅）**：
    - [x] `add_skill()` → `add_or_upgrade(skill: SkillBase) → bool`
    - [x] 升级逻辑：遍历 4 槽找同名 → 等级+1 或填入空槽
    - [x] 槽满替换信号 `skill_replace_needed(new_skill)`
    - [x] EscapeSkill 分离为 player.escape_skill，不经过 SkillManager（已有）
3. **技能面板 UI（Phase A ✅）**：
    - [x] 4槽底部居中 HUD（图标+冷却遮罩+能量不足变暗）— 已有
    - [x] 等级小数字显示（右下角）
    - [x] 绿色升级浮动 "+1 Lv3!"
    - [x] 替换选择弹窗（4槽预览 + 放弃按钮）
4. **掉落集成（Phase A ✅）**：
    - [x] 精英怪击杀触发三选一技能面板（取代旧固定掉落）
    - [x] RoomManager 新增 `_on_enemy_died` + `_show_skill_choice()`
5. **清理旧绑定（Phase B ✅）**：
    - [x] 删除 `EquipmentBase.granted_skill` 字段
    - [x] 删除 `Affix.granted_skill` 字段
    - [x] 删除 `SetBonus.bonus_3pc_skills` 字段
    - [x] EquipmentManager 移除所有技能桥接逻辑
    - [x] SetBonusManager 移除套装技能桥接逻辑
    - [x] 删除 EffectAction.ACTIVATE_SKILL 枚举值 + 处理器 + trigger_effect.skill 字段
    - [x] 删除 affix_database 中 _skill_31 / _skill_32 两条词缀
    - [x] 删除 EquipmentDrop._try_grant_skill / SKILL_TEMPLATES / SKILL_CHANCE
    - [x] 删除神秘外卖套 bonus_3pc_skills
    - [x] 删除 player_controller 调试戒指 granted_skill
    - [x] 删除 SkillManager.add_skill / remove_skill 兼容方法
6. **天赋树系统（Phase C）**：
    - [ ] TalentNode Resource（4分支，共24+节点）
    - [ ] TalentManager 节点（解锁/资源消耗/存档对接）
    - [ ] 天赋碎片获取（通关房间+1，Boss+5）
    - [ ] Lobby 天赋面板 UI（节点可视化+升级按钮+资源预览）
    - [ ] EquipmentDrop 对接 TalentManager 过滤解锁词缀/武器池
    - [ ] 菱形关键节点实现（不屈意志/武器大师/双重词缀/传奇猎手等）
7. **场景环境碰撞体**：玩家可走出导航网格，需在房间场景添加墙壁碰撞体
8. **RoomManager 硬编码 fallback**：room_1.tres / room_2.tres 路径硬编码
9. **子弹对象池未接通**：`projectile.gd` 的 `_pool` 从未被赋值
10. **Boss 配置数据流混乱**：硬编码 + 数据驱动两套入口打架
11. **各武器 .tscn 碰撞体精细调整**：CollisionShape2D 的位置/大小

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
| `inventory` | I |
| `return_lobby` | U |
| 武器主/副手 | Q / E |
| 技能槽 1-4 | 1 / 2 / 3 / 4 |

### 最近一次提交

`45523f2` — bump iron_sword attack_speed 1.2 -> 3.0
`e36619b` — melee hitbox in tscn + parent-level scale.x flip + grip point alignment

### 启动新会话注意事项

- 开始前先 `glob docs/*.md` 然后 `read` 所有文档
- 编码约定：GDScript only, 640×360, texture_filter=NEAREST, no comments unless complex
- 修改 `monitoring`/`monitorable` 必须用 `set_deferred`
- 使用组件化架构, 信号解耦, Resource 数据驱动
- 最少改动原则, 保持一致性
