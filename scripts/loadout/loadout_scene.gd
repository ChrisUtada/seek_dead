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

# ---- M1-04 转轮带预览（运行时构建，不改 tscn）----
var _preview_btn: Button = null
var _preview_panel: PanelContainer = null
var _preview_box: VBoxContainer = null

# ---- M2 棋盘试玩开关（灰盒期免命令行；只改本进程的 board_config，不写存档）----
var _board_btn: Button = null

# ---- G6-01 生涯成就面板（只读 meta，不改配装/存档）----
var _career_btn: Button = null
var _career_panel: PanelContainer = null
var _career_box: VBoxContainer = null

# ---- G6-05 横向铸式面板（整备选择，写入 anvil_meta.forge_styles）----
var _forge_btn: Button = null
var _forge_panel: PanelContainer = null
var _forge_box: VBoxContainer = null

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
@onready var sub_scroll: ScrollContainer = $UILayer/UIRoot/SubPanel/SubVBox/SubScroll
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
	_build_preview_ui()
	_build_board_toggle()
	_build_career_ui()
	_build_forge_ui()
	_update_loadout_anvil()


func show_screen() -> void:
	controller.in_loadout = true
	apply_soft_default()   # T29（2026-08-24 拍板：立即做基础版）——四类全空时预选默认配装
	controller.invalidate_state()
	hud.hide()                 # 隐藏 Game Boy 外框 + 战斗 HUD
	# 双重防御：Node2D.visible + CanvasLayer.visible + process_mode，
	# 避免 Godot 4.7 在某些情况下 CanvasLayer 不随父级 visible 级联。
	visible = true
	if _ui_layer != null:
		_ui_layer.visible = true
	if _preview_panel != null:
		_preview_panel.visible = false
	if _career_panel != null:
		_career_panel.visible = false
	if _forge_panel != null:
		_forge_panel.visible = false
	process_mode = Node.PROCESS_MODE_INHERIT
	_update_loadout_anvil()
	_fill_sub(selected_char)
	_update_loadout_count()
	_refresh_char_highlight()
	_set_sub_open(true, true)  # 默认展开副屏，小人左移


func hide_screen() -> void:
	controller.in_loadout = false
	controller.invalidate_state()
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
	for path in controller._loadout_system.owned_arr(cat):
		var data: Resource = load(path)
		var card = hud._make_item_card(data, path, cat)
		sub_list.add_child(card["btn"])
		loadout_cards.append(card)
	_sync_card_selection()
	_update_loadout_cards_visual()
	_refresh_slot_strip()
	# 2026-11-08 排版验收：换类目时列表回到顶部，避免沿用上一个类目的滚动位置
	# （技能 10 条滚到底后切到武器，会看到列表停在中间）。
	sub_scroll.scroll_vertical = 0


func _refresh_slot_strip() -> void:
	var category := selected_char
	for c in sub_strip.get_children():
		sub_strip.remove_child(c)
		c.queue_free()
	var used = controller._loadout_system.sel_arr(category).size()
	var unlocked = controller._loadout_system.cat_max(category)
	var ceiling = controller._loadout_system.cat_cap(category)
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
	var wfull = controller.state.selected_loadout.size() >= controller._loadout_system.cat_max("weapon")
	var cfull = controller._loadout_system.sel_arr("active").size() >= controller._loadout_system.cat_max("active")
	var hfull = controller.state.selected_charms.size() >= controller._loadout_system.cat_max("passive")
	var bfull = controller.state.selected_skills.size() >= controller._loadout_system.cat_max("skill")
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
	var grow = "＋" if controller._loadout_system.cat_cap(cat) == controller.state.UNCAPPED else ""
	return "%s %d/%d%s" % [label, controller._loadout_system.sel_arr(cat).size(), controller._loadout_system.cat_max(cat), grow]


func _update_loadout_count() -> void:
	count_label.text = "%s · %s · %s · %s" % [
		_cat_count_text("weapon", "武器"), _cat_count_text("skill", "技能"),
		_cat_count_text("active", "消耗品"), _cat_count_text("passive", "护符")]
	sub_head.text = _cat_count_text(selected_char, TITLES[selected_char])
	_refresh_slot_strip()
	var ok = controller.state.selected_loadout.size() >= controller.state.LOADOUT_MIN
	confirm_btn.disabled = not ok
	confirm_btn.text = ("确认开战 ▶" if ok else "至少选 %d 把武器 ▶" % controller.state.LOADOUT_MIN)
	if _preview_panel != null and _preview_panel.visible:
		_refresh_preview()


