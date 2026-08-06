extends Node2D
class_name LoadoutScene

# loadout_scene — 纯 2D 整备场景（q-0：放弃 Control 覆盖层，改为 Node2D 世界）
#
# 设计：小人作为 Area2D 自由摆放在 2D 世界（圆形碰撞 + Sprite2D，坐标写死在 CHAR_POS，
# 未来引入美术资源即可自由挪动，不再受 HBox/Grid 容器约束）。卡片副屏 + 底部栏为
# CanvasLayer 上的 Control 覆盖层，复用 HUD 的 _make_item_card，保持与旧 loadout 一致的语义接口。
#
# 进入整备：hud.hide() 隐藏 Game Boy 外框 + 战斗 HUD（同时根治旧整备 BG alpha=0.98 透出敌人文字的 D 项）。
# 离开/开战：hide_screen() 内 hud.show() 还原。铁砧是 hud 的子覆盖层，故点铁砧小人时先 hud.show() 再开。

var controller
var hud: BattleHud

const CHAR_CATS := ["weapon", "skill", "active", "passive"]
const TITLES := {"weapon": "武器", "skill": "技能", "active": "消耗品", "passive": "护符"}
const TEX := {
	"weapon": "res://assets/wq.png",
	"skill":  "res://assets/jn.png",
	"active": "res://assets/xh.png",
	"passive": "res://assets/hf.png",
	"anvil":  "res://assets/tz.png",
}
# 自由摆放坐标（viewport 480×270；副屏占右 ~41%，小人居左 60%）
const CHAR_POS := {
	"weapon":  Vector2(72, 96),
	"skill":   Vector2(150, 70),
	"active":  Vector2(158, 150),
	"passive": Vector2(72, 176),
	"anvil":   Vector2(214, 112),
}
const SPRITE_TARGET := 44.0     # 小人目标高度(px)
const RING_R := 28.0            # 选中环半径
const SUB_OPEN_X := 282.0       # 副屏展开时左上 x
const SUB_W := 196.0
const SUB_Y := 26.0
const SUB_H := 184.0
const CHARS_SHIFT := -42.0      # 副屏展开时小人整体左移量

var selected_char := "weapon"
var loadout_cards := []         # 副屏卡片元数据 {path, btn, selected, kind}
var sub_open := false
var _tween: Tween

# 2D 世界
var chars_root: Node2D
var ring: Line2D

# UI 覆盖层（CanvasLayer / Control）
var ui_root: Control
var sub_panel: PanelContainer
var sub_head: Label
var sub_strip: HBoxContainer
var sub_list: VBoxContainer
var title_label: Label
var rule_label: Label
var count_label: Label
var anvil_label: Label
var confirm_btn: Button


func _ready() -> void:
	_build_world()
	_build_ui()
	queue_redraw()


func _draw() -> void:
	# 整备底：完全不透明（alpha=1.0），避免透出底层战斗页（根治 D 项）
	draw_rect(Rect2(0, 0, 480, 270), Color(0.06, 0.06, 0.10, 1.0))


# ---- 2D 世界：小人 ----

func _build_world() -> void:
	chars_root = Node2D.new()
	add_child(chars_root)
	ring = _make_ring()
	ring.position = CHAR_POS[selected_char]
	chars_root.add_child(ring)
	for cat in CHAR_CATS:
		_add_char(cat, false)
	_add_char("anvil", true)


func _add_char(cat: String, is_anvil: bool) -> void:
	var area := Area2D.new()
	area.name = "Char_" + cat
	area.position = CHAR_POS[cat]
	area.input_pickable = true
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = SPRITE_TARGET * 0.5 + 4
	shape.shape = circle
	area.add_child(shape)
	var sprite := Sprite2D.new()
	sprite.texture = load(TEX[cat])
	if sprite.texture != null:
		var s := SPRITE_TARGET / float(sprite.texture.get_height())
		sprite.scale = Vector2(s, s)
	area.add_child(sprite)
	if is_anvil:
		area.input_event.connect(_on_char_input.bind("anvil"))
	else:
		area.input_event.connect(_on_char_input.bind(cat))
	chars_root.add_child(area)


func _make_ring() -> Line2D:
	var r := Line2D.new()
	r.width = 2
	r.closed = true
	r.default_color = Palette.CARD_SEL_BORDER
	var pts := PackedVector2Array()
	for i in range(28):
		var a := TAU * float(i) / 28.0
		pts.append(Vector2(cos(a), sin(a)) * RING_R)
	r.points = pts
	return r


