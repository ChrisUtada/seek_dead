class_name WeaponBase
extends Resource

@export var weapon_name: String = ""
@export var damage: float = 10.0
@export var damage_type: int = 0
@export var attack_speed: float = 1.0
@export var attack_range: float = 40.0

@export var status_effect_type: int = -1
@export var status_effect_damage: float = 0.0
@export var status_effect_duration: float = 3.0

@export var heat_per_attack: float = -1.0

@export var visual_scene: PackedScene
