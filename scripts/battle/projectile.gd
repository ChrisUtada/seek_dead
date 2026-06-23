extends Area2D

signal hit(hit_pos: Vector2, hit_dir: Vector2, damage_type: int, body: Node2D)

var direction: Vector2
var speed: float = 600.0
var damage: float = 20.0
var damage_type: int = 0
var shooter: Node = null
var status_effect_type: int = -1
var status_effect_damage: float = 0.0
var status_effect_duration: float = 3.0
var _age: float = 0.0
var _pool: ObjectPool = null
var _signal_connected: bool = false
var _returning: bool = false

func _enter_tree():
	_returning = false
	if not _signal_connected:
		body_entered.connect(_on_body_entered)
		_signal_connected = true

func set_pool(pool: ObjectPool):
	_pool = pool

func _physics_process(delta):
	position += direction * speed * delta
	_age += delta
	if _age > 2.0:
		_return_to_pool()

func _on_body_entered(body):
	if body == shooter:
		return
	if body.has_method("take_damage"):
		body.take_damage(damage, damage_type)
	if status_effect_type >= 0 and body.has_method("apply_status"):
		body.apply_status(status_effect_type, status_effect_damage, status_effect_duration)
	hit.emit(global_position, direction, damage_type, body)
	_return_to_pool()

func _return_to_pool():
	if _returning:
		return
	_returning = true
	if _pool:
		body_entered.disconnect(_on_body_entered)
		_signal_connected = false
		call_deferred("_deferred_return_to_pool")
	else:
		queue_free()

func _deferred_return_to_pool():
	_pool.release(self)