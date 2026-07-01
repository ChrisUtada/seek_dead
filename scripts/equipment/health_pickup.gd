class_name HealthPickup
extends Area2D

var heal_amount: int = 15
var _collected: bool = false


func setup(amount: int = 15):
	heal_amount = amount
	collision_layer = 0
	collision_mask = CollisionSystem.bit(CollisionSystem.LAYER_PLAYER)
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	call_deferred("_build_visual")


func _build_visual():
	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 10
	shape.shape = circle
	add_child(shape)

	var orb = ColorRect.new()
	orb.size = Vector2(14, 14)
	orb.color = Color(1, 0.2, 0.2, 0.9)
	orb.position = Vector2(-7, -7)
	add_child(orb)

	var border = ColorRect.new()
	border.size = Vector2(18, 18)
	border.color = Color(1, 1, 1, 0.3)
	border.position = Vector2(-9, -9)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(border)

	var label = Label.new()
	label.text = "+"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-7, -8)
	label.size = Vector2(14, 14)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


func _on_body_entered(body: Node2D):
	_try_heal(body)


func _on_area_entered(area: Area2D):
	var owner = area.owner if area.owner else area
	_try_heal(owner)


func _try_heal(target: Node2D):
	if _collected:
		return
	if not target.is_in_group("players"):
		return
	var state = target.get_node_or_null("StateComponent") as StateComponent
	if not state:
		return
	_collected = true
	var old = state.hp
	state.hp = min(state.hp + heal_amount, state.max_hp)
	var healed = state.hp - old
	print("[血球拾取] +%d HP" % healed)
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.1)
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.15)
	tween.tween_callback(queue_free)