# ---------------------------------------------------------------------------
# M1-04 转轮带预览：装备集合 → 真实带子构成（符号/有效元素/实际格数，含聚合/稀有度/
# 共享来源/MISS/金币）+ 已激活共鸣与触发装备。纯计算（ReelPreview），不写入局内状态。
# ---------------------------------------------------------------------------
func _build_preview_ui() -> void:
	if _preview_panel != null:
		return
	_preview_btn = Button.new()
	_preview_btn.text = "🎰带"
	_preview_btn.add_theme_font_size_override("font_size", 9)
	_preview_btn.pressed.connect(_toggle_preview)
	var bar: Node = confirm_btn.get_parent()
	bar.add_child(_preview_btn)
	bar.move_child(_preview_btn, confirm_btn.get_index())

	_preview_panel = PanelContainer.new()
	_preview_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_panel.z_index = 30
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.BG_OVERLAY
	_preview_panel.add_theme_stylebox_override("panel", sb)
	_preview_panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_preview_panel.visible = false)   # 点遮罩任意处可退出（内容超屏时的兜底）
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dlg := PanelContainer.new()
	var sb2 := StyleBoxFlat.new()
	sb2.bg_color = Palette.PANEL_BG
	sb2.border_color = Palette.ACCENT_GOLD
	sb2.set_border_width_all(2)
	dlg.add_theme_stylebox_override("panel", sb2)
	dlg.custom_minimum_size = Vector2(430, 240)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(410, 220)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_preview_box = VBoxContainer.new()
	_preview_box.add_theme_constant_override("separation", 2)
	_preview_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_preview_box)
	dlg.add_child(scroll)
	center.add_child(dlg)
	_preview_panel.add_child(center)
	ui_root.add_child(_preview_panel)
	_preview_panel.visible = false


func _toggle_preview() -> void:
	_preview_panel.visible = not _preview_panel.visible
	if _preview_panel.visible:
		_refresh_preview()


# ---------------------------------------------------------------------------
# M2 棋盘试玩开关：整备底栏小按钮，等价于启动参数 --board（免命令行试玩）。
# 只改 board_config.enabled 的本进程值，不写存档；确认开战后由 full_reset 读取。
# ---------------------------------------------------------------------------
func _build_board_toggle() -> void:
	if _board_btn != null:
		return
	_board_btn = Button.new()
	_board_btn.add_theme_font_size_override("font_size", 9)
	_board_btn.tooltip_text = "切换棋盘模式：开启后确认开战进入 ACT1 棋盘（12 节点 / 1D3）"
	_board_btn.pressed.connect(_toggle_board_mode)
	var bar: Node = confirm_btn.get_parent()
	bar.add_child(_board_btn)
	var idx: int = _preview_btn.get_index() if _preview_btn != null else confirm_btn.get_index()
	bar.move_child(_board_btn, idx)
	_refresh_board_toggle()


func _toggle_board_mode() -> void:
	controller.board_config.enabled = not controller.board_config.enabled
	_refresh_board_toggle()
	hud._log("棋盘模式：%s（确认开战后生效）" % ("开" if controller.board_config.is_active() else "关"))


func _refresh_board_toggle() -> void:
	if _board_btn == null:
		return
	var on: bool = controller.board_config.is_active()
	_board_btn.text = "🗺 棋盘✓" if on else "🗺 棋盘"
	_board_btn.modulate = Color(1, 1, 1, 1.0) if on else Color(1, 1, 1, 0.65)


# ---------------------------------------------------------------------------
# G6-01 生涯成就：底栏入口 + 只读列表（一次性解锁来自 meta，跨局保留）。
# ---------------------------------------------------------------------------
func _build_career_ui() -> void:
	if _career_panel != null:
		return
	_career_btn = Button.new()
	_career_btn.text = "🏅"
	_career_btn.add_theme_font_size_override("font_size", 9)
	_career_btn.tooltip_text = "生涯成就与下一目标（只发一次，跨局保留）"
	_career_btn.pressed.connect(_toggle_career)
	var bar: Node = confirm_btn.get_parent()
	bar.add_child(_career_btn)
	bar.move_child(_career_btn, 0)

	_career_panel = PanelContainer.new()
	_career_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_career_panel.z_index = 30
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.BG_OVERLAY
	_career_panel.add_theme_stylebox_override("panel", sb)
	_career_panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_career_panel.visible = false)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dlg := PanelContainer.new()
	var sb2 := StyleBoxFlat.new()
	sb2.bg_color = Palette.PANEL_BG
	sb2.border_color = Palette.ACCENT_GOLD
	sb2.set_border_width_all(2)
	dlg.add_theme_stylebox_override("panel", sb2)
	dlg.custom_minimum_size = Vector2(430, 250)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(410, 230)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_career_box = VBoxContainer.new()
	_career_box.add_theme_constant_override("separation", 3)
	_career_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_career_box)
	dlg.add_child(scroll)
	center.add_child(dlg)
	_career_panel.add_child(center)
	ui_root.add_child(_career_panel)
	_career_panel.visible = false


