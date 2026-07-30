class_name HUD
extends CanvasLayer

const _WeaponNode = preload("res://scripts/battle/weapon_node.gd")
const _EquipmentPanel = preload("res://scenes/ui/equipment_panel.gd")

@onready var weapon_label: Label = $WeaponLabel

var _bars: Dictionary = {}            # 仅弹药显示使用（状态条已迁出 StatusBars）
var _equipment_panel: EquipmentPanel = null
var _skill_manager: SkillManager
var _escape_btn: ColorRect = null
var _lobby_btn: ColorRect = null
var _crosshair: ColorRect
var _overlay: ColorRect
var _flash_overlay: ColorRect
var _overlay_label: Label
var _overlay_button: Label
var _is_paused: bool = false
var _death_overlay: bool = false

# 子组件：各自承载一类 HUD 职责，由 _ready 实例化并 add_child
var _status_bars: StatusBars = StatusBars.new()
var _damage_spawner: DamageNumberSpawner = DamageNumberSpawner.new()
var _skill_bar: SkillBar = SkillBar.new()
var _skill_choice_ui: SkillChoiceUI = SkillChoiceUI.new()

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_status_bars)
	add_child(_damage_spawner)
	add_child(_skill_bar)
	add_child(_skill_choice_ui)
	_build_crosshair()
	_build_overlay()
	_build_ammo_display()
	_build_escape_bar()
	_build_utility_bar()
	_connect_player()
	EventManager.damage_dealt.connect(_on_damage_dealt)


func _build_crosshair():
	_crosshair = ColorRect.new()
	_crosshair.name = "Crosshair"
	_crosshair.size = Vector2(8, 8)
	_crosshair.color = Color(1, 1, 1, 0.7)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)

func _build_overlay():
	_overlay = ColorRect.new()
	_overlay.name = "Overlay"
	_overlay.size = Vector2(640, 360)
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	_overlay_label = Label.new()
	_overlay_label.name = "OverlayLabel"
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_overlay_label.position = Vector2(0, 130)
	_overlay_label.size = Vector2(640, 40)
	_overlay_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_overlay_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_overlay_label.add_theme_constant_override("outline_size", 3)
	_overlay_label.add_theme_font_size_override("font_size", 22)
	add_child(_overlay_label)

	_flash_overlay = ColorRect.new()
	_flash_overlay.name = "FlashOverlay"
	_flash_overlay.size = Vector2(640, 360)
	_flash_overlay.color = Color(0, 0, 0, 0)
	_flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash_overlay)

	_overlay_button = Label.new()
	_overlay_button.name = "OverlayButton"
	_overlay_button.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_button.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_overlay_button.position = Vector2(0, 180)
	_overlay_button.size = Vector2(640, 20)
	_overlay_button.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_overlay_button.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_overlay_button.add_theme_constant_override("outline_size", 2)
	_overlay_button.add_theme_font_size_override("font_size", 14)
	add_child(_overlay_button)

func _connect_player():
	var player: Node2D = null
	while player == null:
		player = EntityRegistry.players[0] if EntityRegistry.get_player_count() > 0 else null
		if player == null:
			await get_tree().process_frame

	var st = player.state
	st.died.connect(_on_player_died)
	_status_bars.connect_player(st)

	player.weapon.weapon_changed.connect(_on_weapon_changed)
	player.weapon.active_hand_changed.connect(_on_active_hand_changed)
	var active_node = player.weapon.get_active_weapon_node()
	if active_node:
		_on_weapon_changed(active_node, player.weapon.active_hand)

	var ammo_node = player.get_node_or_null("AmmoSystem")
	if ammo_node:
		ammo_node.ammo_changed.connect(_on_ammo_changed)
		ammo_node.reload_started.connect(_on_reload_started)
		ammo_node.reload_finished.connect(_on_reload_finished)
		_on_ammo_changed(ammo_node.current_ammo, ammo_node.max_ammo)

	var skill_node = player.get_node_or_null("SkillManager")
	if skill_node:
		_skill_manager = skill_node
		skill_node.skill_upgraded.connect(_on_skill_upgraded)
		skill_node.skill_replace_needed.connect(_on_skill_replace_needed)
		_skill_bar.connect_manager(skill_node)
		_skill_choice_ui.set_skill_manager(skill_node)

	if "escape_skill" in player and player.escape_skill:
		var esc = player.escape_skill
		esc.channel_started.connect(_on_escape_channel_started)
		esc.channel_progress.connect(_on_escape_channel_progress)
		esc.channel_cancelled.connect(_on_escape_channel_cancelled)
		esc.channel_completed.connect(_on_escape_channel_completed)

	_init_equipment_panel(player)
	_connect_equipment_signals(player)

