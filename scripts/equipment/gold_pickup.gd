class_name GoldPickup
extends Area2D

var gold_value: int = 15
var _collected: bool = false


func setup(value: int = 15):
	gold_value = value
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
	orb.color = Color(1, 0.85, 0.3, 0.9)
	orb.position = Vector2(-7, -7)
	add_child(orb)

	var label = Label.new()
	label.text = "$"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-7, -8)
	label.size = Vector2(14, 14)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


func _on_body_entered(body: Node2D):
	_collect()


func _on_area_entered(area: Area2D):
	_collect()


func _collect():
	if _collected:
		return
	if not has_node("/root/GameManager"):
		return
	_collected = true
	GameManager.run_gold += gold_value
	var lobby_data = SaveSystem.load_lobby_data()
	lobby_data["gold"] = lobby_data.get("gold", 0) + gold_value
	SaveSystem.save_lobby_data(lobby_data)
	print("[金币拾取] +%d (当前局内:%d)" % [gold_value, GameManager.run_gold])
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.1)
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.15)
	tween.tween_callback(queue_free)