func _toggle_career() -> void:
	if _career_panel == null:
		return
	_career_panel.visible = not _career_panel.visible
	if _career_panel.visible:
		_refresh_career()


func _refresh_career() -> void:
	if _career_box == null or controller._career == null:
		return
	for c in _career_box.get_children():
		_career_box.remove_child(c)
		c.queue_free()
	var career = controller._career
	var head := Label.new()
	head.text = "生涯成就 %d/%d · 已击败 BOSS %d" % [
		career.unlocked_count(), career.total_count(), career.boss_count()]
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 11)
	head.add_theme_color_override("font_color", Palette.ACCENT_GOLD)
	_career_box.add_child(head)
	for e in career.entries():
		var row := Label.new()
		var mark: String = "✓" if bool(e.get("unlocked", false)) else "○"
		row.text = "%s %s — %s" % [mark, String(e.get("title", "")), String(e.get("desc", ""))]
		row.add_theme_font_size_override("font_size", 9)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.custom_minimum_size = Vector2(390, 0)
		row.add_theme_color_override("font_color",
			Palette.ACCENT_GOLD if bool(e.get("unlocked", false)) else Color(0.66, 0.66, 0.66))
		_career_box.add_child(row)
	var goal := Label.new()
	var hint: String = career.next_goal_hint()
	goal.text = ("下一目标：" + hint) if hint != "" else "首批成就已全部完成，等下一批。"
	goal.add_theme_font_size_override("font_size", 9)
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal.custom_minimum_size = Vector2(390, 0)
	goal.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_career_box.add_child(goal)
	# 2026-11-08 排版验收：本面板原本只能「点任意处退出」，没有可见关闭入口（与预览/铸式弹层不一致）。
	var close := Button.new()
	close.text = "关闭"
	close.add_theme_font_size_override("font_size", 9)
	close.custom_minimum_size = Vector2(120, 26)
	close.pressed.connect(func() -> void: _career_panel.visible = false)
	_career_box.add_child(close)


# ---------------------------------------------------------------------------
# G6-05 横向铸式：底栏入口 + 4 把代表武器（标准 / 变体二选一）。
# 选择写入 anvil_meta.forge_styles；变体需该武器历史熟练 R2。
# 每行展示优势、代价、属性差异与真实转轮带格数差异（ReelPreview，同 build_strips 口径）。
# ---------------------------------------------------------------------------
func _build_forge_ui() -> void:
	if _forge_panel != null:
		return
	_forge_btn = Button.new()
	_forge_btn.text = "🔨"
	_forge_btn.add_theme_font_size_override("font_size", 9)
	_forge_btn.tooltip_text = "横向铸式：4 把代表武器，有得有失（历史熟练 R2 解锁变体）"
	_forge_btn.pressed.connect(_toggle_forge)
	var bar: Node = confirm_btn.get_parent()
	bar.add_child(_forge_btn)
	bar.move_child(_forge_btn, 1)

	_forge_panel = PanelContainer.new()
	_forge_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_forge_panel.z_index = 31
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.PANEL_BG
	sb.border_color = Palette.ACCENT_GOLD
	sb.set_border_width_all(1)
	_forge_panel.add_theme_stylebox_override("panel", sb)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "🔨 铸式 · 横向变体"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Palette.ACCENT_GOLD)
	head.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var close := Button.new()
	close.text = "✕ 关闭"
	close.add_theme_font_size_override("font_size", 9)
	close.pressed.connect(func() -> void: _forge_panel.visible = false)
	head.add_child(close)
	root.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_forge_box = VBoxContainer.new()
	_forge_box.add_theme_constant_override("separation", 3)
	_forge_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_forge_box)
	root.add_child(scroll)
	margin.add_child(root)
	_forge_panel.add_child(margin)
	ui_root.add_child(_forge_panel)
	_forge_panel.visible = false


func _toggle_forge() -> void:
	if _forge_panel == null:
		return
	_forge_panel.visible = not _forge_panel.visible
	if _forge_panel.visible:
		_refresh_forge()


