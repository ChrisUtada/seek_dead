class_name WeaponData
extends LoadoutItem

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

# -- 近战专属 --
@export var cleave_angle: float = 90.0
@export var knockback_force: float = 200.0

# -- 碰撞体配置 --
# 碰撞体形状在武器 .tscn 的 HitboxArea 节点中配置

# -- 老虎机战斗符号池（资源化，零注册表） --
# 该武器作为"转轮"时持有的符号与各自权重。每个元素直接引用 SymbolData 资源，
# 无 id 查表、无全局 CATALOG。加符=新建 SymbolData .tres，不改代码。
@export var reel: Array[SymbolWeight] = []
# 该武器特殊符号（kind=="special"）的属性元素（fire/ice/poison/light/dark/none）。
# 用于单向属性克制：玩家特殊符号元素 → 敌人元素。普通伤害符号恒为 none（中性）。
@export var reel_element: String = "none"
# 武器元素（Phase G v2.0 武器元素化）。普通伤害/治疗/护盾/状态符号若自身 element 为
# "none"，则继承此值；special 符号优先用 reel_element（见 duel_controller._eff_element）。
# 中性开局武器保持 "none"，其符号恒为中性。
@export var element: String = "none"