func _on_char_input(_vp, event, _idx, cat: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if cat == "anvil":
			_on_anvil_pressed()
		else:
			_on_char_pressed(cat)


# ---- UI 覆盖层 ----

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 空白处点击穿透到 2D 小人
	layer.add_child(ui_root)

	title_label = Label.new()
	title_label.text = "⚙ 整备 · 选择携带物品"
	title_label.add_theme_font_size_override("font_size", TypeScale.TITLE)
	title_label.add_theme_color_override("font_color", Palette.TITLE)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.position = Vector2(10, 4)
	ui_root.add_child(title_label)

	rule_label = Label.new()
	rule_label.text = "点小人查看该类目 · 铁砧进入锻造"
	rule_label.add_theme_font_size_override("font_size", TypeScale.CAPTION)
	rule_label.add_theme_color_override("font_color", Palette.MUTED)
	rule_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule_label.position = Vector2(10, 18)
	ui_root.add_child(rule_label)

	# 副屏面板（自由 Control，anchor 全 0 → position/size 即像素，便于 tween 滑入）
	sub_panel = PanelContainer.new()
	sub_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	sub_panel.anchor_left = 0.0
	sub_panel.anchor_top = 0.0
	sub_panel.anchor_right = 0.0
	sub_panel.anchor_bottom = 0.0
	sub_panel.offset_left = SUB_OPEN_X
	sub_panel.offset_top = SUB_Y
	sub_panel.offset_right = SUB_OPEN_X + SUB_W
	sub_panel.offset_bottom = SUB_Y + SUB_H
	sub_panel.add_theme_stylebox_override("panel", _panel_style())
	ui_root.add_child(sub_panel)

	var vbox := VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	sub_panel.add_child(vbox)

	sub_head = Label.new()
	sub_head.add_theme_font_size_override("font_size", TypeScale.LEAD)
	sub_head.add_theme_color_override("font_color", Palette.TITLE)
	sub_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sub_head)

	sub_strip = HBoxContainer.new()
	vbox.add_child(sub_strip)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	sub_list = VBoxContainer.new()
	sub_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_list.add_theme_constant_override("separation", 2)
	scroll.add_child(sub_list)

	# 底部栏
	var bot := HBoxContainer.new()
	bot.mouse_filter = Control.MOUSE_FILTER_STOP
	bot.anchor_left = 0.0
	bot.anchor_top = 0.0
	bot.anchor_right = 0.0
	bot.anchor_bottom = 0.0
	bot.offset_left = 0.0
	bot.offset_top = 216.0
	bot.offset_right = 480.0
	bot.offset_bottom = 270.0
	bot.add_theme_constant_override("separation", 8)
	ui_root.add_child(bot)

	count_label = Label.new()
	count_label.add_theme_font_size_override("font_size", TypeScale.META)
	count_label.add_theme_color_override("font_color", Palette.TITLE)
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bot.add_child(count_label)

	anvil_label = Label.new()
	anvil_label.add_theme_font_size_override("font_size", TypeScale.TINY)
	anvil_label.add_theme_color_override("font_color", Palette.MUTED)
	anvil_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	anvil_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bot.add_child(anvil_label)

	confirm_btn = Button.new()
	confirm_btn.text = "确认开战 ▶"
	confirm_btn.add_theme_font_size_override("font_size", TypeScale.MEDIUM)
	confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot.add_child(confirm_btn)


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var bgc := Palette.PANEL_BG
	bgc.a = 1.0          # 副屏必须不透明，否则主世界内容透出
	sb.bg_color = bgc
	sb.border_color = Palette.PANEL_BORDER
	sb.set_border_width_all(Palette.BORDER_WIDTH)
	sb.set_corner_radius_all(Palette.PANEL_RADIUS)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


# ---- 公开语义接口（与旧 loadout 一致，供 battle_hud 薄包装调用）----

func configure(ctrl, h: BattleHud) -> void:
	controller = ctrl
	hud = h
	title_label.text = "⚙ 整备 · 选择携带物品"
	confirm_btn.text = "确认开战 ▶"
	confirm_btn.pressed.connect(controller._confirm_loadout)
	_update_loadout_anvil()


func show_screen() -> void:
	controller.in_loadout = true
	hud.hide()                 # 隐藏 Game Boy 外框 + 战斗 HUD
	visible = true
	_update_loadout_anvil()
	_fill_sub(selected_char)
	_update_loadout_count()
	_refresh_char_highlight()
	_set_sub_open(true, true)  # 默认展开副屏，小人左移


func hide_screen() -> void:
	controller.in_loadout = false
	visible = false
	hud.show()                 # 回到战斗 HUD（含外框）


# ---- 小人交互 ----

func _refresh_char_highlight() -> void:
	ring.position = CHAR_POS[selected_char]


func _on_char_pressed(cat: String) -> void:
	if not sub_open:
		_open_sub(cat)
	else:
		selected_char = cat
		_refresh_char_highlight()
		_fill_sub(cat)
		_update_loadout_count()


func _on_anvil_pressed() -> void:
	# 铁砧是 hud 的子覆盖层：先显 hud 再开，并隐藏本 2D 场景
	visible = false
	hud.show()
	hud._show_anvil_screen()


func _open_sub(cat: String) -> void:
	selected_char = cat
	_refresh_char_highlight()
	_fill_sub(cat)
	_set_sub_open(true)
	_update_loadout_count()