func _refresh_forge() -> void:
	if _forge_box == null or controller == null or controller._forge_styles == null:
		return
	for c in _forge_box.get_children():
		_forge_box.remove_child(c)
		c.queue_free()
	_forge_box.add_child(_forge_label("变体在整备时选择，最多一个；历史熟练达 R2 解锁。标准形态始终可选，铸式有得有失。", 9, Palette.MUTED))
	var fs = controller._forge_styles
	for path in fs.supported_paths():
		_add_forge_section(fs, String(path))


func _add_forge_section(fs, path: String) -> void:
	var wd: WeaponData = load(path)
	var wname: String = wd.weapon_name if wd != null else path.get_file().get_basename()
	var d: Dictionary = fs.style_def(path)
	if d.is_empty():
		return
	var sid: String = String(fs.selected_id(path))
	var cur := "标准" if sid == "" else String(d["name"])
	var owned: bool = controller.meta.get("owned_weapons", []).has(path)
	var head_txt := "%s · 当前：%s" % [wname, cur]
	if not owned:
		head_txt += "（未拥有）"
	_forge_box.add_child(_forge_label(head_txt, 10, Palette.ACCENT_GOLD, false))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var std_btn := Button.new()
	std_btn.text = "标准形态"
	std_btn.add_theme_font_size_override("font_size", 9)
	std_btn.disabled = (sid == "" or not owned)
	std_btn.pressed.connect(_on_forge_choose.bind(path, ""))
	row.add_child(std_btn)
	var style_btn := Button.new()
	var unlock_suffix := "" if fs.unlocked(path) else "（R2）"
	style_btn.text = String(d["name"]) + unlock_suffix
	style_btn.add_theme_font_size_override("font_size", 9)
	style_btn.disabled = not owned
	style_btn.pressed.connect(_on_forge_choose.bind(path, String(d["id"])))
	row.add_child(style_btn)
	var lock: Label = _forge_label(String(fs.unlock_text(path)) if owned else "未拥有：装备后可选择", 9,
		Palette.MUTED if fs.unlocked(path) else Palette.ENEMY, false)
	row.add_child(lock)
	_forge_box.add_child(row)

	_forge_box.add_child(_forge_label("优势：" + String(d["adv"]), 9, Palette.ACCENT_GOLD))
	_forge_box.add_child(_forge_label("代价：" + String(d["cost"]), 9, Palette.ENEMY))
	_forge_box.add_child(_forge_label(fs.stat_line(path), 9, Color(0.9, 0.9, 0.86)))
	var strip_txt := ""
	if not controller.selected_loadout.has(path):
		strip_txt = "带子：装备该武器后显示真实格数差异"
	else:
		var diff: Array = fs.strip_diff(path)
		strip_txt = "带子：格数无变化（变化已计入命中与权重）" if diff.is_empty() else "带子：" + "；".join(diff)
	_forge_box.add_child(_forge_label(strip_txt, 9, Palette.MUTED_DIM))
	var sep := HSeparator.new()
	_forge_box.add_child(sep)


func _on_forge_choose(path: String, id: String) -> void:
	if controller == null or controller._forge_styles == null:
		return
	var fs = controller._forge_styles
	if id != "" and not fs.unlocked(path):
		hud._log("🔨 %s：%s" % [String(fs.style_def(path).get("name", "")), fs.unlock_text(path)])
		_refresh_forge()
		return
	if not fs.set_style(path, id):
		return
	var wd: WeaponData = load(path)
	var wname: String = wd.weapon_name if wd != null else path.get_file().get_basename()
	var label := "标准形态" if id == "" else String(fs.style_def(path).get("name", ""))
	hud._log("🔨 铸式：%s → %s" % [wname, label])
	_fill_sub(selected_char)
	_refresh_forge()
	if _preview_panel != null and _preview_panel.visible:
		_refresh_preview()


