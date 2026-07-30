class_name SkillBar
extends Node
## 技能栏（2 个槽位）的视觉与冷却显示。由 HUD 实例化并 add_child。
## connect_manager() 注入 SkillManager 后，每帧在 _process 中刷新槽位名称 / 等级 / 冷却遮罩。

var _skill_slots: Array = []
var _skill_manager: SkillManager = null


func _ready():
	_build_skill_bar()


func _build_skill_bar():
	var skill_bar = Control.new()
	skill_bar.name = "SkillBar"
	skill_bar.position = Vector2(272, 324)
	skill_bar.size = Vector2(68, 32)
	add_child(skill_bar)
	var slot_size = 32
	var gap = 4
	for i in range(2):
		var slot = ColorRect.new()
		slot.name = "SkillSlot%d" % i
		slot.position = Vector2(i * (slot_size + gap), 0)
		slot.size = Vector2(slot_size, slot_size)
		slot.color = Color(0.25, 0.25, 0.25, 0.85)
		skill_bar.add_child(slot)
		var key_label = Label.new()
		key_label.text = str(i + 1)
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		key_label.position = Vector2(0, 0)
		key_label.size = Vector2(slot_size, slot_size)
		key_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		key_label.add_theme_constant_override("outline_size", 1)
		key_label.add_theme_font_size_override("font_size", 9)
		slot.add_child(key_label)
		var name_label = Label.new()
		name_label.name = "SkillName"
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.position = Vector2(0, 0)
		name_label.size = Vector2(slot_size, slot_size)
		name_label.add_theme_color_override("font_color", Color(1, 1, 1))
		name_label.add_theme_constant_override("outline_size", 1)
		name_label.add_theme_font_size_override("font_size", 10)
		slot.add_child(name_label)
		var level_label = Label.new()
		level_label.name = "Level"
		level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		level_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		level_label.position = Vector2(0, 0)
		level_label.size = Vector2(slot_size - 1, slot_size - 1)
		level_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.2))
		level_label.add_theme_constant_override("outline_size", 1)
		level_label.add_theme_font_size_override("font_size", 8)
		slot.add_child(level_label)
		var cd_overlay = ColorRect.new()
		cd_overlay.name = "Cooldown"
		cd_overlay.position = Vector2(0, 0)
		cd_overlay.size = Vector2(slot_size, 0)
		cd_overlay.color = Color(0, 0, 0, 0.75)
		slot.add_child(cd_overlay)
		_skill_slots.append(slot)


func connect_manager(sm: SkillManager):
	_skill_manager = sm


func _process(_delta):
	_update_skill_bar()


func _update_skill_bar():
	if not _skill_manager or _skill_slots.size() == 0:
		return
	var player = EntityRegistry.players[0] if EntityRegistry.get_player_count() > 0 else null
	var state = player.state if player and player.state else null
	for i in range(min(_skill_slots.size(), _skill_manager.skills.size())):
		var skill = _skill_manager.skills[i]
		var slot = _skill_slots[i]
		var cd = slot.get_node_or_null("Cooldown")
		if cd:
			var ratio = skill.get_cooldown_ratio()
			cd.size.y = slot.size.y * ratio
		var name_label = slot.get_node_or_null("SkillName")
		if name_label:
			name_label.text = skill.skill_name
		var level_label = slot.get_node_or_null("Level")
		if level_label:
			level_label.text = "Lv%d" % skill.level if skill.level > 0 else ""
		if state and not skill.can_use(state):
			slot.color = Color(0.15, 0.15, 0.15, 0.85)
		else:
			slot.color = Color(0.25, 0.25, 0.25, 0.85)
