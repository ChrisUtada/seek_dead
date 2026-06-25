class_name Damageable
extends CharacterBody2D

var is_invincible: bool = false

func take_damage(amount: float, damage_type: int) -> Dictionary:
	push_error("%s 未实现 take_damage()" % name)
	return {}

func knockback(_velocity: Vector2):
	push_error("%s 未实现 knockback()" % name)

func apply_status(_effect_type: int, _damage: float, _duration: float):
	push_error("%s 未实现 apply_status()" % name)