func _forge_label(text: String, size: int, color: Color, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(418, 0)
	return l


func _refresh_preview() -> void:
	for c in _preview_box.get_children():
		_preview_box.remove_child(c)
		c.queue_free()
	var comp: Dictionary = ReelPreview.compose(
		controller.selected_loadout, controller.selected_skills, controller.selected_charms,
		[], controller._reward_system.run_symbol_bonus, controller.deprived_level, false, 0, controller.mastery.tune_map(),
		controller._forge_styles.preview_map() if controller._forge_styles != null else {})
	var head = hud._label("🎰 转轮带预览", TypeScale.MEDIUM)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_box.add_child(head)
	var sum = hud._label(ReelPreview.summary_line(comp), TypeScale.TINY)
	sum.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sum.add_theme_color_override("font_color", Palette.MUTED)
	_preview_box.add_child(sum)
	for r in comp["rows"]:
		var line := "%s · %s · 权重%.0f → %d格 · 来源:%s" % [
			String(r["name"]), ElementCounter.label(String(r["elem"])),
			float(r["weight"]), int(r["cells"]), "、".join(r["items"])]
		var l = hud._label(line, TypeScale.TINY)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(320, 0)
		_preview_box.add_child(l)
	for s in comp["synergies"]:
		var sd: SynergyData = s["def"]
		var names := []
		for p in s["paths"]:
			var d = load(String(p))
			names.append(controller._shop_name(String(p), "weapon" if d is WeaponData else "passive"))
		var sl = hud._label("共鸣 %s（%s）：%s" % [sd.name, "、".join(names), sd.desc], TypeScale.TINY)
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sl.custom_minimum_size = Vector2(320, 0)
		sl.add_theme_color_override("font_color", Palette.ACCENT_GOLD)
		_preview_box.add_child(sl)
	var hint = hud._label("权重是格数档位依据（≥2→3 格、≥4→4 格；共享来源可突破稀有封顶）；落点由按停时机决定", TypeScale.TINY)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(320, 0)
	hint.add_theme_color_override("font_color", Palette.MUTED_DIM)
	_preview_box.add_child(hint)
	var close := Button.new()
	close.text = "关闭"
	# 2026-11-08 排版验收：早先漏设字号，按默认 16px 渲染，在 480x270 下明显大于全屏其它文字。
	close.add_theme_font_size_override("font_size", 9)
	close.custom_minimum_size = Vector2(120, 26)
	close.pressed.connect(func(): _preview_panel.visible = false)
	_preview_box.add_child(close)


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


# ---------------------------------------------------------------------------
# T29 整备软默认预选（基础版，2026-08-24 拍板：立即执行；同日修正——只从 owned 预选）
# 仅当「四类全空」时生效（首次开整备 / 战败回来）——玩家动过任何一类即视为有意图，不再自动补。
# ⚠ 必须从 owned_arr 预选：整备副屏卡片只构建 owned 项（§12.3 铁律「整备选装唯一约束点 = owned_*」），
#   从全池预选会产出「隐形选中」——占槽却无卡片可看可改（用户实测：护符 1/1 但列表无选中项且无法更改）。
# 预选策略：武器火+光（双克制轴）→ 技能治疗 → 消耗品治疗药剂 → 护符守备（防御向兜底）；
#   偏好未命中 owned 时回落「owned 首件」。T4 完成后只需调整偏好表（数据），逻辑零改动。
# ---------------------------------------------------------------------------
func apply_soft_default() -> void:
	var c = controller   # loadout_scene.controller 为无类型引用，动态访问
	if c.selected_loadout.size() > 0 or c.selected_skills.size() > 0 \
			or c.selected_charms.size() > 0 or c.selected_consumables.size() > 0:
		return
	var guard := 0
	while c.selected_loadout.size() < c.LOADOUT_MIN and guard < 8:
		guard += 1
		var p := _pref_pick(c._loadout_system.owned_arr("weapon"), ["fire_sword", "holy_sword"])
		if p == "" or c.selected_loadout.has(p):
			p = _first_owned_not_in(c._loadout_system.owned_arr("weapon"), c.selected_loadout)
		if p == "":
			break
		c.selected_loadout.append(p)
	if c.selected_skills.is_empty():
		var s := _pref_pick(c._loadout_system.owned_arr("skill"), ["recovery"])
		if s != "":
			c.selected_skills.append(s)
	if c.selected_charms.is_empty():
		var ch := _pref_pick(c._loadout_system.owned_arr("passive"), ["guard_charm", "sharp_charm"])
		if ch != "":
			c.selected_charms.append(ch)
	if c.selected_consumables.is_empty():
		var cs := _pref_pick(c._loadout_system.owned_arr("active"), ["heal_potion"])
		if cs != "":
			c.selected_consumables.append(cs)
	if c.selected_loadout.size() >= c.LOADOUT_MIN:
		c.hud._log("已为你预选默认配装（可自由调整后再开战）")


func _first_owned_not_in(pool: Array, exclude: Array) -> String:
	for p in pool:
		if not exclude.has(p):
			return p
	return ""


func _pref_pick(pool: Array, wants: Array) -> String:
	for w in wants:
		for p in pool:
			if p.ends_with(w + ".tres"):
				return p
	return "" if pool.is_empty() else pool[0]
