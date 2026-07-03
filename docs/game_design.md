# 《Seek Dead》完整策划文档 — AI 可读版

| 版本 | 日期 | 说明 |
|------|------|------|
| v1.0 | 2026-06-30 | 全系统整合，合并 docs/*.md 为一站式参考 |
| v1.1 | 2026-07-01 | 同步代码现状：修复技能/装备/Lobby/待办等不准确描述，补充天赋树设计 |
| v1.2 | 2026-07-03 | 5→3品质简化、SET标签化、词缀槽位过滤、锻造删除、Collection瘦身、Lobby资源简化、Gold + 附魔台实现 |

---

## 一、项目总览

### 1.1 基本信息

| 项目 | 内容 |
|------|------|
| 英文名 | Seek Dead |
| 中文名 | 寻死者 |
| 类型 | 俯视角动作 RPG，单人/合作/循环 |
| 引擎 | Godot 4.x (GDScript only, 无 C#) |
| 分辨率 | 设计 640×360，窗口 1280×720，stretch/mode=canvas_items |
| 方向 | 像素风，texture_filter = NEAREST |
| 世界观 | 你是超级外卖员，职责是每 12 小时清理一次被遗忘的外卖柜。柜门背后不只是残羹冷炙——有些承载强烈情感的外卖（生日蛋糕、订婚套餐）长期无人认领会"腐化"成为怪物。每清完一层深入一层，直到击败最深处 Boss（腐化贵重外卖）取出"残余物"。日常 × 超自然恐怖，类似《Control》。 |

### 1.2 目录结构

```
ssz/
├── autoload/                  # 全局单例（GameManager, EventManager, SaveSystem, SceneManager, RoomManager, AudioManager, EntityRegistry）
├── scripts/
│   ├── battle/                # 战斗核心（player_controller, enemy_base, weapon_node, weapon_visual_base, hitbox, hurtbox, damage_system, status_effect, collision_system, ammo_system, skill_manager, skill_base）
│   │   └── skills/            # 技能实现（escape_skill, shockwave_skill）
│   ├── components/            # 组件化系统（weapon_component, movement_component, state_component, ai_component, boss_ai_component, dodge_component, sprint_component, status_effect_component）
│   ├── equipment/             # 装备系统（equipment_manager, equipment_drop, equipment_pickup, equipment_inventory, equipment_base, effect_executor, forging, collection, weapon_data, rarity_table, affix_database, set_database, reward_ui, etc）
│   ├── rooms/                 # 房间系统（room_manager, room_config, wave_config, 房间场景脚本）
│   ├── ui/                    # UI 组件（hud, shadow, weapon_visual, equipment_panel, lobby）
│   ├── systems/               # 系统（entity_registry）
│   ├── resources/             # Resource 定义（player_config, enemy_config, boss_config, bullet_data）
│   └── utils/                 # 工具（save_system, object_pool）
├── scenes/
│   ├── ui/                    # 场景 UI（main_menu, hud, lobby, equipment_panel, compare_popup）
│   ├── player/                # 玩家场景（player.tscn, knight.tscn）
│   ├── enemies/               # 敌人场景（skeleton.tscn, goblin.tscn）
│   ├── weapons/               # 武器场景（8个武器 .tscn）
│   ├── battle/                # 战斗场景（test_enemy, boss_enemy, projectile）
│   └── rooms/                 # 房间场景（room_1~4, room_boss）
├── resources/
│   ├── players/               # PlayerConfig .tres（knight/warrior/mage）
│   ├── weapon_templates/      # WeaponData .tres（8个武器模板）
│   ├── rooms/                 # RoomConfig .tres
│   ├── enemies/               # EnemyConfig .tres
│   └── bullets/               # BulletData .tres
├── assets/                    # 像素资源
└── docs/                      # 文档
```

### 1.3 Autoload 注册

| 名称 | 路径 | 用途 |
|------|------|------|
| GameManager | autoload/game_manager.gd | 全局状态管理、暂停/恢复 |
| EventManager | autoload/event_manager.gd | 全局信号事件分发 |
| EntityRegistry | scripts/systems/entity_registry.gd | 玩家/敌人注册与查询 |
| SaveSystem | scripts/utils/save_system.gd | JSON 存档/读档（game_data + lobby_data 分离） |
| SceneManager | autoload/scene_manager.gd | 场景切换+淡入淡出 |
| AudioManager | autoload/audio_manager.gd | 音频播放（空壳） |
| RoomManager | scripts/rooms/room_manager.gd | 房间生成/波次管理 |

### 1.4 碰撞层

| Layer | 名称 | bit 值 | 用途 |
|-------|------|--------|------|
| 1 | PLAYER | 1 | 玩家碰撞体 |
| 2 | ENEMY | 2 | 敌人碰撞体 |
| 3 | ENVIRONMENT | 4 | 墙壁/障碍物 |
| 4 | PICKUP | 8 | 地上拾取物 |
| 5 | HAZARD | 16 | 环境危险物 |
| 6 | HURTBOX | 32 | 受击框（敌人受伤区域） |
| 7 | HITBOX | 64 | 攻击框（武器判定区域） |

### 1.5 输入映射

| 动作 | 键 | 用途 |
|------|-----|------|
| move_forward/backward/left/right | WASD / 方向键 | 移动 |
| 鼠标左键 | — | 攻击 |
| Shift | shift | 闪避 |
| Ctrl | ctrl | 冲刺 |
| R | R | 手动装弹 |
| Z | Z | 紧急撤离（引导5s） |
| 1 | 1 | 技能槽 1 |
| 2 | 2 | 技能槽 2 |
| Q | Q | 武器主手 |
| E | E | 武器副手 |
| I | I | 打开装备面板 |
| U | U | 返回大厅 |
| K | K | 调试刷装备 |
| Esc | Esc | 暂停菜单 |

---

## 二、已完成系统

### 2.1 全部已完成

| 系统 | 状态 | 说明 |
|------|------|------|
| GameManager | ✅ | 全局状态管理、暂停/恢复 |
| EventManager | ✅ | 全局信号事件分发（伤害、死亡、房间清空等） |
| SceneManager | ✅ | 场景切换+淡入淡出过渡 |
| SaveSystem | ✅ | JSON 存档/读档（F5/F9），lobby_data 单独保存 |
| EntityRegistry | ✅ | 玩家/敌人注册与查询 |
| AudioManager | ⚠️ 空壳 | SfxType 枚举 + play_sfx 接口，无声 |
| ObjectPool | ✅ | RefCounted 泛型对象池（预分配+acquire/release） |
| DamageSystem | ✅ | 8种伤害类型、属性克制、暴击、命中结果枚举 |
| StateComponent | ✅ | HP/能量/体力/热量 + 自动回复 + 超载 Meltdown |
| StatusEffect | ✅ | 3种 DoT（中毒/燃烧/流血），RefCounted 架构 |
| CollisionSystem | ✅ | 7层碰撞配置静态工具类（bit/mask） |
| 阴影系统 | ✅ | shadow.gd 独立组件，@export 参数 |
| 粒子池化 | ✅ | ColorRect 池化替换 instantiate/free |

### 2.2 武器系统

**已完成**：
- WeaponData Resource 统一架构（archetype/隐式修正/melee+ranged 字段）
- Tween 驱动挥砍动画（始终 `-half_arc → +half_arc`，父级 scale.x 翻转自动镜像）
- 碰撞体在武器 .tscn 的 HitboxArea 节点中可视化编辑（方案 B）
- hitbox collision_mask = LAYER_HURTBOX（修复原 LAYER_ENEMY 不匹配）
- 主副手双持（数字键 1/2 切换，轻型武器可双持）
- 远程子弹系统（projectile、对象池、碰撞层 HITBOX/HURTBOX）
- 武器切换状态机重置
- GripPoint 锚点对齐（Marker2D "GripPoint" 定位握把位置）
- 方向处理层级：WeaponComponent scale.x 翻转（父级）→ WeaponVisualBase 不翻转（避免双重翻转抵消）
- 8个武器 .tscn 场景 + 8个 .tres 模板

| 武器 | 类型 | 双持 | Archetype |
|------|------|------|-----------|
| 铁剑 | 近战 MEDIUM | false | MEDIUM |
| 火焰剑 | 近战 MEDIUM | false | MEDIUM |
| 战斧 | 近战 HEAVY | false | HEAVY |
| 匕首 | 近战 LIGHT | true | LIGHT |
| 毒匕首 | 近战 LIGHT | true | LIGHT |
| 手枪 | 远程 MEDIUM | true | MEDIUM |
| 冰霜枪 | 远程 LIGHT | true | LIGHT |
| 火焰法杖 | 远程 MAGIC | false | MAGIC |

**待优化**：
- 不同武器需不同的 `visual_offset`（铁剑/战斧/手枪大小差异），当前默认 Vector2.ZERO，需逐 .tres 填写
- 可在 WeaponData 中加 `visual_scale` 属性控制缩放

**初始装备配置**：主手铁剑（近战），副手手枪（远程）

**武器隐式修正**（Archetype，不占词缀槽）：

| Archetype | 修正 |
|-----------|------|
| LIGHT | +10% 攻速，-20% 伤害 |
| MEDIUM | 无 |
| HEAVY | +20% 伤害，-10% 攻速，+100 击退 |
| MAGIC | +15% 伤害，-10% 攻速 |

### 2.3 装备系统（Phases 0–7）

> 本节 §二.3 描述的设计已全部实现（改造于 v1.2 完成）。

| Phase | 内容 | 状态 |
|-------|------|------|
| 0 | 房间波次刷新 + Boss 门锁 + 紧急撤离技能 | ✅ |
| 1 | 装备基础架构（EquipmentBase/EquipmentManager/Inventory） | ✅ |
| 2 | 词缀系统（30条、EffectExecutor 9种动作、TriggerEffect/ConditionalBonus） | ✅ |
| 3 | 掉落与品质（RarityTable 3品质、EquipmentDrop、Pickup、RoomContext 缩放） | ✅ |
| 4 | 套装系统（6套、SetBonus Resource、SetBonusManager、SET标签化） | ✅ |
| 5 | UI（EquipmentPanel 拖拽、FloatingText、Set激活提示、ComparePopup 已删除） | ✅ |
| 6 | Lobby（资源简化 gold+talent_shards、Collection记录、无锻造） | ✅ |
| 7 | 武器-装备统一（WeaponData 内嵌 Resource、模板池、archetype 隐式修正） | ✅ |

**7个装备槽位**（无基础属性，装备价值 100% 来自词缀）：

| 槽位 | 数量 | 说明 |
|------|------|------|
| WEAPON_MAIN | 1 | 武器数据（WeaponData），决定攻击方式和伤害类型 |
| WEAPON_OFFHAND | 1 | 武器数据（仅双持武器可用） |
| HELMET | 1 | 纯词缀槽，生存类词缀池 |
| BODY | 1 | 纯词缀槽，生存类词缀池 |
| HAND | 1 | 纯词缀槽，机动/进攻类词缀池 |
| LEG | 1 | 纯词缀槽，机动类词缀池 |
| ACCESSORY | 2 | 纯词缀槽，全词缀池（构筑核心） |

**3种品质**：

| 品质 | 色 | 词缀数 | 掉落权重 |
|------|-----|--------|---------|
| MAGIC（蓝） | 蓝 | 1 | 60% |
| RARE（金） | 金 | 2 | 30% |
| LEGENDARY（红） | 红 | 3 + 独特效果 | 10% |

> 删除了 COMMON（白板无意义）和 SET（降为标签，见下文）。
> 每件掉落至少 1 条词缀，每件都能影响构筑。
> LEGENDARY 与 RARE 质的差距：额外一条独特效果（不可镶嵌，不可替代）。

**属性管线**：玩家最终属性由三层叠加，装备槽位不再提供白送基础值。

```
最终属性 = 职业底值 + 天赋树(跨局永久) + 词缀(局内构筑)
```

| 属性来源 | 举例 | 性质 |
|---------|------|------|
| 职业底值（PlayerConfig） | 骑士 HP200/体力100/移速200 | 开局固定，换职业变 |
| 天赋树解锁 | 坚韧 I→III（HP+30/+60/+100） | 跨局永久，全职业共享 |
| 词缀（局内装备掉落） | 活力(+80HP) / 铁壁(+0.15全防) | 局内构筑，更换装备动态变化 |

> 职业底值是玩家初始能力的基础，天赋树是成长追求，词缀是构筑选择。
> 装备本身没有"这件比那件多 5 点防御"——区别全在词缀组合上。

**词缀槽位过滤**：每个词缀有明确的可用槽位范围，避免荒诞组合。饰品（ACCESSORY）不受限制，出任何词缀都有可能：

| 槽位 | 可用词缀 | 设计思路 |
|------|---------|---------|
| WEAPON（主/副手） | 进攻数值（#2-10*）、所有触发类（#11-22）、条件类（#23/25/27/29） | 武器决定攻击风格，触发效果和条件增伤 |
| HELMET/BODY（头/身） | 防御数值（#1/4/5）、生存触发（#17）、生存条件（#26/30） | 防具提供生存基础 |
| HAND/LEG（手/腿） | 机动数值（#8-9）、部分条件（#24/28） | 手足决定操作手感 |
| ACCESSORY（饰品） | **全部词缀**，无限制 | 饰品是构筑拼图的核心 |

\*#2 狂怒/#3 疾风/#6 灵巧/#7 致命/#10 元素专精/#8 迅捷等武器相关进攻数值

**套装**（降为标签，不再独立品质）：

| 套装 | 2件 | 3件 |
|------|-----|-----|
| 腐化外卖员 | 移速+20%，闪避CD-0.3s | 击杀25%掉落补给 |
| 烈焰配送 | 火焰伤害+40%，燃烧伤害+50% | 燃烧死亡留下火径 |
| 冰封仓库 | 冰霜伤害+40%，冻结时间+50% | 冻结死亡产生冰霜新星 |
| 毒物实验室 | 毒素伤害+50%，中毒时间+100% | 中毒死亡留下毒云 |
| 高压电柜 | 雷电伤害+40%，暴击率+10% | 暴击时闪电新星全屏 |
| 神秘外卖 | 全伤害+20%，资源回复+30% | 每清空房间随机属性+3% |

**房间附魔台**（替代锻造，有限可控性）：

每个房间低概率（约20%）生成附魔台，提供词缀操作：

| 操作 | 消耗 | 效果 |
|------|------|------|
| 重铸 | 金币 300 | 重随装备一条指定词缀的数值 |
| 转移 | 金币 500 + 消耗一件装备 | 将消耗装备的一条词缀转移到目标装备空位 |

**经济系统**：

| 资源 | 用途 | 来源 | 性质 |
|------|------|------|------|
| 金币 | 附魔台操作 | 怪物击杀(10~25)、精英击杀(50~100)、Boss(200~500)、出售装备 | 局内消耗，每局重置 |
| 天赋碎片 | 天赋树解锁 | 清空房间(+1)、Boss击杀(+5) | 跨局累积，永久保留 |

> 一局 10 房间正常收入约 800~1500 金币，够 2~3 次操作或攒着不用。
> 不出附魔台的房间，装备全靠掉落随机——这正是 DMD 的核心："掉到什么用什么"。
> 附魔台、HealthPickup（血球）、SkillPickup（技能光球）三者都是房间内放置物，不相互挤占掉落位。

### 2.4 玩家/角色

| 系统 | 状态 |
|------|------|
| PlayerController | ✅ 玩家控制（移动/攻击/技能/闪避/冲刺/装弹/装备面板/调试） |
| StateComponent | ✅ HP/能量/体力/热量 + 自动回复 + 超载 Meltdown + 移速/攻速/暴击等 exports |
| MovementComponent | ✅ 移动速度控制 |
| DodgeComponent | ✅ Shift 闪避 150px + 无敌 0.2s + 消耗15体力 + 减热15 |
| SprintComponent | ✅ Ctrl 冲刺 1.5x + 10体力/s |
| AmmoSystem | ✅ 30发/2秒装弹/R键手动/自动装弹/HUD标红 |
| 多职业 PlayerConfig | ✅ knight/warrior/mage 三套 .tres |
| 角色朝向 | ✅ sprite flip_h + WeaponComponent scale.x 翻转 |
| 紧急撤离 | ✅ Z键引导5s + 90s CD + 受伤/操作打断 + RoomManager.escape_current_room() |

### 2.5 敌人系统

| 系统 | 状态 |
|------|------|
| EnemyBase | ✅ 抽象基类（HP/闪白/状态效果/击退/血条） |
| BasicEnemy (goblin/skeleton) | ✅ 通用 AIComponent 巡逻/追击/攻击 |
| BossEnemy (limb_boss) | ✅ BossAIComponent 三阶段（猛击AoE/冲锋/远程散射） |
| AIComponent | ✅ IDLE/WANDER/CHASE/ATTACK 状态机 |
| BossAIComponent | ✅ 三阶段 HP 阈值（60%/30%） |
| Navigation | ✅ NavigationRegion2D + NavigationAgent2D |
| 行为树框架 | ✅ Selector/Sequence/Condition/Action/Invert/Cooldown |
| EnemyConfig/BossConfig/LootEntry | ⚠️ 骨架定义，待完善 |
| 精英敌人 | ❌ 未实现 |

### 2.6 UI

| UI | 状态 |
|----|------|
| HUD | ✅ HP/能量/体力/热量 tween条 + 弹药 + 技能冷却 + 准星 |
| 浮动伤害 | ✅ 数字上飘，暴击金色/普通白色 |
| 敌人血条 | ✅ 头顶血条 + 状态图标 |
| Boss血条 | ❌ 未实现 |
| 暂停菜单 | ✅ Esc暂停/继续 |
| 死亡画面 | ✅ "你死了" + 提示 |
| 屏幕震动 | ✅ Camera2D 随机偏移 |
| 主菜单 | ✅ 标题画面 + 开始/继续/退出 |
| EquipmentPanel | ✅ I键 7槽+6×2背包+属性总览+拖拽换装 |
| RewardUI | ✅ 房间清空选装备（3选1） |
| 技能界面 | ❌ 未实现 |

> ComparePopup 已删除（战斗中打断节奏）。背包管理改为自动流程：拾取时若背包未满则直接拾取，若已满则替换最旧装备。玩家可在 I 键面板中手动管理。

### 2.7 Lobby

- lobby.tscn 节点树（背景/标题/资源标签/门精灵/铁匠NPC视觉遗留/学者NPC/返回按钮）
- 资源仅 gold（金币） + talent_shards（天赋碎片），去除旧四种材料（iron/magic_essence/legendary_core）
- 锻造面板已废弃（forging.gd 内容已清空），ForgeArea/ForgePanel 节点保留为编辑器视觉遗留
- 收集面板仅保留记录展示（无全局加成）
- 游戏流程：MainMenu → Lobby → Game → death → Lobby
- SaveSystem.lobby_data 持久化（gold/talent_shards/collection_record）

> 锻造已删除，替代为房间内附魔台。铁匠NPC节点保留但无交互功能。

---

## 三、架构决策

### 3.1 组件化架构

战斗单位 = 多个组件组合（非继承树）：

```
EnemyBase
├── StateComponent (HP/能量/体力)
├── MovementComponent
├── StatusEffectComponent
├── AIComponent / BossAIComponent
├── Hurtbox / Hitbox
└── WeaponComponent (仅玩家)
```

### 3.2 状态机

使用 enum + match 单类实现，带 `_enter_*` 和 `_exit_*` 生命周期注释风格。

### 3.3 信号解耦

系统间通信走 EventManager 信号，不使用直接引用：

| 信号 | 触发 |
|------|------|
| EventManager.damage_dealt | 武器命中时 |
| EventManager.enemy_died | 敌人死亡时 |
| EventManager.room_cleared | 房间清空时 |
| EventManager.skill_used | 使用技能时 |
| EventManager.equipment_changed | 装备变更时 |
| EventManager.trigger_event | 词缀触发时（对接 EffectExecutor） |

### 3.4 数据驱动优先

使用 Resource (.tres) 配置，不用 JSON：
- PlayerConfig、EnemyConfig、BossConfig、WeaponData、RoomConfig、BulletData
- AffixDatabase、SetDatabase 集中管理

### 3.5 WeaponDirection 方向处理层级

```
WeaponComponent.set_aim_direction(dir)
  ├─ scale.x = -1.0 if dir.x < 0 else 1.0   （父级翻转，影响整个子树）
  └─ _weapon_node.set_aim_direction(dir)     （同步节点状态，子弹方向用）

WeaponNode.set_aim_direction(dir)
  ├─ aim_direction = dir
  └─ _weapon_visual.set_aim_direction(dir)

WeaponVisualBase.set_aim_direction(dir)
  └─ aim_direction = dir  （不设 scale.x，避免双重翻转抵消）

挥砍 Tween：始终 -half_arc → +half_arc，父级 flip 自动镜像视觉
```

### 3.6 每步必验

每完成一个功能模块后必须进行调试验证再提交，方式包括：
- K 键调试生成装备
- print 输出关键状态
- 游戏内实测
- 检查日志确认无报错

---

## 四、房间生成系统

### 4.1 房间尺寸分级

| 尺寸 | 比例 | 波次 | 怪物数/波 |
|------|------|------|-----------|
| SMALL | 40% | 1 | 6-8 |
| MEDIUM | 35% | 2 | 8-12 |
| LARGE | 20% | 3 | 12-18 |
| BOSS | 5% | 3 | 14-18 + Boss |

### 4.2 一局流程（10房间）

```
房间 1-2:  小 ← 上手发育
房间 3-4:  中/大 ← 构筑初体验
房间 5-7:  中/大 + BOSS(随机1间) ← 构筑验证，可跳 Boss
房间 8-10: 中/大 ← 构筑全力运转
```

### 4.3 波次触发条件

- ON_START（进门立即刷）
- ENEMIES_LEFT(n)（场上剩 n 只时刷下一波）
- TIMER(n)（n 秒后自动刷）
- BOSS_PHASE(n)（Boss HP 低于 n% 时刷）

### 4.4 房间内放置物

每个房间（SMALL/MEDIUM/LARGE）有概率生成放置物，不相互挤占：

| 放置物 | 概率 | 功能 |
|--------|------|------|
| 技能光球 | 50% | 清空后掉落，见 §五 |
| 附魔台 | ~20% | 重铸（300金）或 转移（500金+消耗装备），见 §二.3.1 |
| HealthPickup | 敌怪掉落 | 血球，见 §五.4 |
| GoldPickup | 敌怪掉落（60%） | 金币 10~25（默认），见 §二.3 经济系统 |

> 附魔台不出现在 BOSS 房间。
> 金币也受 EnemyConfig.drop_gold 字段覆盖控制。

---

## 五、技能系统（纯 DMD 路线）

设计原则：**技能是独立于装备的 blessing 式系统**。技能作为独立掉落物拾取，直接进入技能槽。**拾取同名技能升级**（Lv1→Lv4），满槽无同名时触发替换选择。与装备系统完全解耦。治疗由 HealthPickup（敌怪血球掉落）替代，不占用技能槽。

### 5.1 技能槽

- **2 个主动技能槽**，对应键位 1/2
- EscapeSkill 固定 Z 键，不占 2 槽
- 空槽显示为灰色空格

### 5.2 技能获取与替换

| 触发 | 行为 |
|------|------|
| 拾取技能光球，有空槽 | 填入空槽 |
| 拾取技能光球，槽位已满 | 弹替换选择：替换某个已有技能，或放弃 |
| 房间清空 | 50% 概率掉落一个技能光球 |
| 精英死亡 | 触发三选一面板（三个技能选一） |

### 5.3 技能来源（掉落管线）

| 来源 | 说明 |
|------|------|
| 房间清空 | 50% 概率掉落技能光球 |
| 精英/Boss 击杀 | 三选一面板（必定触发） |
| 宝箱 | 概率产出技能（待实现） |

### 5.4 HealthPickup（血球）

治疗由敌怪掉落 HealthPickup 替代（红色 + 标识），不占技能槽：
- `EnemyConfig.drop_heal`：回复量
- `EnemyConfig.drop_heal_chance`：掉落概率（0.0~1.0）
- 碰触自动回血 `state.hp += drop_heal`
- 所有敌怪 `.tres` 配置独立数值（哥布林 8-20%、骷髅 10-25%、精英法师 20-60%、Boss 30-80%）

### 5.5 SkillManager 职责

```gdscript
class_name SkillManager
extends Node

const MAX_SLOTS: int = 2

var skills: Array[SkillBase]            # 2槽，null=空
var max_level: int = 4

func add_or_upgrade(skill: SkillBase) -> bool
  # 有同名且未满级 → 升级（等级+1），返回 true
  # 有空槽 → 填入，返回 true
  # 无同名且槽满 → 触发 skill_replace_needed 信号 → HUD 弹替换选择，返回 false

func replace_skill(slot_index: int, skill: SkillBase)
  # 替换指定槽位的技能

func use_skill(slot_index: int, user: Node2D) -> bool
signal skill_equipped(slot_index, skill)
signal skill_removed(slot_index)
signal skill_replace_needed(new_skill: SkillBase)  # UI 弹选择
```

### 5.6 当前实现状态

| 组件 | 状态 | 说明 |
|------|------|------|
| SkillBase Resource | ✅ | can_use/use/tick/冷却/能量管理 |
| SkillManager Node | ✅ | 2槽 + add_or_upgrade + replace_skill + 替换信号 |
| SkillPickup | ✅ | 蓝色技能光球 + 拾取检测 + SkillManager.add_or_upgrade |
| HealthPickup | ✅ | 红色 + 血球 + 碰触回血 |
| 技能面板 UI | ✅ | 2槽底部居中 + 冷却遮罩 + 能量不足变暗 |
| 替换选择弹窗 | ✅ | 2槽预览 + 放弃按钮 |
| 掉落集成（清空） | ✅ | RoomManager 50% 概率丢技能光球 |
| 掉落集成（精英） | ✅ | RoomManager 三选一面板 |
| 技能数据库 | ✅ | SkillDatabase 自动发现 `resources/skills/` 目录加载，过滤 EscapeSkill |
| HealSkill | ❌ 已删除 | 被 HealthPickup 替代 |
| EscapeSkill | ✅ | Z 键引导撤离，90s CD，角色固有 |

### 5.7 清理项（已完成）

- ✅ 删除 `EquipmentBase.granted_skill` 字段
- ✅ 删除 `Affix.granted_skill` 字段
- ✅ 删除 `SetBonus.bonus_3pc_skills` 字段
- ✅ 从 EquipmentManager 中移除所有技能桥接逻辑

---

## 六、局外天赋树

设计目标：**跨局永久成长系统**。天赋碎片由通关房间/Boss获得，用于解锁天赋节点。天赋树独立于装备和技能，提供底层数值基础和构筑可能性。

### 6.1 核心规则

| 规则 | 说明 |
|------|------|
| 资源 | 天赋碎片（通关房间+1，Boss+5） |
| 节点类型 | 普通节点（+1级） + 菱形关键节点（一次性解锁） |
| 每节点消耗 | 天赋碎片 + 金币（少量） |
| 重置 | 可重置回收部分碎片 |

### 6.2 四分支

| 分支 | 色 | 定位 | 关键节点 |
|------|-----|------|---------|
| 生存（绿） | 绿 | HP/防御/回复 | 不屈意志：HP归零时3s无敌（1次/局） |
| 战斗（红） | 红 | 伤害/暴击/攻速 | 武器大师：主副手武器词缀共享 |
| 构筑（蓝） | 蓝 | 附魔台/技能/背包 | 词缀共鸣：同一条词缀出现在两件装备上时，效果×1.5 |
| 掉落（黄） | 黄 | 品质/金币/碎片 | 传奇猎手：LEGENDARY掉落率×2 |

> 当前状态：设计完成，未实现（N/A）。

---

## 七、待办 / 尚未实现

### 装备改造 v1.2（已完成）

| 功能 | 说明 |
|------|------|
| 5→3品质简化 | 删 COMMON/SET，RarityTable 重构，EquipmentDrop 适配 |
| 槽位基础属性移除 | 删装备基础数值管线 |
| SET 标签化 | SET 从品质枚举中移除，改为 EquipmentBase.set_id 字段 |
| 词缀槽位过滤实现 | `_add_affixes` 加上 `allowed_slots` 过滤逻辑 |
| 锻造删除 | forging.gd、ForgeMaterial 相关代码清空 |
| Lobby 改造 | 资源简化为 gold + talent_shards，Collection 删除全局加成 |
| Collection 瘦身 | 删除全局加成逻辑，保留记录功能 |
| 材料简化 | iron/magic_essence/legendary_core → 仅 gold + talent_shards |
| 附魔台实现 | 房间场景 EnchantmentTable（Area2D 交互），重铸消耗 300 金 |
| Gold 系统 | GoldPickup + EnemyConfig.drop_gold + run_gold 归入 lobby_data |

### 待实现新功能（P0）

| 功能 | 说明 |
|------|------|
| 天赋树实现 | TalentNode Resource + TalentManager + Lobby 面板 |
| 房间环境碰撞体 | 所有房间场景墙壁 StaticBody2D |
| 各武器碰撞体精细调整 | CollisionShape2D 位置/大小 |
| 音频系统 | AudioManager 填实 |

### 待实现新功能（P1）

| 功能 | 说明 |
|------|------|
| 精英敌人 | 独有行为脚本 + 精英掉落 |
| Boss 血条 UI | Boss 战专用血条组件 |
| 更多技能种类 | `resources/skills/` 下填充更多技能脚本+.tres |
| 章节模式 | 关卡解锁 + 难度选择 |
| 循环模式 | 无限场景 + 难度递增 + 最高纪录 |
| 装备图鉴界面 | 收集展示（数据已存，缺界面） |

### 已取消

| 功能 | 说明 |
|------|------|
| PVP 模式 | ❌ 不再做 |
| 基地系统 | ❌ 不再做 |
| 角色自定义 | ❌ 不再做 |
| 完整职业系统 | ❌ 不再做（仅保留现有 warrior/mage/knight 三职业 PlayerConfig） |
| 镶嵌/宝石系统 | ❌ 不再做（替换方案：房间附魔台） |

### 架构已修复

| 问题 | 文件 | 状态 |
|------|------|------|
| weapon_data.gd 中 `visual_scene` 冗余 | weapon_data.gd | ✅ |
| `tool_path` 无效引用 | set_database.gd:27 | ✅ |
| 子弹对象池未接通 | projectile.gd → GameManager | ✅ |
| Boss 配置数据流混乱 | boss_enemy.gd | ✅ （已统一走数据驱动） |
| RoomManager 硬编码 fallback | room_manager.gd | ✅ （fallback 增至 5 个房间） |

---

## 八、关键编码约定

### 应遵守

1. **全部 GDScript**，不引入 C#
2. **设计分辨率 640×360**，stretch/mode=canvas_items，窗口 1280×720
3. **像素图用 texture_filter = NEAREST**
4. **class_name 类通过 preload 在文件顶部显式引用**
5. **不写注释**，除非有特别复杂的逻辑需要说明
6. **组件化架构**：StateComponent / MovementComponent / WeaponComponent
7. **数据驱动优先**：使用 Resource (.tres) 配置，而非硬编码
8. **碰撞层**：1=Player, 2=Enemy, 3=Environment, 4=Pickup, 5=Hazard, 6=Hurtbox, 7=Hitbox
9. **状态机使用 enum + match 单类实现**
10. **monitoring/monitorable 修改必须用 set_deferred**
11. **最少改动原则**：优先修改现有文件
12. **防御性编程**：get_node_or_null() / is_instance_valid()
13. **信号解耦**：使用 EventManager 或节点信号，避免直接依赖
14. **不引入外部依赖**：无插件/第三方库

### 不踩坑

1. **I 键**开背包（非 Tab，Godot Tab 被焦点导航消费）
2. **U 键**返回大厅（非重新开始）
3. **`theme_override_*` 不能在 .tscn 中使用** → 在脚本中用 add_theme_color_override
4. **`state.get(key)` 单参数**（Node.get() 不支持 default value）
5. **.tscn 用于 UI 布局，脚本只负责逻辑**
6. **WeaponComponent.scale.x 翻转**（父级），**WeaponVisualBase 不翻转**（子级）
7. **swing tween 始终 -half_arc → +half_arc**（翻转由 scale.x 继承自动完成）
8. **碰撞体在武器 .tscn 中可视化编辑**（非代码生成）

---

## 九、数据流全景（装备→战斗）

```
掉落生成（EquipmentDrop）
  → 拾取（EquipmentPickup） → 背包（EquipmentInventory）
  → 装备（EquipmentManager.equip()）
    ├── 所有槽：StatModifier → StateComponent
    └── WEAPON槽：weapon_data duplicate → WeaponNode.equip()
                    → _apply_archetype_modifiers()（隐式修正）
                    → _spawn_weapon_visual()（加载 .tscn 视觉场景）
                    → attack() → _attack_melee() / _attack_ranged()
                      → hit_landed 信号 → WeaponComponent（粒子/震屏）
                                        → EquipmentManager（词缀触发判定）

附魔台交互（房间内）
  → 重铸（消耗金币，重随单条词缀数值）
  → 转移（消耗金币+装备，移动词缀到目标装备）
```

---

## 十、参考文档

| 文件 | 内容 |
|------|------|
| docs/项目实施规划.md | 整体阶段规划、文件清单、风险评估 |
| docs/装备系统设计.md | 装备系统 v7.0 完整设计（词缀/品质/套装/锻造/Room适配） |
| docs/武器-装备统一方案.md | WeaponData 设计、Archtype 隐式修正、WeaponNode 统一 |
| docs/敌人系统设计.md | EnemyConfig/BossConfig 骨架、3层敌人架构 |
| docs/核心战斗功能完善规划.md | 体力/热量/弹药/技能详细设计（Unity原版参考） |
| docs/游戏策划文档.md | 初始策划（战斗/角色/关卡/经济/UI/音频） |
| docs/架构待办.md | 7个架构问题的分析和修复方向 |
