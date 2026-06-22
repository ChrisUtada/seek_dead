class_name WeaponBase
extends Resource

enum WeaponType { MELEE, RANGED }

@export var weapon_name: String = "Weapon"
@export var weapon_type: WeaponType = WeaponType.MELEE
@export var damage: float = 30.0
@export var damage_type: DamageSystem.DamageType = DamageSystem.DamageType.SLASH
@export var attack_speed: float = 1.0
@export var range: float = 40.0
