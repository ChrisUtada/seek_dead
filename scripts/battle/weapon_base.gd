class_name WeaponBase
extends Resource

enum WeaponType { MELEE, RANGED }

@export var weapon_name: String = "Weapon"
@export var weapon_type: WeaponType = WeaponType.MELEE
@export var damage: float = 30.0
@export var damage_type: DamageSystem.DamageType = DamageSystem.DamageType.SLASH
@export var attack_speed: float = 1.0
@export var range: float = 40.0

@export var status_effect_type: int = -1
@export var status_effect_damage: float = 0.0
@export var status_effect_duration: float = 3.0

@export var heat_per_attack: float = -1.0
@export var max_ammo: int = 0
@export var ammo_per_shot: int = 1
