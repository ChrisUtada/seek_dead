extends Area2D

var damage: float = 10.0
var damage_type: int = 0
var interval: float = 0.5
var lifetime: float = 5.0
var _age: float = 0.0
var _timer: float = 0.0


func _ready():
	collision_layer = 0
	collision_mask = 0


func _process(delta):
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	_timer += delta
	if _timer >= interval:
		_timer = 0.0
		_pulse()


func _pulse():
	var space = get_world_2d().direct_space_state
	if not space:
		return
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	var cs: CollisionShape2D = $CollisionShape2D
	if cs and cs.shape:
		shape.radius = (cs.shape as CircleShape2D).radius
	else:
		shape.radius = 100.0
	query.shape = shape
	query.transform = Transform2D(0, global_position)
	query.collision_mask = CollisionSystem.bit(CollisionSystem.LAYER_ENEMY)
	query.collide_with_areas = true
	var results = space.intersect_shape(query)
	for r in results:
		var obj = r.collider
		if not obj:
			continue
		var owner = obj.owner if obj.owner else obj
		if owner.has_method("take_damage"):
			owner.take_damage(damage, damage_type)
