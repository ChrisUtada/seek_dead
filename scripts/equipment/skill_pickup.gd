class_name SkillPickup
extends Area2D

var skill: SkillBase
var _collected: bool = false


func setup(s: SkillBase):
	skill = s
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
	orb.size = Vector2(16, 16)
	orb.color = Color(0.2, 0.8, 1.0, 0.9)
	orb.position = Vector2(-8, -8)
	add_child(orb)

	var border = ColorRect.new()
	border.size = Vector2(20, 20)
	border.color = Color(1, 1, 1, 0.3)
	border.position = Vector2(-10, -10)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(border)

	var label = Label.new()
	label.text = "S"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-8, -7)
	label.size = Vector2(16, 16)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


func _on_body_entered(body: Node2D):
	_try_pickup(body)


func _on_area_entered(area: Area2D):
	var owner = area.owner if area.owner else area
	_try_pickup(owner)


func _try_pickup(target: Node2D):
	if _collected:
		return
	if not target.is_in_group("players"):
		return
	var sm = target.get_node_or_null("SkillManager") as SkillManager
	if not sm:
		return
	_collected = true
	var dup = skill.duplicate(true)
	if sm.add_or_upgrade(dup):
		print("[技能拾取] %s (Lv.%d)" % [dup.skill_name, dup.level])
		EventManager.skill_picked_up.emit({"skill": dup})
	_collected = false
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.1)
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.15)
	tween.tween_callback(queue_free)
