class_name EquipmentPickup
extends Area2D

var item: EquipmentBase
var _collected: bool = false


func setup(equip: EquipmentBase):
	item = equip
	collision_layer = 0
	collision_mask = CollisionSystem.bit(CollisionSystem.LAYER_PLAYER)
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)

	var color = RarityTable.get_rarity_color(item.rarity)
	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 10
	shape.shape = circle
	add_child(shape)

	var sprite = ColorRect.new()
	sprite.size = Vector2(18, 18)
	sprite.color = color
	sprite.position = Vector2(-9, -9)
	add_child(sprite)

	var border = ColorRect.new()
	border.size = Vector2(22, 22)
	border.color = Color(1, 1, 1, 0.3)
	border.position = Vector2(-11, -11)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(border)

	var label = Label.new()
	label.text = "?"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-9, -7)
	label.size = Vector2(18, 18)
	label.add_theme_font_size_override("font_size", 12)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)

	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


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
	var inv = target.get_node_or_null("EquipmentInventory") as EquipmentInventory
	if not inv:
		return
	_collected = true
	if inv.add_item(item):
		print("[拾取] %s (%s)" % [item.equipment_name, RarityTable.get_rarity_name(item.rarity)])
		EventManager.item_picked_up.emit({"item": item})
		Collection.register_item(item)
	else:
		_collected = false
		print("[拾取] 背包已满")
		return
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.1)
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.15)
	tween.tween_callback(queue_free)
