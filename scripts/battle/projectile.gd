extends Hitbox

signal hit(hit_pos: Vector2, hit_dir: Vector2, damage_type: int, body: Node2D)

const _BulletData = preload("res://scripts/battle/bullet_data.gd")

@export var data: BulletData

var direction: Vector2
var _pool: ObjectPool = null
var _signal_connected: bool = false
var _returning: bool = false

func _ready():
	super()
	lifespan = 0.0
	collision_mask = CollisionSystem.bit(CollisionSystem.LAYER_ENVIRONMENT)
	hit_landed.connect(_on_hurtbox_hit)

func _enter_tree():
	_returning = false
	if not _signal_connected:
		body_entered.connect(_on_body_entered)
		_signal_connected = true

func set_pool(pool: ObjectPool):
	_pool = pool

func _physics_process(delta):
	if not data:
		_return_to_pool()
		return
	position += direction * data.speed * delta
	_age += delta
	if _age > data.lifetime:
		_return_to_pool()

func _on_body_entered(body):
	if body == shooter:
		return
	_handle_hit(body)

func _on_hurtbox_hit(target: Node2D):
	_handle_hit(target)

func _handle_hit(hit_target: Node2D):
	hit.emit(global_position, direction, damage_type, hit_target)
	if _pool and data and data.pierce_count > 0:
		data.pierce_count -= 1
		if data.pierce_count <= 0:
			_return_to_pool()
	else:
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
