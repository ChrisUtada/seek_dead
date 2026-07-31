class_name WeaponData
extends Resource

enum Archetype { LIGHT, MEDIUM, HEAVY, MAGIC }
enum WeaponType { MELEE, RANGED }

@export var weapon_name: String = ""
@export var archetype: Archetype = Archetype.MEDIUM
@export var weapon_type: WeaponType = WeaponType.MELEE
@export var can_dual_wield: bool = false  # 是否可装备到副手

# -- 通用战斗属性 --
@export var damage: float = 10.0
@export var damage_type: int = 0
@export var attack_speed: float = 1.0
@export var attack_range: float = 40.0

# -- 武器场景 --
@export var weapon_scene: PackedScene
@export var grip_point: Vector2 = Vector2.ZERO   # 握把锚点（武器精灵上"手握住的位置"，相对于精灵原点）
@export var visual_offset: Vector2 = Vector2.ZERO  # 武器视觉偏移（微调武器在角色上的位置）
@export var visual_scale: Vector2 = Vector2.ONE   # 武器视觉缩放

# -- 状态效果 --
@export var status_effect_type: int = -1
@export var status_effect_damage: float = 0.0
@export var status_effect_duration: float = 3.0

# -- 过热 --
@export var heat_per_attack: float = -1.0

# -- 远程专属 --
@export var bullet_scene: PackedScene
@export var bullet_speed: float = 600.0
@export var max_ammo: int = 0
@export var ammo_per_shot: int = 1
@export var bullet_data: BulletData

# -- 近战专属 --
@export var cleave_angle: float = 90.0
@export var knockback_force: float = 200.0

# -- 碰撞体配置 --
# 碰撞体形状在武器 .tscn 的 HitboxArea 节点中配置

# -- 老虎机战斗符号池（M1 接入） --
# 该武器作为"转轮"时，其符号及权重。key = ReelSymbol.Id 整数，value = 权重(float)。
# 例：{ 0: 6.0, 5: 3.0 } 表示斩(SLASH)权重 6、格挡(BLOCK)权重 3。
@export var reel_symbols: Dictionary = {}
# 该武器的专属特殊符号（ReelSymbol.Id）。仅作签名记录，M3 接入武器 special 效果时再使用。-1 表示无。
@export var special_symbol: int = -1
# 该武器特殊符号的属性元素（fire/ice/poison/light/dark/none）。
# 用于单向属性克制：玩家特殊符号元素 → 敌人元素。普通伤害符号恒为 none（中性）。
@export var reel_element: String = "none"


## 返回 archetype 对应的隐式修正列表。
## 复用 StatModifier 对象，与装备词缀管线一致。
static func get_implicit_modifiers(archetype: Archetype) -> Array[StatModifier]:
	var result: Array[StatModifier] = []
	match archetype:
		Archetype.LIGHT:
			result.append(_mod(EquipmentEnums.StatTarget.ATTACK_SPEED, EquipmentEnums.ModifierType.MUL, 0.10))
			result.append(_mod(EquipmentEnums.StatTarget.ATTACK_DAMAGE, EquipmentEnums.ModifierType.MUL, -0.20))
		Archetype.HEAVY:
			result.append(_mod(EquipmentEnums.StatTarget.ATTACK_DAMAGE, EquipmentEnums.ModifierType.MUL, 0.20))
			result.append(_mod(EquipmentEnums.StatTarget.ATTACK_SPEED, EquipmentEnums.ModifierType.MUL, -0.10))
		Archetype.MAGIC:
			result.append(_mod(EquipmentEnums.StatTarget.ATTACK_DAMAGE, EquipmentEnums.ModifierType.MUL, 0.15))
			result.append(_mod(EquipmentEnums.StatTarget.ATTACK_SPEED, EquipmentEnums.ModifierType.MUL, -0.10))
		# MEDIUM: 无隐式修正
	return result


static func _mod(target: int, type: int, value: float) -> StatModifier:
	var m = StatModifier.new()
	m.target_stat = target
	m.modifier_type = type
	m.value = value
	return m
