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
│   ├── player_controller.gd        ← 主玩家逻辑，技能输入在 _process (Z/X/C/V/1-4)
│   ├── skill_manager.gd            ← SkillManager 节点，管理 Array[SkillBase]
│   ├── skill_base.gd               ← SkillBase Resource，含 can_use/use/tick
│   ├── skills/
│   │   ├── escape_skill.gd         ← 引导5s撤离技能（Z键, CD 90s）
│   │   ├── heal_skill.gd           ← 恢复50%HP
│   │   └── shockwave_skill.gd      ← 范围伤害+击退（CircleShape2D 物理查询）
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

### 技能系统现状

- `SkillBase`（Resource）已存在：`can_use(state)`, `use(user)`, `tick(delta)`, 冷却/能量管理
- `SkillManager`（Node）已存在：`add_skill()`, `use_skill(index, user)`, 信号 `skill_used`
- 3个实现技能：`EscapeSkill`（Z键引导撤离）, `HealSkill`, `ShockwaveSkill`
- 技能在 `player_controller.gd` 硬编码注册（约 260~280 行）
- 无技能面板 UI，无快捷键配置，无技能树
- `技能系统` 在 `docs/核心战斗功能完善规划.md` 中有详细设计（技能配置结构、技能栏UI方案、扩展点）

### 待办要点

1. **技能系统扩展**：Resource 驱动的技能配置、技能面板（快捷键绑定/拖拽）、技能树/天赋
2. **场景环境碰撞体**：玩家可走出导航网格，需在房间场景添加墙壁碰撞体
3. **RoomManager 硬编码 fallback**：room_1.tres / room_2.tres 路径硬编码
4. **子弹对象池未接通**：`projectile.gd` 的 `_pool` 从未被赋值
5. **Boss 配置数据流混乱**：硬编码 + 数据驱动两套入口打架
6. **各武器 .tscn 碰撞体精细调整**：CollisionShape2D 的位置/大小

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
| 技能快捷键 | Z / X / C / V（player_controller 硬编码）|

### 最近一次提交

`45523f2` — bump iron_sword attack_speed 1.2 -> 3.0
`e36619b` — melee hitbox in tscn + parent-level scale.x flip + grip point alignment

### 启动新会话注意事项

- 开始前先 `glob docs/*.md` 然后 `read` 所有文档
- 编码约定：GDScript only, 640×360, texture_filter=NEAREST, no comments unless complex
- 修改 `monitoring`/`monitorable` 必须用 `set_deferred`
- 使用组件化架构, 信号解耦, Resource 数据驱动
- 最少改动原则, 保持一致性
