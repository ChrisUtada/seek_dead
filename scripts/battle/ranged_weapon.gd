class_name RangedWeapon
extends WeaponBase

const _BulletData = preload("res://scripts/battle/bullet_data.gd")

@export var bullet_scene: PackedScene
@export var bullet_speed: float = 600.0
@export var max_ammo: int = 0
@export var ammo_per_shot: int = 1
@export var bullet_data: BulletData
