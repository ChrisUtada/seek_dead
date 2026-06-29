extends Area2D

var damage: float = 15.0
var damage_type: int = 0
var lifetime: float = 3.0
var _age: float = 0.0
var _hit: Array[Node2D] = []


func _ready():
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func _process(delta):
	_age += delta
	if _age >= lifetime:
		queue_free()
	modulate.a = 1.0 - (_age / lifetime) * 0.5


func _on_body_entered(body: Node2D):
	_try_damage(body)


func _on_area_entered(area: Area2D):
	var owner = area.owner if area.owner else area
	_try_damage(owner)


func _try_damage(target: Node2D):
	if target in _hit:
		return
	if not target.has_method("take_damage"):
		return
	_hit.append(target)
	target.take_damage(damage, damage_type)