func _set_sub_open(open: bool, instant := false) -> void:
	sub_open = open
	if _tween and _tween.is_valid():
		_tween.kill()
	var sub_x := SUB_OPEN_X if open else 480.0
	var chars_x := CHARS_SHIFT if open else 0.0
	if instant:
		sub_panel.offset_left = sub_x
		chars_root.position.x = chars_x
	else:
		_tween = create_tween()
		_tween.tween_property(sub_panel, "offset_left", sub_x, 0.18) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween.parallel().tween_property(chars_root, "position:x", chars_x, 0.18) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ---- 副屏内容 ----

func _fill_sub(cat: String) -> void:
	sub_head.text = _cat_count_text(cat, TITLES[cat])
	for c in sub_list.get_children():
		sub_list.remove_child(c)
		c.queue_free()
	loadout_cards = []
	for path in controller._owned_arr(cat):
		var data: Resource = load(path)
		var card = hud._make_item_card(data, path, cat)
		sub_list.add_child(card["btn"])
		loadout_cards.append(card)
	_sync_card_selection()
	_update_loadout_cards_visual()
	_refresh_slot_strip()


func _refresh_slot_strip() -> void:
	var category := selected_char
	for c in sub_strip.get_children():
		sub_strip.remove_child(c)
		c.queue_free()
	var used = controller._sel_arr(category).size()
	var unlocked = controller._cat_max(category)
	var ceiling = controller._cat_cap(category)
	var uncapped = (ceiling == controller.state.UNCAPPED)
	var cells = unlocked if uncapped else ceiling
	for i in cells:
		var glyph := "·"
		var tint := Palette.PANEL_BORDER
		if i < used:
			glyph = "◆"
			tint = Palette.CARD_SEL_BORDER
		elif i < unlocked:
			glyph = "◇"
			tint = Palette.MUTED
		var g = hud._label(glyph, 12)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.add_theme_color_override("font_color", tint)
		sub_strip.add_child(g)
	if uncapped:
		var plus = hud._label("＋", 12)
		plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plus.add_theme_color_override("font_color", Palette.PANEL_BORDER)
		sub_strip.add_child(plus)


func _update_loadout_cards_visual() -> void:
	var wfull = controller.state.selected_loadout.size() >= controller._cat_max("weapon")
	var cfull = controller._sel_arr("active").size() >= controller._cat_max("active")
	var hfull = controller.state.selected_charms.size() >= controller._cat_max("passive")
	var bfull = controller.state.selected_skills.size() >= controller._cat_max("skill")
	for card in loadout_cards:
		var sb := StyleBoxFlat.new()
		if card["selected"]:
			sb.bg_color = Palette.CARD_SEL_BG
			sb.border_color = Palette.CARD_SEL_BORDER
			sb.set_border_width_all(2)
			card["btn"].disabled = false
		else:
			sb.bg_color = Palette.CARD_NORM_BG
			sb.border_color = Palette.CARD_NORM_BORDER
			sb.set_border_width_all(1)
			var cf = (card["kind"] == "weapon" and wfull) or (card["kind"] == "active" and cfull) or (card["kind"] == "passive" and hfull) or (card["kind"] == "skill" and bfull)
			card["btn"].disabled = cf
		card["btn"].add_theme_stylebox_override("normal", sb)
		card["btn"].add_theme_stylebox_override("hover", sb)
		card["btn"].add_theme_stylebox_override("pressed", sb)
		card["btn"].add_theme_stylebox_override("disabled", sb)


func _cat_count_text(cat: String, label: String) -> String:
	var grow = "＋" if controller._cat_cap(cat) == controller.state.UNCAPPED else ""
	return "%s %d/%d%s" % [label, controller._sel_arr(cat).size(), controller._cat_max(cat), grow]


func _update_loadout_count() -> void:
	count_label.text = "%s · %s · %s · %s" % [
		_cat_count_text("weapon", "武器"), _cat_count_text("skill", "技能"),
		_cat_count_text("active", "消耗品"), _cat_count_text("passive", "护符")]
	sub_head.text = _cat_count_text(selected_char, TITLES[selected_char])
	_refresh_slot_strip()
	var ok = controller.state.selected_loadout.size() >= controller.state.LOADOUT_MIN
	confirm_btn.disabled = not ok
	confirm_btn.text = ("确认开战 ▶" if ok else "至少选 %d 把武器 ▶" % controller.state.LOADOUT_MIN)


func _sync_card_selection() -> void:
	var weapons = controller.state.selected_loadout
	var consumables = controller.state.selected_consumables
	var charms = controller.state.selected_charms
	var skills = controller.state.selected_skills
	for card in loadout_cards:
		match card["kind"]:
			"weapon":
				card["selected"] = weapons.has(card["path"])
			"active":
				card["selected"] = consumables.has(card["path"])
			"passive":
				card["selected"] = charms.has(card["path"])
			"skill":
				card["selected"] = skills.has(card["path"])


func _update_loadout_anvil() -> void:
	if anvil_label != null:
		anvil_label.text = "点数:%d" % controller.state.meta["anvil_points"]


# 铁砧授予等 owned 变化后，整备页开着时立即重建副屏（隐藏时由 show_screen 自动重建）
func refresh_data() -> void:
	_fill_sub(selected_char)
	_update_loadout_count()
	_update_loadout_anvil()
