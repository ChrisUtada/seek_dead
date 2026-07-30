class_name DamageNumberSpawner
extends Node
## 屏幕空间飘字：伤害数字 + 装备触发 / 套装激活的浮动文字。
## 由 HUD 实例化并 add_child。connect_player_equipment() 注入玩家装备信号后自动弹出飘字。

func spawn_damage_number(world_pos: Vector2, amount: float, is_critical: bool = false):
	var label = Label.new()
	var viewport = get_viewport()
	if not viewport:
		return
	var cam = viewport.get_camera_2d()
	if cam:
		label.position = cam.get_canvas_transform() * world_pos
	label.position -= Vector2(8, 0)
	label.add_theme_color_override("font_color", Color(1, 0.8, 0.2) if is_critical else Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_font_size_override("font_size", 16)
	label.text = "%.0f" % amount
	if is_critical:
		label.text = "暴击! " + label.text
	add_child(label)
	var tween = create_tween()
	var end_pos = label.position + Vector2(0, -30)
	if is_critical:
		tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
		end_pos = label.position + Vector2(0, -36)
	tween.tween_property(label, "position", end_pos, 0.8)
	tween.parallel().tween_property(label, "modulate", Color(1, 1, 1, 0), 0.8)
	tween.tween_callback(label.queue_free)


func _on_trigger_activated(event: int, effect: TriggerEffect, player: Node2D):
	if not is_instance_valid(player):
		return
	var text = _trigger_floating_text(effect.effect_action)
	if text.length() == 0:
		return
	spawn_floating_text(player.global_position, text, _trigger_color(effect.effect_action))


func _on_set_bonus_activated(set_id: String, tier: int, player: Node2D):
	if not is_instance_valid(player):
		return
	var set_def = SetDatabase.get_set(set_id)
	if not set_def:
		return
	var text = "套装 %s %d件 已激活!" % [set_def.set_name, tier]
	spawn_floating_text(player.global_position, text, Color(0.3, 1, 0.3))


func _trigger_floating_text(action: int) -> String:
	match action:
		EquipmentEnums.EffectAction.EXPLODE: return "爆炸!"
		EquipmentEnums.EffectAction.SPAWN_PROJECTILE: return "弹射!"
		EquipmentEnums.EffectAction.SPAWN_POOL: return "毒池!"
		EquipmentEnums.EffectAction.CHAIN_LIGHTNING: return "连锁闪电!"
		EquipmentEnums.EffectAction.HEAL: return "回血!"
		EquipmentEnums.EffectAction.SHIELD: return "护盾!"
		EquipmentEnums.EffectAction.FIRE_AURA: return "火焰光环!"
		EquipmentEnums.EffectAction.KNOCKBACK: return "击退!"
		EquipmentEnums.EffectAction.SLOW_ENEMIES: return "减速!"
		_: return ""


func _trigger_color(action: int) -> Color:
	match action:
		EquipmentEnums.EffectAction.EXPLODE: return Color(1, 0.6, 0.1)
		EquipmentEnums.EffectAction.SPAWN_PROJECTILE: return Color(0.6, 0.8, 1)
		EquipmentEnums.EffectAction.SPAWN_POOL: return Color(0.3, 1, 0.3)
		EquipmentEnums.EffectAction.CHAIN_LIGHTNING: return Color(0.5, 0.5, 1)
		EquipmentEnums.EffectAction.HEAL: return Color(0.3, 1, 0.3)
		EquipmentEnums.EffectAction.SHIELD: return Color(0.3, 0.6, 1)
		EquipmentEnums.EffectAction.FIRE_AURA: return Color(1, 0.4, 0.1)
		EquipmentEnums.EffectAction.KNOCKBACK: return Color(1, 1, 0.3)
		EquipmentEnums.EffectAction.SLOW_ENEMIES: return Color(0.5, 0.8, 1)
		_: return Color.WHITE


func spawn_floating_text(world_pos: Vector2, text: String, color: Color = Color.WHITE):
	var label = Label.new()
	var viewport = get_viewport()
	if not viewport:
		return
	var cam = viewport.get_camera_2d()
	if cam:
		label.position = cam.get_canvas_transform() * world_pos
	label.position -= Vector2(30, 0)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_font_size_override("font_size", 14)
	label.text = text
	add_child(label)
	var tween = create_tween()
	tween.tween_property(label, "position", label.position + Vector2(0, -40), 1.0)
	tween.parallel().tween_property(label, "modulate", Color(color.r, color.g, color.b, 0), 1.0)
	tween.tween_callback(label.queue_free)


## 连接玩家装备的触发信号（原在 HUD._connect_equipment_signals 中按玩家 bind）。
func connect_player_equipment(player: Node2D):
	var mgr = player.get_node_or_null("EquipmentManager") as EquipmentManager
	if mgr:
		mgr.trigger_activated.connect(_on_trigger_activated.bind(player))
		var set_mgr = mgr.get_node_or_null("SetBonusManager") as SetBonusManager
		if set_mgr:
			set_mgr.set_bonus_activated.connect(_on_set_bonus_activated.bind(player))
