class_name Hitbox
extends Area2D

signal hit_landed(target: Node2D)

var damage: float = 0.0
var damage_type: int = 0
var shooter: Node2D = null
var knockback_force: float = 120.0
var status_effect_type: int = -1
var status_effect_damage: float = 0.0
var status_effect_duration: float = 3.0

var lifespan: float = 0.3
var _age: float = 0.0
var _already_hit: Array[Node2D] = []

func reset():
	_already_hit.clear()

func _ready():
	collision_layer = CollisionSystem.bit(CollisionSystem.LAYER_HITBOX)

func _process(delta):
	if lifespan <= 0:
		return
	_age += delta
	if _age >= lifespan:
		queue_free()

func apply_to(hurtbox: Hurtbox):
	if not hurtbox:
		return
	var target = hurtbox.owner as Damageable
	if not target or target == shooter or target in _already_hit:
		return
	_already_hit.append(target)
	hit_landed.emit(target)
	target.take_damage(damage, damage_type)
	if status_effect_type >= 0:
		target.apply_status(status_effect_type, status_effect_damage, status_effect_duration)
	var dir = Vector2.RIGHT if shooter == null else (target.global_position - shooter.global_position).normalized()
	target.knockback(dir * knockback_force)
