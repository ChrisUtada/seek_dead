class_name SlowArea
extends Area2D

var speed_mult: float = 0.5
var lifetime: float = 3.0
var _age: float = 0.0
var _affected: Dictionary = {}


func _ready():
	body_entered.connect(_on_body_enter)
	area_entered.connect(_on_area_enter)


func _process(delta):
	_age += delta
	if _age >= lifetime:
		_cleanup_all()
		queue_free()
		return


func _on_body_enter(body: Node2D):
	_try_apply_slow(body)


func _on_area_enter(area: Area2D):
	var target = area.owner if area.owner else area
	_try_apply_slow(target)


func _try_apply_slow(target: Node2D):
	if target in _affected:
		return
	var mover = target.get_node_or_null("MovementComponent") as MovementComponent
	if not mover:
		return
	_affected[target] = { "mover": mover, "original_speed": mover.speed }
	mover.speed *= speed_mult


func _exit_tree():
	for target in _affected.keys():
		var info = _affected[target] as Dictionary
		var mover = info.get("mover") as MovementComponent
		if mover:
			mover.speed = info.get("original_speed", mover.speed)
	_affected.clear()


func _cleanup_all():
	for target in _affected.keys():
		var info = _affected[target] as Dictionary
		var mover = info.get("mover") as MovementComponent
		if mover:
			mover.speed = info.get("original_speed", mover.speed)
	_affected.clear()