func _init_equipment_panel(player: Node2D):
	_equipment_panel = _EquipmentPanel.new()
	_equipment_panel.name = "EquipmentPanel"
	_equipment_panel.hide()
	add_child(_equipment_panel)
	_equipment_panel.init(player)


func _connect_equipment_signals(player: Node2D):
	var mgr = player.get_node_or_null("EquipmentManager") as EquipmentManager
	if mgr:
		mgr.equipment_equipped.connect(_on_equipment_changed)
		mgr.equipment_unequipped.connect(_on_equipment_changed)
	_damage_spawner.connect_player_equipment(player)
	var inv = player.get_node_or_null("EquipmentInventory") as EquipmentInventory
	if inv:
		inv.inventory_changed.connect(_on_equipment_changed)
		inv.item_added.connect(_on_item_added.bind(player))
		inv.item_removed.connect(_on_item_removed)

func _on_item_removed(item: EquipmentBase, _index: int):
	Debug.log("[丢弃] %s" % item.equipment_name)

func _on_equipment_changed(_a = null, _b = null):
	if _equipment_panel and _equipment_panel.visible:
		_equipment_panel.refresh()

func _on_item_added(item: EquipmentBase, index: int, player: Node2D):
	var mgr = player.get_node_or_null("EquipmentManager") as EquipmentManager
	if not mgr:
		return
	if mgr.get_equipped(item.slot) != null:
		Debug.log("[拾取→背包] %s (槽位已被占)" % item.equipment_name)
		return
	var inv = player.get_node_or_null("EquipmentInventory") as EquipmentInventory
	if not inv:
		return
	inv.remove_item(index)
	mgr.equip(item)
	Debug.log("[拾取→装备] %s" % item.equipment_name)


func _build_escape_bar():
	var bg = ColorRect.new()
	bg.name = "EscapeBarBg"
	bg.position = Vector2(220, 200)
	bg.size = Vector2(200, 16)
	bg.color = Color(0.1, 0.1, 0.1, 0.8)
	bg.visible = false
	add_child(bg)
	var fill = ColorRect.new()
	fill.name = "EscapeBarFill"
	fill.position = Vector2(0, 0)
	fill.size = Vector2(0, 16)
	fill.color = Color(1, 0.7, 0.1, 0.9)
	bg.add_child(fill)
	var label = Label.new()
	label.name = "EscapeBarLabel"
	label.position = Vector2(0, 0)
	label.size = Vector2(200, 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = "撤离中...  再次按Z取消"
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_constant_override("outline_size", 1)
	label.add_theme_font_size_override("font_size", 10)
	bg.add_child(label)


func _build_utility_bar():
	var start_x = 364
	var y = 324
	var sz = Vector2(28, 28)
	var gap = 4

	_escape_btn = ColorRect.new()
	_escape_btn.name = "EscapeBtn"
	_escape_btn.position = Vector2(start_x, y)
	_escape_btn.size = sz
	_escape_btn.color = Color(0.25, 0.25, 0.25, 0.85)
	add_child(_escape_btn)
	var zkey = Label.new()
	zkey.text = "Z"
	zkey.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zkey.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	zkey.position = Vector2(2, 1)
	zkey.size = Vector2(sz.x - 4, 12)
	zkey.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	zkey.add_theme_constant_override("outline_size", 1)
	zkey.add_theme_font_size_override("font_size", 8)
	_escape_btn.add_child(zkey)
	var zname = Label.new()
	zname.name = "EscapeName"
	zname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zname.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	zname.position = Vector2(0, 0)
	zname.size = sz
	zname.add_theme_color_override("font_color", Color(1, 1, 1))
	zname.add_theme_constant_override("outline_size", 1)
	zname.add_theme_font_size_override("font_size", 7)
	zname.text = "撤离"
	_escape_btn.add_child(zname)
	var zcd = ColorRect.new()
	zcd.name = "EscapeCD"
	zcd.position = Vector2(0, 0)
	zcd.size = Vector2(sz.x, 0)
	zcd.color = Color(0, 0, 0, 0.75)
	_escape_btn.add_child(zcd)

	_lobby_btn = ColorRect.new()
	_lobby_btn.name = "LobbyBtn"
	_lobby_btn.position = Vector2(start_x + sz.x + gap, y)
	_lobby_btn.size = sz
	_lobby_btn.color = Color(0.2, 0.2, 0.25, 0.85)
	add_child(_lobby_btn)
	var ukey = Label.new()
	ukey.text = "U"
	ukey.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ukey.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	ukey.position = Vector2(2, 1)
	ukey.size = Vector2(sz.x - 4, 12)
	ukey.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	ukey.add_theme_constant_override("outline_size", 1)
	ukey.add_theme_font_size_override("font_size", 8)
	_lobby_btn.add_child(ukey)
	var uname = Label.new()
	uname.text = "返回"
	uname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	uname.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	uname.position = Vector2(0, 0)
	uname.size = sz
	uname.add_theme_color_override("font_color", Color(1, 1, 1))
	uname.add_theme_constant_override("outline_size", 1)
	uname.add_theme_font_size_override("font_size", 7)
	_lobby_btn.add_child(uname)


func _build_ammo_display():
	var label = Label.new()
	label.name = "AmmoLabel"
	label.position = Vector2(10, 76)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 1)
	label.add_theme_font_size_override("font_size", 10)
	label.text = "弹药: --/--"
	add_child(label)
	_bars["ammo"] = {label = label}

