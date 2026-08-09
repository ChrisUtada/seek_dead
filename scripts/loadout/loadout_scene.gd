extends Node2D
class_name LoadoutScene

# loadout_scene — 纯 2D 整备场景（Node2D 世界 + CanvasLayer 覆盖层）。
# 布局已抽到 scenes/ui/loadout_scene.tscn：小人坐标、副屏面板、底部栏、标签文字与配色
# 全部可在编辑器里直接拖/改。本脚本只负责交互（点击命中）与动态内容（卡片/槽位条/高亮）。
#
# 进入整备：hud.hide() 隐藏 Game Boy 外框 + 战斗 HUD（根治旧整备 BG 透出敌人文字的 D 项）。
# 离开/开战：hide_screen() 内 hud.show() 还原。铁砧是 hud 的子覆盖层，故点铁砧小人时先 hud.show() 再开。

var controller
var hud: BattleHud

const CHAR_CATS := ["weapon", "skill", "active", "passive"]
const TITLES := {"weapon": "武器", "skill": "技能", "active": "消耗品", "passive": "护符"}
const SPRITE_TARGET := 44.0     # 小人目标高度(px)，_ready 按贴图高度缩放（位置在 tscn 里手动调）
const RING_R := 28.0            # 选中环半径
const SUB_OPEN_X := 282.0       # 副屏展开时左上 x（与 tscn SubPanel.offset_left 对应）
const CHARS_SHIFT := -42.0      # 副屏展开时小人整体左移量

var selected_char := "weapon"
var loadout_cards := []         # 副屏卡片元数据 {path, btn, selected, kind}
var sub_open := false
var _tween: Tween

# ---- 静态节点（来自 scenes/ui/loadout_scene.tscn，可在编辑器调整）----
@onready var chars_root: Node2D = $CharsRoot
@onready var ring: Line2D = $CharsRoot/Ring
@onready var _ui_layer: CanvasLayer = $UILayer
@onready var ui_root: Control = $UILayer/UIRoot
@onready var title_label: Label = $UILayer/UIRoot/TitleLabel
@onready var rule_label: Label = $UILayer/UIRoot/RuleLabel
@onready var sub_panel: PanelContainer = $UILayer/UIRoot/SubPanel
@onready var sub_head: Label = $UILayer/UIRoot/SubPanel/SubVBox/SubHead
@onready var sub_strip: HBoxContainer = $UILayer/UIRoot/SubPanel/SubVBox/SubStrip
@onready var sub_list: VBoxContainer = $UILayer/UIRoot/SubPanel/SubVBox/SubScroll/SubList
@onready var count_label: Label = $UILayer/UIRoot/BottomBar/CountLabel
@onready var anvil_label: Label = $UILayer/UIRoot/BottomBar/AnvilLabel
@onready var confirm_btn: Button = $UILayer/UIRoot/BottomBar/ConfirmBtn

var char_nodes := {}            # cat -> Area2D（坐标来自 tscn，可在编辑器改，_input 按实际坐标命中）


func _ready() -> void:
	char_nodes = {
		"weapon": $CharsRoot/Char_weapon,
		"skill": $CharsRoot/Char_skill,
		"active": $CharsRoot/Char_active,
		"passive": $CharsRoot/Char_passive,
		"anvil": $CharsRoot/Char_anvil,
	}
	# 按贴图高度把小人缩放到 SPRITE_TARGET；位置保留 tscn 里的手动摆放
	for cat in char_nodes:
		var sp: Sprite2D = char_nodes[cat].get_node_or_null("Sprite2D")
		if sp != null and sp.texture != null:
			var s := SPRITE_TARGET / float(sp.texture.get_height())
			sp.scale = Vector2(s, s)
	_init_ring_points()
	_refresh_char_highlight()


func _init_ring_points() -> void:
	var pts := PackedVector2Array()
	for i in range(28):
		var a := TAU * float(i) / 28.0
		pts.append(Vector2(cos(a), sin(a)) * RING_R)
	ring.points = pts


# 手动命中测试：不依赖 Area2D/Control 输入派发顺序（CanvasLayer 上的 Control 会干扰
# Area2D 的 input_event），直接对小人圆心做距离判定，且圆心取 tscn 实际坐标，编辑可拖。
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		var mp: Vector2 = mb.position
		var r := SPRITE_TARGET * 0.5 + 4          # 与碰撞圆同半径
		var dx := chars_root.position.x          # 副屏展开时小人整体左移
		for cat in CHAR_CATS:
			var wp: Vector2 = char_nodes[cat].position + Vector2(dx, 0.0)
			if mp.distance_to(wp) <= r:
				_on_char_pressed(cat)
				get_viewport().set_input_as_handled()
				return
		var ap: Vector2 = char_nodes["anvil"].position + Vector2(dx, 0.0)
		if mp.distance_to(ap) <= r:
			_on_anvil_pressed()
			get_viewport().set_input_as_handled()


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
	# 双重防御：Node2D.visible + CanvasLayer.visible + process_mode，
	# 避免 Godot 4.7 在某些情况下 CanvasLayer 不随父级 visible 级联。
	visible = true
	if _ui_layer != null:
		_ui_layer.visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	_update_loadout_anvil()
	_fill_sub(selected_char)
	_update_loadout_count()
	_refresh_char_highlight()
	_set_sub_open(true, true)  # 默认展开副屏，小人左移


func hide_screen() -> void:
	controller.in_loadout = false
	visible = false
	if _ui_layer != null:
		_ui_layer.visible = false          # 显式隐藏 CanvasLayer 覆盖层
	process_mode = Node.PROCESS_MODE_DISABLED   # 顺手停掉本节点的 _input/_process，连鼠标事件都不再接收
	hud.show()                 # 回到战斗 HUD（含外框）


# ---- 小人交互 ----

func _refresh_char_highlight() -> void:
	ring.position = char_nodes[selected_char].position


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
	# ⚠ CanvasLayer（UILayer=layer 10）不随父级 visible 级联——必须显式隐藏，否则武器栏/确认按钮盖在铁砧上
	visible = false
	if _ui_layer != null:
		_ui_layer.visible = false
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
	for path in controller._meta_store.owned_arr(cat):
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
		var g = hud._label(glyph, TypeScale.TITLE)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.add_theme_color_override("font_color", tint)
		sub_strip.add_child(g)
	if uncapped:
		var plus = hud._label("＋", TypeScale.TITLE)
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
