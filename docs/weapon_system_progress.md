## 武器装备系统 — 当前状态总结

### 已完成

1. **场景驱动武器视觉系统（方案A）**：每把武器独立 .tscn 场景（`scenes/weapons/*.tscn`），`WeaponData.weapon_scene` 引用 PackedScene，`WeaponNode` 动态实例化
2. **主副手双持系统（方案B）**：`EquipmentSlot.WEAPON_MAIN` + `WEAPON_OFFHAND`，数字键 1/2 切换 `active_hand`
3. **副手限制轻型武器**：`WeaponData.can_dual_wield` 控制哪些武器可装副手（匕首/毒匕首/手枪/冰霜枪 = true，其余 = false）
4. **远程子弹系统修复**：3个远程模板补上 `bullet_data`，projectile 碰撞层改为 HITBOX/HURTBOX，`area_entered` 调用 `apply_to()` 造成伤害
5. **武器切换状态机重置**：`equip()` / `unequip()` 重置 `_ws` / `is_attacking` / 计时器，避免卡攻击
6. **武器视觉定位**：`WeaponData.visual_offset` + `WeaponVisualBase.setup()` 应用偏移

### 待优化

- **不同武器的位置和大小差异**：铁剑、战斧、手枪等武器大小不同，需要不同的 `visual_offset` 和可能的 scale 调整。目前 `visual_offset` 默认 `Vector2.ZERO`，需要在各 `.tres` 模板中逐一把合适的偏移值填上
- **可考虑**：在 `WeaponData` 中加 `visual_scale` 属性，让不同武器在场景中有合适的缩放比例

### 关键文件

| 文件 | 职责 |
|------|------|
| `scripts/equipment/weapon_data.gd` | `can_dual_wield`, `visual_offset`, `weapon_scene` 等属性定义 |
| `scripts/battle/weapon_node.gd` | 装备/卸下/攻击逻辑 |
| `scripts/battle/weapon_visual_base.gd` | 视觉基类，`setup()` 应用 `visual_offset` |
| `scripts/components/weapon_component.gd` | 主副手管理，`switch_active_hand()` |
| `scripts/equipment/equipment_manager.gd` | 装备/卸下，含副手校验 |
| `scripts/equipment/equipment_drop.gd` | 掉落生成，副手过滤可双持武器 |
| `scenes/weapons/*.tscn` | 8个武器场景文件 |
| `resources/weapon_templates/*.tres` | 8个武器数据模板 |

### 武器可双持情况

| 武器 | 类型 | can_dual_wield |
|------|------|----------------|
| 铁剑 | 近战 MEDIUM | false |
| 火焰剑 | 近战 MEDIUM | false |
| 战斧 | 近战 HEAVY | false |
| 匕首 | 近战 LIGHT | true |
| 毒匕首 | 近战 LIGHT | true |
| 手枪 | 远程 MEDIUM | true |
| 冰霜枪 | 远程 LIGHT | true |
| 火焰法杖 | 远程 MAGIC | false |

### 初始装备配置

- 主手：铁剑（近战）
- 副手：手枪（远程）