func _on_ammo_changed(current: int, max_cap: int):
	if not _bars.has("ammo"):
		return
	_bars.ammo.label.text = "弹药: %d/%d" % [current, max_cap]
	if max_cap > 0 and float(current) / float(max_cap) < 0.25:
		_bars.ammo.label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	else:
		_bars.ammo.label.add_theme_color_override("font_color", Color(1, 1, 1))

func _on_reload_started():
	if _bars.has("ammo"):
		_bars.ammo.label.text = "弹药: 装弹中..."

func _on_escape_channel_started(_duration: float):
	var bg = get_node_or_null("EscapeBarBg")
	if bg:
		bg.visible = true
		bg.get_node("EscapeBarFill").size.x = 0


func _on_escape_channel_progress(ratio: float):
	var fill = get_node_or_null("EscapeBarBg/EscapeBarFill")
	if fill:
		fill.size.x = 200 * ratio


func _on_escape_channel_cancelled():
	var bg = get_node_or_null("EscapeBarBg")
	if bg:
		bg.visible = false
		bg.get_node("EscapeBarFill").size.x = 0


func _on_escape_channel_completed():
	var bg = get_node_or_null("EscapeBarBg")
	if bg:
		bg.visible = false
		bg.get_node("EscapeBarFill").size.x = 0


func _on_skill_upgraded(skill: SkillBase, old_level: int, new_level: int):
	var player = EntityRegistry.players[0] if EntityRegistry.get_player_count() > 0 else null
	if not player:
		return
	var text = "%s +1 Lv.%d!" % [skill.skill_name, new_level]
	_damage_spawner.spawn_floating_text(player.global_position, text, Color(0.3, 1, 0.3))


var _replace_popup: Control = null
var _pending_skill: SkillBase = null


