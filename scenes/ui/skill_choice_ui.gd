class_name SkillChoiceUI
extends Node
## 技能升级 / 选择弹窗（暂停游戏 + 点击卡片选择）。
## 由 HUD 实例化并 add_child。HUD 保留 show_skill_upgrade / show_skill_choice 作为转发入口
## （room_manager 经 find_child("HUD") 调用）。自身处理鼠标点击选择（_input），无需 HUD 介入。

var _skill_manager: SkillManager = null
var _choice_panel: Control = null
var _choice_card_rects: Array = []


func set_skill_manager(sm: SkillManager):
	_skill_manager = sm


func show_skill_upgrade(sm: SkillManager):
	if _choice_panel:
		_choice_panel.queue_free()
		_choice_panel = null
	get_tree().paused = true
	_choice_panel = Control.new()
	_choice_panel.name = "SkillUpgradePanel"
	var panel_w = 260
	var panel_h = 40 + sm.skills.size() * 70
	_choice_panel.size = Vector2(panel_w, panel_h)
	var viewport_size = get_viewport().get_visible_rect().size
	_choice_panel.position = (viewport_size - _choice_panel.size) / 2
	add_child(_choice_panel)

	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.1, 0.92)
	bg.size = Vector2(panel_w, panel_h)
	_choice_panel.add_child(bg)

	var title = Label.new()
	title.text = "选择升级技能"
	title.position = Vector2(panel_w / 2 - 60, 8)
	title.size = Vector2(120, 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	title.add_theme_font_size_override("font_size", 14)
	_choice_panel.add_child(title)

	var card_size = Vector2(panel_w - 24, 56)
	var start_y = 34
	_choice_card_rects.clear()
	for i in range(sm.skills.size()):
		var sk = sm.skills[i]
		var card = ColorRect.new()
		card.name = "UpgradeCard%d" % i
		card.position = Vector2(12, start_y + i * (int(card_size.y) + 8))
		card.size = card_size
		card.color = Color(0.2, 0.3, 0.25, 0.95) if sk.level < sk.max_level else Color(0.25, 0.2, 0.2, 0.95)
		_choice_panel.add_child(card)

		_choice_card_rects.append({rect = Rect2(card.position, card_size), skill = sk})

		var name_lbl = Label.new()
		name_lbl.text = sk.skill_name + "  Lv." + str(sk.level)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.position = Vector2(0, 4)
		name_lbl.size = Vector2(card_size.x, 24)
		name_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		name_lbl.add_theme_font_size_override("font_size", 13)
		card.add_child(name_lbl)

		var status_lbl = Label.new()
		if sk.level >= sk.max_level:
			status_lbl.text = "已达最高等级"
			status_lbl.add_theme_color_override("font_color", Color(0.8, 0.5, 0.5))
		else:
			status_lbl.text = "点击升级至 Lv." + str(sk.level + 1)
			status_lbl.add_theme_color_override("font_color", Color(0.5, 1, 0.5))
		status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_lbl.position = Vector2(0, 30)
		status_lbl.size = Vector2(card_size.x, 20)
		status_lbl.add_theme_font_size_override("font_size", 10)
		card.add_child(status_lbl)


func show_skill_choice(choices: Array[SkillBase]):
	if _choice_panel:
		_choice_panel.queue_free()
		_choice_panel = null
	get_tree().paused = true
	_choice_panel = Control.new()
	_choice_panel.name = "SkillChoicePanel"
	_choice_panel.size = Vector2(400, 160)
	var viewport_size = get_viewport().get_visible_rect().size
	_choice_panel.position = (viewport_size - _choice_panel.size) / 2
	add_child(_choice_panel)

	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.1, 0.92)
	bg.size = Vector2(400, 160)
	_choice_panel.add_child(bg)

	var title = Label.new()
	title.text = "选择技能"
	title.position = Vector2(140, 8)
	title.size = Vector2(120, 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	title.add_theme_font_size_override("font_size", 14)
	_choice_panel.add_child(title)

	var card_size = Vector2(110, 120)
	var gap = 12
	var total_w = choices.size() * int(card_size.x) + (choices.size() - 1) * gap
	var start_x = (400 - total_w) / 2
	_choice_card_rects.clear()
	for i in range(choices.size()):
		var sk = choices[i]
		var card = ColorRect.new()
		card.name = "Card%d" % i
		card.position = Vector2(start_x + i * (int(card_size.x) + gap), 32)
		card.size = card_size
		card.color = Color(0.2, 0.2, 0.3, 0.95)
		_choice_panel.add_child(card)

		_choice_card_rects.append({rect = Rect2(card.position, card_size), skill = sk})

		var name_lbl = Label.new()
		name_lbl.text = sk.skill_name
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.position = Vector2(0, 4)
		name_lbl.size = Vector2(card_size.x, 20)
		name_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		name_lbl.add_theme_font_size_override("font_size", 12)
		card.add_child(name_lbl)

		var desc_lbl = Label.new()
		desc_lbl.text = sk.skill_description
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		desc_lbl.position = Vector2(4, 24)
		desc_lbl.size = Vector2(card_size.x - 8, 60)
		desc_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		desc_lbl.add_theme_font_size_override("font_size", 9)
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(desc_lbl)

		var cost_lbl = Label.new()
		cost_lbl.text = "能量 %d  CD %.1fs" % [sk.energy_cost, sk.cooldown]
		cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		cost_lbl.position = Vector2(0, card_size.y - 24)
		cost_lbl.size = Vector2(card_size.x, 20)
		cost_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 1))
		cost_lbl.add_theme_font_size_override("font_size", 8)
		card.add_child(cost_lbl)


func _input(event):
	if _choice_panel and not _choice_card_rects.is_empty() and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse = get_viewport().get_mouse_position()
		for entry in _choice_card_rects:
			var pos = _choice_panel.position + entry.rect.position
			if mouse.x >= pos.x and mouse.x <= pos.x + entry.rect.size.x and mouse.y >= pos.y and mouse.y <= pos.y + entry.rect.size.y:
				if _choice_panel.name == "SkillUpgradePanel":
					_on_skill_upgrade_selected(entry.skill)
				else:
					_on_skill_choice_selected(entry.skill)
				return


func _on_skill_upgrade_selected(skill: SkillBase):
	if not _skill_manager:
		_close_skill_choice()
		return
	for existing in _skill_manager.skills:
		if existing.skill_name == skill.skill_name:
			var old = existing.level
			existing.level += 1
			_skill_manager.skill_upgraded.emit(existing, old, existing.level)
			Debug.log("[技能升级] %s: Lv.%d → Lv.%d" % [existing.skill_name, old, existing.level])
			break
	_close_skill_choice()


func _on_skill_choice_selected(skill: SkillBase):
	if not _skill_manager:
		_close_skill_choice()
		return
	var dup = skill.duplicate(true)
	if _skill_manager.add_or_upgrade(dup):
		Debug.log("[技能选择] 选中: %s (Lv.%d)" % [dup.skill_name, dup.level])
	_close_skill_choice()


func _close_skill_choice():
	get_tree().paused = false
	if _choice_panel:
		_choice_panel.queue_free()
		_choice_panel = null
	_choice_card_rects.clear()