func _on_skill_replace_needed(new_skill: SkillBase):
	if _replace_popup:
		return
	_pending_skill = new_skill
	_replace_popup = Control.new()
	_replace_popup.name = "ReplacePopup"
	_replace_popup.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE, 4)
	_replace_popup.size = Vector2(220, 100)
	add_child(_replace_popup)

	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.1, 0.9)
	bg.size = Vector2(220, 100)
	_replace_popup.add_child(bg)

	var title = Label.new()
	title.text = "技能替换"
	title.position = Vector2(8, 4)
	title.size = Vector2(200, 16)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	title.add_theme_font_size_override("font_size", 12)
	_replace_popup.add_child(title)

	var prompt = Label.new()
	prompt.text = "选择要替换的技能："
	prompt.position = Vector2(8, 20)
	prompt.size = Vector2(200, 14)
	prompt.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	prompt.add_theme_font_size_override("font_size", 10)
	_replace_popup.add_child(prompt)

	var slot_size = 36
	var gap = 4
	var start_x = 8
	for i in range(_skill_manager.skills.size()):
		var btn = ColorRect.new()
		btn.name = "SlotBtn%d" % i
		btn.position = Vector2(start_x + i * (slot_size + gap), 38)
		btn.size = Vector2(slot_size, slot_size)
		btn.color = Color(0.3, 0.3, 0.5, 0.9)
		_replace_popup.add_child(btn)

		var lbl = Label.new()
		lbl.text = _skill_manager.skills[i].skill_name
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.position = Vector2(0, 0)
		lbl.size = Vector2(slot_size, slot_size)
		lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		lbl.add_theme_font_size_override("font_size", 9)
		btn.add_child(lbl)

		var lv = Label.new()
		lv.text = "Lv%d" % _skill_manager.skills[i].level
		lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lv.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		lv.position = Vector2(0, 0)
		lv.size = Vector2(slot_size - 1, slot_size - 1)
		lv.add_theme_color_override("font_color", Color(0.8, 0.8, 0.2))
		lv.add_theme_font_size_override("font_size", 8)
		btn.add_child(lv)

		var click_area = Area2D.new()
		var shape = CollisionShape2D.new()
		var rect = RectangleShape2D.new()
		rect.size = Vector2(slot_size, slot_size)
		shape.shape = rect
		click_area.add_child(shape)
		click_area.global_position = btn.global_position + btn.size / 2
		var idx = i
		click_area.input_event.connect(func(_v, _e, _i): _on_replace_confirm(idx))
		_replace_popup.add_child(click_area)
		click_area.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var discard_btn = ColorRect.new()
	discard_btn.name = "DiscardBtn"
	discard_btn.position = Vector2(start_x + _skill_manager.skills.size() * (slot_size + gap), 38)
	discard_btn.size = Vector2(slot_size, slot_size)
	discard_btn.color = Color(0.5, 0.3, 0.3, 0.9)
	_replace_popup.add_child(discard_btn)

	var discard_lbl = Label.new()
	discard_lbl.text = "放弃"
	discard_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	discard_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	discard_lbl.position = Vector2(0, 0)
	discard_lbl.size = Vector2(slot_size, slot_size)
	discard_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	discard_lbl.add_theme_font_size_override("font_size", 9)
	discard_btn.add_child(discard_lbl)

	var discard_click = Area2D.new()
	var dshape = CollisionShape2D.new()
	var drect = RectangleShape2D.new()
	drect.size = Vector2(slot_size, slot_size)
	dshape.shape = drect
	discard_click.add_child(dshape)
	discard_click.input_event.connect(func(_v, _e, _i): _on_replace_discard())
	_replace_popup.add_child(discard_click)


func _close_replace_popup():
	if _replace_popup:
		_replace_popup.queue_free()
		_replace_popup = null
	_pending_skill = null


func _on_replace_confirm(index: int):
	if not _pending_skill or not _skill_manager:
		_close_replace_popup()
		return
	_skill_manager.replace_skill(index, _pending_skill.duplicate(true))
	Debug.log("[技能替换] 槽%d → %s" % [index, _pending_skill.skill_name])
	_close_replace_popup()


func _on_replace_discard():
	Debug.log("[技能替换] 放弃拾取: %s" % [_pending_skill.skill_name if _pending_skill else "null"])
	_close_replace_popup()

func _on_reload_finished():
	if _bars.has("ammo"):
		_bars.ammo.label.text = "弹药: 已装填"

func _on_weapon_changed(weapon: WeaponNode, _hand: int = 0):
	var s = weapon.weapon_data
	if not s:
		return
	var hand_label = "主手" if _hand == 0 else "副手"
	var color = DamageSystem.get_color(s.damage_type)
	weapon_label.text = "%s | %s | 伤害: %.0f | 类型: %s" % [hand_label, s.weapon_name, s.damage, DamageSystem.damage_type_to_string(s.damage_type)]
	weapon_label.add_theme_color_override("font_color", color)

func _on_active_hand_changed(hand: int):
	var wc = EntityRegistry.players[0].weapon as WeaponComponent
	if not wc:
		return
	var node = wc.get_active_weapon_node()
	if node:
		_on_weapon_changed(node, hand)
	else:
		weapon_label.text = ""

func _on_player_died():
	_death_overlay = true
	_show_overlay("你死了", "按 F2 重新开始", Color(0.6, 0.1, 0.1, 0.7))

func _show_overlay(title: String, button_text: String, bg_color: Color):
	_overlay.color = bg_color
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay_label.text = title
	_overlay_button.text = button_text

func _hide_overlay():
	_death_overlay = false
	_overlay.color = Color(0, 0, 0, 0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_label.text = ""
	_overlay_button.text = ""

func _input(event):
	if event.is_action_pressed("pause"):
		_toggle_pause()
	if event.is_action_pressed("restart") and _death_overlay:
		call_deferred("_restart_game")
	if event.is_action_pressed("inventory"):
		_toggle_inventory()
	if event.is_action_pressed("return_lobby") and not _is_paused and not _death_overlay:
		_return_to_lobby()

func _toggle_inventory():
	if not _equipment_panel:
		return
	_equipment_panel.visible = not _equipment_panel.visible
	if _equipment_panel.visible:
		_equipment_panel.refresh()

func _return_to_lobby():
	get_tree().paused = false
	SceneManager.fade_to_scene("res://scenes/ui/lobby.tscn")

func _restart_game():
	_return_to_lobby()

func _toggle_pause():
	_is_paused = not _is_paused
	get_tree().paused = _is_paused
	if _is_paused:
		AudioManager.play_sfx(AudioManager.SfxType.UI_PAUSE)
		_show_overlay("暂停", "按 Esc 继续", Color(0, 0, 0, 0.5))
	else:
		_hide_overlay()

func _process(_delta):
	var mouse = get_viewport().get_mouse_position()
	_crosshair.position = mouse - _crosshair.size / 2
	_update_utility_bar()


# 飘字逻辑已迁入 DamageNumberSpawner，此处仅作转发入口
func spawn_damage_number(world_pos: Vector2, amount: float, is_critical: bool = false):
	_damage_spawner.spawn_damage_number(world_pos, amount, is_critical)

func spawn_floating_text(world_pos: Vector2, text: String, color: Color = Color.WHITE):
	_damage_spawner.spawn_floating_text(world_pos, text, color)

func _trigger_hit_flash(intensity: float = 0.08, color: Color = Color(1, 0.3, 0.3)):
	_flash_overlay.color = Color(color.r, color.g, color.b, intensity)
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_LINEAR)
	tween.tween_property(_flash_overlay, "color", Color(color.r, color.g, color.b, 0), 0.08)

func _on_damage_dealt(attacker: Node2D, defender: Node2D, amount: float, _damage_type: int):
	if not is_instance_valid(defender):
		return
	spawn_damage_number(defender.global_position, amount, false)
	if defender.is_in_group("players"):
		_trigger_hit_flash(0.08, Color(1, 0.3, 0.3))
	elif amount > 50.0:
		_trigger_hit_flash(0.06, Color(1, 0.8, 0.3))


func show_skill_upgrade(sm: SkillManager):
	_skill_choice_ui.show_skill_upgrade(sm)


func show_skill_choice(choices: Array[SkillBase]):
	_skill_choice_ui.show_skill_choice(choices)


func _update_utility_bar():
	var player = EntityRegistry.players[0] if EntityRegistry.get_player_count() > 0 else null
	if not player or not _escape_btn or not _lobby_btn:
		return

	if "escape_skill" in player and player.escape_skill:
		var esc = player.escape_skill
		var cd = _escape_btn.get_node_or_null("EscapeCD")
		if cd:
			var ratio = esc.cooldown_timer / esc.cooldown if esc.cooldown > 0 else 0
			cd.size.y = _escape_btn.size.y * ratio
		if esc.get("_is_channeling"):
			_escape_btn.color = Color(0.8, 0.6, 0.1, 0.85)
		elif esc.cooldown_timer > 0:
			_escape_btn.color = Color(0.25, 0.2, 0.2, 0.85)
		else:
			_escape_btn.color = Color(0.2, 0.5, 0.2, 0.85)

	_lobby_btn.color = Color(0.2, 0.2, 0.25, 0.85) if not get_tree().paused else Color(0.15, 0.15, 0.15, 0.85)
