extends Control

# ============================================================================
# BoardScreen — 14×9 地图主视图（Step 6 收口）
# 规格：docs/地图巡逻诱导_第一版预算与分步执行计划_2026-11-14.md §4.1–4.3
#
# 独立满屏视图：显示时 hud.hide()，进入战斗 / 商店时切回战斗 HUD。
# 由 BattleHud._build_board_screen 挂到 Duel 根（与整备场景同级），不挤进战斗中央区域。
#
# 布局：480×270，按设计稿（1080×608 等比稿）落地——顶栏 + 左侧地图面板（14×9 整图，
# 16.6px 格，单字表达）+ 右侧「当前局面」+ 底部说明条。移动靠点击相邻格，等待推进一回合。
# ============================================================================

const UI_BUTTON = preload("res://scenes/ui/ui_button.tscn")
const NODE = preload("res://scripts/board/board_node_data.gd")
const MAP_TYPES = preload("res://scripts/board/map_node_types.gd")

# 设计稿口径：16.6px 格里用统一单字表达概念（普/精/王/宝/图/商/休/事/门），
# 不再叠加 16px 图标——同一概念只有一种表现，也不依赖点阵字体缺字形的 emoji。
const PIECE_ICON = preload("res://assets/icons/16/board_piece.png")

# 480×270，按设计稿（1080×608 等比 2.25 倍）落地：14×9 整图入屏。
# 顶栏（游戏名 + 预算）/ 地图面板（标题·副标题·区域标注·格阵·图例）/ 右侧「当前局面」/ 底部说明。
const VIEW := Vector2(480.0, 270.0)
const TOP_RECT := Rect2(4.0, 3.0, 472.0, 20.0)
const MAP_PANEL := Rect2(4.0, 26.0, 320.0, 196.0)
# 14×9 格阵：14×16.6=232.4，9×16.6=149.4，在面板内水平居中。
const MAP_RECT := Rect2(47.8, 64.0, 232.4, 149.4)
const INFO_RECT := Rect2(329.0, 26.0, 147.0, 224.0)
const FOOT_RECT := Rect2(13.0, 251.0, 454.0, 17.0)
const COLS := 14
const ROWS := 9
const CELL := 16.6
const CELL_GAP := 1.0
const NODE_H := CELL - CELL_GAP
const STEP_SEC := 0.12
# 地图面板内的固定文字基线
const AREA_LABEL_Y := 61.0
const LEGEND_Y := 219.0
# 等待按钮（右栏底部，金色大按钮）
const WAIT_BTN_RECT := Rect2(334.0, 216.0, 137.0, 22.0)

# 单字标签：16.6px 格只放得下一个汉字（点阵字体缺字形会显示成方框）。
# 用词与设计稿一致：普 / 精 / 王 / 宝 / 图 / 商 / 休 / 事 / 门。
const SHORT := {
	"start": "起", "path": "", "battle": "普", "elite": "精", "boss": "王",
	"chest": "宝", "armory": "图", "shop": "商", "rest": "休", "event": "事",
}

# 道路 / 节点状态色（与样稿一致；语义仍由 Palette 决定）
const ROAD_DONE := Color("#4b3b33")
const ROAD_UNDONE := Color("#3a2b31")
const NODE_BG := Color("#1d1219")
const NODE_BG_DONE := Color("#120b11")
const PATH_BG := Color("#150d12")
const TRAP_COL := Color("#c8553d")
const CARD_CYAN := Color("#3fb0a8")
const CARD_GREEN := Color("#5f9e52")
const PANEL_FILL := Color("#181016")
const PANEL_LINE := Color("#4a3a2e")
const PATROL_COL := Color("#e35b50")

var controller
var hud                       # BattleHud（不标类型：避免与 battle_hud.gd 的 preload 形成循环依赖）
var board = null

var _built := false
var _moving := false
var _stepping := false      # 自动走一格的 0.12s 等待期内防连点
var _selected_id := ""
var _buttons := {}          # id -> Button（透明热区）
var _button_sig := ""       # 当前按钮集合对应的节点 id 串（换骨架时重建）
var _pos := {}              # id -> Vector2（由 BoardSystem.layout 计算）
var _node_w := 34.0         # 当前骨架的节点宽（标准 34 / 长尾 30）
var _art: Control = null     # 绘制层：地图面板内的格阵 / 区域标注 / 图例
var _bg: ColorRect = null
var _act_theme: Dictionary = Palette.ACT_THEME[1]   # G7-A S3：按幕换配色
var _piece: TextureRect = null      # 玩家标记
var _act_label: Label = null        # 顶栏右侧：ACT + 回合
var _budget_label: Label = null     # 顶栏副标题：本图预算
var _map_hint_text := ""            # 地图面板副标题：操作说明 / 选中格真实结果
var _info_stats: Label = null       # 右栏：HP / 金币 / 探索
var _card_desc_1: Label = null      # 巡逻怪预告（动态）
var _card_desc_2: Label = null      # ① 选择等待
var _card_desc_3: Label = null      # ② 怪物踩陷阱（动态）
var _card_desc_4: Label = null      # ③ 转轮战斗（动态护甲）
var _wait_btn: Button = null        # 等待一回合（推进地图回合）
var _trim_btn: Button = null        # 精简入口（G7-B B3，行内隐藏）
var _foot: Label = null             # 底部说明条

# 战斗确认层：落到战斗节点后不立刻开打，先展示敌人与属性，由玩家点「进入战斗」。
var _confirm_layer: Control = null
var _confirm_title: Label = null
var _confirm_enemy: Label = null
var _confirm_stats: Label = null
var _confirm_btn: Button = null
var _confirm_alt_btn: Button = null
var _pending_node: Dictionary = {}

# 查看构筑（只读）/ 撤回整备（二次确认）：不读 RNG、不改任何状态。
var _build_btn: Button = null
var _retreat_btn: Button = null
var _build_layer: Control = null
var _build_text: Label = null
var _retreat_layer: Control = null
var _retreat_text: Label = null
var _retreat_next_btn: Button = null
var _retreat_stage := 0   # 0 关闭 / 1 第一次确认 / 2 第二次确认


func configure(ctrl, h) -> void:
	controller = ctrl
	hud = h
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	visible = false


func _build_ui() -> void:
	if _built:
		return
	_built = true
	var bg := ColorRect.new()
	bg.color = Palette.BG_MAIN
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_bg = bg

	# 顶栏：游戏名 + ACT/回合 + 本图预算（设计稿顶部条）。
	var top := _label("SEEK DEAD · 灰沼回廊", 12, Palette.ACCENT_GOLD)
	top.position = Vector2(6, 2)
	top.size = Vector2(300, 15)
	add_child(top)
	_act_label = _label("ACT I · 回合 0", 10, Palette.TITLE)
	_act_label.position = Vector2(300, 4)
	_act_label.size = Vector2(174, 13)
	_act_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_act_label)
	_budget_label = _label("14×9 · 61 可走格 · 16 战 · 4 宝箱 · 3 陷阱",
		8, Palette.MUTED_DIM)
	_budget_label.position = Vector2(6, 15)
	_budget_label.size = Vector2(470, 10)
	_budget_label.clip_text = true
	add_child(_budget_label)

	# 地图面板：底 + 标题 + 副标题；格阵 / 区域标注 / 图例由 _draw_art 负责。
	_panel(MAP_PANEL.position, MAP_PANEL.size, false)

	# 绘制层全屏：地图面板内的格阵 / 区域标注 / 图例都在这一层画。
	_art = Control.new()
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	_art.draw.connect(_draw_art)

	# 右侧「当前局面」：局面摘要 + 巡逻预告 + 三条链路 + 等待按钮 + 系统入口。
	var info := _panel(INFO_RECT.position, INFO_RECT.size, true)
	var iv: VBoxContainer = info.get_node("Margin/VBox")
	iv.add_theme_constant_override("separation", 2)
	var head := _label("当前局面", 12, Palette.ACCENT_GOLD)
	iv.add_child(head)
	_info_stats = _label("", 9, Palette.PLAYER)
	_info_stats.clip_text = true
	_info_stats.custom_minimum_size = Vector2(0, 14)
	iv.add_child(_info_stats)

	_card_desc_1 = _card(iv, "巡逻怪", "预告：—", Palette.ENEMY, 2)
	_card_desc_2 = _card(iv, "① 选择等待", "原地不动，地图推进一回合", CARD_CYAN, 1)
	_card_desc_3 = _card(iv, "② 怪物踩陷阱", "触发公开破甲陷阱", Palette.ACCENT_GOLD, 1)
	_card_desc_4 = _card(iv, "③ 转轮战斗", "敌方护甲降低，仍靠 Build 击败", CARD_GREEN, 1)

	_wait_btn = UI_BUTTON.instantiate()
	_wait_btn.custom_minimum_size = Vector2(0, 20)
	_wait_btn.size = Vector2(137, 20)
	_wait_btn.add_theme_font_size_override("font_size", 10)
	_wait_btn.text = "等待一回合"
	_wait_btn.pressed.connect(_on_wait)
	iv.add_child(_wait_btn)

	var sys_row := HBoxContainer.new()
	sys_row.add_theme_constant_override("separation", 4)
	iv.add_child(sys_row)
	_build_btn = UI_BUTTON.instantiate()
	_build_btn.custom_minimum_size = Vector2(66, 14)
	_build_btn.size = Vector2(66, 14)
	_build_btn.add_theme_font_size_override("font_size", 8)
	_build_btn.text = "查看构筑"
	_build_btn.pressed.connect(_on_build_pressed)
	sys_row.add_child(_build_btn)
	_retreat_btn = UI_BUTTON.instantiate()
	_retreat_btn.custom_minimum_size = Vector2(66, 14)
	_retreat_btn.size = Vector2(66, 14)
	_retreat_btn.add_theme_font_size_override("font_size", 8)
	_retreat_btn.text = "撤回整备"
	_retreat_btn.pressed.connect(_on_retreat_pressed)
	sys_row.add_child(_retreat_btn)

	# 玩家标记叠在地图之上。
	_piece = TextureRect.new()
	_piece.texture = PIECE_ICON
	_piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_piece.stretch_mode = TextureRect.STRETCH_SCALE
	_piece.size = Vector2(8, 8)
	_piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_piece)

	_build_confirm_layer()
	_build_view_layer()
	_build_retreat_layer()


# 右栏卡片：标题 + 说明（说明返回给调用方，便于按真实状态改写）。
func _card(parent: VBoxContainer, title: String, desc: String, border: Color,
		desc_lines: int) -> Label:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(border.r, border.g, border.b, 0.10)
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	var t := _label(title, 9, border)
	v.add_child(t)
	var d := _label(desc, 8, Palette.PLAYER)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.clip_text = true
	d.max_lines_visible = desc_lines
	d.custom_minimum_size = Vector2(0.0, 12.0 * float(desc_lines))
	v.add_child(d)
	parent.add_child(p)
	return d


func _build_confirm_layer() -> void:
	_confirm_layer = Control.new()
	_confirm_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.visible = false
	add_child(_confirm_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.add_child(dim)

	var panel := PanelContainer.new()
	panel.position = Vector2(90, 52)
	panel.size = Vector2(300, 156)
	panel.custom_minimum_size = Vector2(300, 156)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.PANEL_BG
	sb.border_color = Palette.ACCENT_GOLD
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	_confirm_layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	margin.add_child(vb)
	_confirm_title = _label("战斗确认", 10, Palette.ACCENT_GOLD)
	vb.add_child(_confirm_title)
	_confirm_enemy = _label("", 11, Palette.TITLE)
	vb.add_child(_confirm_enemy)
	_confirm_stats = _label("", 9, Palette.MUTED)
	_confirm_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_confirm_stats)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	vb.add_child(row)
	# 网格 BOSS/精英的「继续探索 / 返回探索」；普通怪与旧棋盘保持单按钮。
	_confirm_alt_btn = UI_BUTTON.instantiate()
	_confirm_alt_btn.custom_minimum_size = Vector2(120, 30)
	_confirm_alt_btn.size = Vector2(120, 30)
	_confirm_alt_btn.text = "继续探索"
	_confirm_alt_btn.visible = false
	_confirm_alt_btn.pressed.connect(_on_confirm_alt)
	row.add_child(_confirm_alt_btn)
	_confirm_btn = UI_BUTTON.instantiate()
	_confirm_btn.custom_minimum_size = Vector2(120, 30)
	_confirm_btn.size = Vector2(120, 30)
	_confirm_btn.text = "进入战斗"
	_confirm_btn.pressed.connect(_on_confirm_battle)
	row.add_child(_confirm_btn)


# 查看构筑（只读滚屏）：不读 RNG、不改任何状态。
func _build_view_layer() -> void:
	_build_layer = Control.new()
	_build_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layer.visible = false
	add_child(_build_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layer.add_child(dim)

	var panel := PanelContainer.new()
	panel.position = Vector2(30, 16)
	panel.size = Vector2(420, 238)
	panel.custom_minimum_size = Vector2(420, 238)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.PANEL_BG
	sb.border_color = Palette.PLAYER
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	_build_layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	margin.add_child(vb)
	var title := _label("当前构筑（只读）", 10, Palette.PLAYER)
	vb.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)
	_build_text = _label("", 8, Palette.TITLE)
	_build_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_build_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_build_text)
	var close := UI_BUTTON.instantiate()
	close.custom_minimum_size = Vector2(120, 24)
	close.size = Vector2(120, 24)
	close.text = "返回棋盘"
	close.pressed.connect(_on_build_closed)
	var crow := HBoxContainer.new()
	crow.alignment = BoxContainer.ALIGNMENT_CENTER
	crow.add_child(close)
	vb.add_child(crow)


# 撤回整备弹层：两次确认；取消不改变任何状态。
func _build_retreat_layer() -> void:
	_retreat_layer = Control.new()
	_retreat_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_retreat_layer.visible = false
	add_child(_retreat_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_retreat_layer.add_child(dim)

	var panel := PanelContainer.new()
	panel.position = Vector2(80, 66)
	panel.size = Vector2(320, 138)
	panel.custom_minimum_size = Vector2(320, 138)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.PANEL_BG
	sb.border_color = Palette.ENEMY
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	_retreat_layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	margin.add_child(vb)
	vb.add_child(_label("撤回整备", 10, Palette.ENEMY))
	_retreat_text = _label("", 8, Palette.TITLE)
	_retreat_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_retreat_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_retreat_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	var cancel := UI_BUTTON.instantiate()
	cancel.custom_minimum_size = Vector2(120, 26)
	cancel.size = Vector2(120, 26)
	cancel.text = "取消"
	cancel.pressed.connect(_on_retreat_cancel)
	row.add_child(cancel)
	_retreat_next_btn = UI_BUTTON.instantiate()
	_retreat_next_btn.custom_minimum_size = Vector2(120, 26)
	_retreat_next_btn.size = Vector2(120, 26)
	_retreat_next_btn.text = "继续撤回"
	_retreat_next_btn.pressed.connect(_on_retreat_confirm)
	row.add_child(_retreat_next_btn)


# 按当前棋盘重建透明热区按钮：节点集合 / 列宽随骨架变化（标准 25 / 长尾 29）。
# 按钮插在确认层之前，保证战斗确认遮罩始终盖住节点。
func _ensure_buttons() -> void:
	if board == null or _confirm_layer == null:
		return
	var ids: Array[String] = []
	for n in board.nodes:
		ids.append(String(n["id"]))
	var sig := ",".join(ids)
	if sig == _button_sig:
		_layout_buttons()
		return
	_button_sig = sig
	for id in _buttons:
		(_buttons[id] as Node).queue_free()
	_buttons.clear()
	for id in ids:
		var b: Button = UI_BUTTON.instantiate()
		b.text = ""
		b.custom_minimum_size = Vector2(_node_w, NODE_H)
		b.size = Vector2(_node_w, NODE_H)
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		# 透明热区：节点外观由 _draw_art 负责，按钮只保留点击 / 悬停。
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			b.add_theme_stylebox_override(st, empty)
		b.pressed.connect(_on_node_pressed.bind(id))
		b.mouse_entered.connect(_on_node_hover.bind(id))
		add_child(b)
		move_child(b, _confirm_layer.get_index())
		_buttons[id] = b
	_layout_buttons()


# 14×9 布局：按 row/col 定位，镜头 9×7 跟随角色（§4.1，不整图入屏）。
func _apply_layout() -> void:
	if board == null:
		return
	_node_w = CELL - CELL_GAP
	var pad := Vector2(CELL_GAP * 0.5, CELL_GAP * 0.5)
	_pos.clear()
	for n in board.nodes:
		var col: int = int(n.get("col", -1))
		var row: int = int(n.get("row", -1))
		if col < 0 or col >= COLS or row < 0 or row >= ROWS:
			continue
		_pos[String(n["id"])] = MAP_RECT.position + Vector2(float(col) * CELL, float(row) * CELL) + pad


func _layout_buttons() -> void:
	for id in _buttons:
		var b: Button = _buttons[id]
		var inside := _pos.has(String(id))
		b.visible = inside
		if not inside:
			continue
		b.position = _node_pos(String(id))
		b.custom_minimum_size = Vector2(_node_w, NODE_H)
		b.size = Vector2(_node_w, NODE_H)


# 面板：统一内边距，文字不贴边。with_vbox = false 时只作底与边框（地图面板用）。
func _panel(pos: Vector2, sz: Vector2, with_vbox := true) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = pos
	p.size = sz
	p.custom_minimum_size = sz
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_FILL
	sb.border_color = PANEL_LINE
	sb.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", sb)
	var m := MarginContainer.new()
	m.name = "Margin"
	m.add_theme_constant_override("margin_left", 5)
	m.add_theme_constant_override("margin_right", 5)
	m.add_theme_constant_override("margin_top", 4)
	m.add_theme_constant_override("margin_bottom", 4)
	p.add_child(m)
	if not with_vbox:
		add_child(p)
		return p
	var vb := VBoxContainer.new()
	vb.name = "VBox"
	vb.add_theme_constant_override("separation", 2)
	m.add_child(vb)
	add_child(p)
	return p


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ---------------------------------------------------------------------------
# 显示 / 刷新
# ---------------------------------------------------------------------------

func show_board(board_sys) -> void:
	board = board_sys
	_pending_node = {}
	if _confirm_layer != null:
		_confirm_layer.visible = false
	_selected_id = String(board.current_id)
	_apply_layout()
	_ensure_buttons()
	visible = true
	if hud != null:
		hud.hide()
	if controller._journal != null:
		controller._journal.note_board_shown()   # G5 工具：10 秒找落点计时起点（每局一次）
	refresh()


func hide_board(show_hud: bool = false) -> void:
	visible = false
	if show_hud and hud != null:
		hud.show()
		hud._refresh_meta()


# G7-A S3：按当前幕取配色；只改颜色与标题，不新增美术资源。
func _apply_act_theme() -> void:
	_act_theme = Palette.act_theme(int(board.act))
	if _act_label != null:
		var turn := 0
		if board.runtime != null:
			turn = int(board.runtime.turn)
		_act_label.text = "%s · 回合 %d" % [String(_act_theme.get("name", "ACT I")), turn]
	if _bg != null:
		_bg.color = _act_theme.get("bg", Palette.BG_MAIN)


func refresh() -> void:
	if board == null:
		return
	_apply_act_theme()
	queue_redraw()
	if board.feedback != "":
		_selected_id = String(board.current_id)
	# 镜头跟随角色：位置每帧按当前格重算，出镜头的格子不建热区。
	_apply_layout()
	_layout_buttons()
	for id in _buttons:
		var b: Button = _buttons[id]
		b.tooltip_text = _tooltip(board.node_by_id(String(id)))
	if _art != null:
		_art.queue_redraw()
	_piece.position = _piece_pos(String(board.current_id))
	_piece.visible = true
	# 操作栏只保留当前可用操作：移动靠点击相邻格，等待是唯一推进回合的按钮。
	var busy: bool = _moving or _stepping or not _pending_node.is_empty()
	_wait_btn.disabled = busy
	if not _pending_node.is_empty():
		_wait_btn.text = "待确认"
	elif _moving:
		_wait_btn.text = "移动中"
	else:
		_wait_btn.text = "等待一回合"
	_build_btn.disabled = busy
	_retreat_btn.disabled = busy
	_info_stats.text = "HP %d/%d · 金币 %d · 探索 %d/%d" % [
		controller.player_hp, controller.player_hp_max, controller.gold,
		board.visited_count(), board.node_count()]
	_refresh_trim_btn()
	_refresh_info()
	_refresh_patrol_info()


# G7-B B3：精简入口状态（ready 可点 / used 本幕已用 / none 隐藏）。
func _refresh_trim_btn() -> void:
	if _trim_btn == null:
		return
	var st := "none"
	if controller != null and controller._trim != null:
		st = controller._trim.entry_state()
	_trim_btn.visible = st != "none"
	_trim_btn.disabled = st != "ready" or _moving or _stepping or not _pending_node.is_empty()
	_trim_btn.text = "精简" if st == "ready" else "精简(已用)"


func _on_trim_pressed() -> void:
	if hud != null:
		hud.show_trim_dialog()


# ---------------------------------------------------------------------------
# 查看构筑（只读）/ 撤回整备（二次确认）
# ---------------------------------------------------------------------------

func _on_build_pressed() -> void:
	if board == null or _moving or _stepping:
		return
	_build_text.text = _build_view_text()
	_build_layer.visible = true


func _on_build_closed() -> void:
	_build_layer.visible = false


# 只读构筑摘要：武器 / 技能 / 护符 / 消耗品 / 成长 / 符号权重。
# 不调用 build_strips（它会用 randi 洗牌），因此查看不消耗 RNG、不改任何状态。
func _build_view_text() -> String:
	var lines: Array[String] = []
	lines.append("武器：%s" % _names_of(controller.selected_loadout, "weapon"))
	lines.append("技能：%s" % _names_of(controller.selected_skills, "skill"))
	lines.append("护符：%s" % _names_of(controller.selected_charms, "passive"))
	var cons: Array[String] = []
	for slot in controller.consumable_slots:
		var path := String(slot.get("path", ""))
		cons.append("%s×%d" % [controller._shop_name(path, "consumable"), int(slot.get("charges", 0))])
	lines.append("消耗品：%s" % ("、".join(cons) if not cons.is_empty() else "无"))
	var growth := "成长：%s" % controller.growth.progress_short()
	if controller.growth.perk_ids.size() > 0:
		growth += " · 技艺 %d" % controller.growth.perk_ids.size()
	var imp: int = controller.mastery.imprint_total()
	if imp > 0:
		growth += " · 铭印 %d" % imp
	lines.append(growth)
	lines.append("生命 %d/%d · 金币 %d · 已击败 %d" % [
		controller.player_hp, controller.player_hp_max, controller.gold,
		board.defeated.size()])
	lines.append("")
	lines.append("转轮符号（按权重合计）")
	lines.append(_symbol_summary())
	lines.append("")
	lines.append("查看构筑不会领取奖励、不消耗 RNG；换装只能在营地 / 商店节点。")
	return "\n".join(lines)


func _names_of(paths: Array, kind: String) -> String:
	var out: Array[String] = []
	for p in paths:
		out.append(controller._shop_name(String(p), kind))
	return " / ".join(out) if not out.is_empty() else "无"


func _symbol_summary() -> String:
	var tally := {}
	for it in controller.pool_items:
		for s in it.get("syms", []):
			var sym = s[0]
			if sym == null:
				continue
			var key := String(sym.label)
			if key == "":
				key = String(sym.name)
			var e := String(s[2]) if (s as Array).size() > 2 else "none"
			if e != "none":
				key += "·" + ElementCounter.label(e)
			tally[key] = float(tally.get(key, 0.0)) + float(s[1])
	var keys: Array = tally.keys()
	keys.sort()
	var parts: Array[String] = []
	for k in keys:
		parts.append("%s×%d" % [String(k), int(round(float(tally[k])))])
	return "、".join(parts) if not parts.is_empty() else "无"


func _on_retreat_pressed() -> void:
	if board == null or _moving or _stepping:
		return
	_retreat_stage = 1
	_retreat_text.text = "撤回整备？\n本局临时成长、地图进度与未结算奖励将失去。\n图鉴 / 收藏 / 解锁与局外点数保留。"
	_retreat_next_btn.text = "继续撤回"
	_retreat_layer.visible = true


# 第一次点「继续撤回」进入第二次确认；第二次才真正结束远征。
func _on_retreat_confirm() -> void:
	if _retreat_stage == 1:
		_retreat_stage = 2
		_retreat_text.text = "再次确认：结束本次远征并回到整备页。\n不会获得区域 BOSS 或通关奖励。"
		_retreat_next_btn.text = "确认撤回"
		return
	if _retreat_stage == 2:
		_retreat_stage = 0
		_retreat_layer.visible = false
		controller.room_flow.retreat_run()


func _on_retreat_cancel() -> void:
	_retreat_stage = 0
	_retreat_layer.visible = false


# 信息栏标题：点阵字体缺 emoji 字形，这里只用文字，不再拼图标。
# 目标名称：节点自带标题优先（房间名 / BOSS 名），否则用类型标签。
func _node_heading(n: Dictionary) -> String:
	if n.is_empty():
		return ""
	var t := String(n.get("title", ""))
	if t != "":
		return t
	return MAP_TYPES.label_of(String(n.get("type", "")))


func _node_pos(id: String) -> Vector2:
	return _pos.get(id, Vector2.ZERO)


func _node_center(id: String) -> Vector2:
	return _node_pos(id) + Vector2(_node_w * 0.5, NODE_H * 0.5)


# 棋子放在格子左上角：16.6px 格里要留出中央的单字。
func _piece_pos(id: String) -> Vector2:
	return _node_pos(id) + Vector2(1.0, 1.0)


# ---------------------------------------------------------------------------
# G3-01 地图绘制：直角道路 / 节点状态框 / 几何图标 / 区域标注
# 只读 BoardSystem 的查询结果，不改任何规则；refresh() 时整层重画。
# ---------------------------------------------------------------------------

func _draw_art() -> void:
	if board == null:
		return
	var font := get_theme_default_font()
	var map_bg: Color = _act_theme.get("map", Color("#1a1016"))
	_art.draw_rect(MAP_RECT, map_bg)
	# 相邻：右 / 下各画一次；两端都已探索的画暗色。
	for n in board.nodes:
		var a := String(n["id"])
		if not _pos.has(a):
			continue
		for nx in n.get("next", []):
			var b := String(nx)
			if a >= b or not _pos.has(b):
				continue
			var road: Color = ROAD_DONE if (board.is_consumed(a) and board.is_consumed(b)) else ROAD_UNDONE
			_art.draw_line(_node_center(a), _node_center(b), road, 1)
	for n in board.nodes:
		var id := String(n["id"])
		if _pos.has(id):
			_draw_grid_node(id, _node_pos(id), font)
	_draw_trap_marks()
	_draw_patrols(font)
	_art_text(font, Vector2(MAP_PANEL.position.x + 7, 39.0), "三区巡逻地图", 12, Palette.TITLE)
	_art_text(font, Vector2(MAP_PANEL.position.x + 7, 51.0), _map_hint_text, 10, Palette.MUTED)
	_draw_area_labels(font)
	_draw_legend(font)
	# 底部说明条（设计稿底栏）：一局的分工，不做操作入口。用绘制避免 Label 行高撑破视口。
	_art.draw_string(font, Vector2(FOOT_RECT.position.x, FOOT_RECT.position.y + 9.0),
		"地图负责诱导 · 转轮负责战斗与成长 · BOSS 主动挑战",
		HORIZONTAL_ALIGNMENT_CENTER, FOOT_RECT.size.x, 8, Palette.MUTED_DIM)


# 三区标注（设计稿 A · 入口区 / B · 交汇区 / C · 深层区），按真实分区列居中。
func _draw_area_labels(font: Font) -> void:
	var spans := {"A": [99, -1], "B": [99, -1], "C": [99, -1]}
	for n in board.nodes:
		var r := String(n.get("region", ""))
		if not spans.has(r):
			continue
		var col := int(n.get("col", 0))
		spans[r][0] = mini(int(spans[r][0]), col)
		spans[r][1] = maxi(int(spans[r][1]), col)
	var names := {"A": "A · 入口区", "B": "B · 交汇区", "C": "C · 深层区"}
	for key in ["A", "B", "C"]:
		var lo: int = int(spans[key][0])
		var hi: int = int(spans[key][1])
		if hi < lo:
			continue
		var cx: float = MAP_RECT.position.x + (float(lo) + float(hi) + 1.0) * CELL * 0.5
		var text := String(names[key])
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		_art_text(font, Vector2(cx - w * 0.5, AREA_LABEL_Y), text, 10, Palette.MUTED)


# 图例条：格内单字的含义，常驻在面板底部。
func _draw_legend(font: Font) -> void:
	var text := "普战 · 精战 · 宝箱 · 图藏库 · 商店 · 休整 · 事件 · 王BOSS · X陷阱 · 门通道"
	_art_text(font, Vector2(MAP_PANEL.position.x + 8, LEGEND_Y), text, 8, Palette.MUTED_DIM)


func _is_legal(id: String) -> bool:
	for t in board.legal_targets():
		if String(t["id"]) == id:
			return true
	return false


func _id_at_cell(cell: int) -> String:
	for n in board.nodes:
		if int(n.get("cell_id", -1)) == cell:
			return String(n["id"])
	return ""


# 陷阱标记：统一几何 X（陷阱无独立美术资源），未破甲红、已消耗暗。
func _draw_trap_marks() -> void:
	var rt = board.runtime
	if rt == null:
		return
	for n in board.nodes:
		var id := String(n["id"])
		if not _pos.has(id):
			continue
		var cell: int = int(n.get("cell_id", -1))
		if not rt.is_trap_cell(cell):
			continue
		var used: bool = not (rt.trap_state.get(cell, {}) as Dictionary).is_empty()
		var col: Color = Palette.MUTED_DIM if used else TRAP_COL
		var box := Rect2(_node_pos(id), Vector2(_node_w, NODE_H))
		var pad := 3.0
		_art.draw_line(box.position + Vector2(pad, pad),
			box.position + Vector2(_node_w - pad, NODE_H - pad), col, 1.5)
		_art.draw_line(box.position + Vector2(_node_w - pad, pad),
			box.position + Vector2(pad, NODE_H - pad), col, 1.5)


# 巡逻怪：红框 + 从当前格指向下一格的箭头；右侧「当前局面」同时给出方向文字。
func _draw_patrols(_font: Font) -> void:
	var rt = board.runtime
	if rt == null:
		return
	for p in rt.patrol_preview():
		var id := _id_at_cell(int(p["cell"]))
		if id == "" or not _pos.has(id):
			continue
		var pos := _node_pos(id)
		var box := Rect2(pos, Vector2(_node_w, NODE_H))
		_art.draw_rect(box, Color(0.89, 0.36, 0.31, 0.22))
		_art.draw_rect(box, PATROL_COL, false, 1.5)
		var nid := _id_at_cell(int(p["next"]))
		if nid != "" and _pos.has(nid):
			_draw_arrow(_node_center(id), _node_center(nid), PATROL_COL)


# 下一步箭头：16.6px 格放不下独立箭头，画一个指向格心的实心三角。
func _draw_arrow(a: Vector2, b: Vector2, col: Color) -> void:
	var d := b - a
	if d.length() < 1.0:
		return
	var dir := d.normalized()
	var tip := b - dir * (_node_w * 0.5 - 3.0)
	var base := tip - dir * 4.5
	var side := dir.orthogonal() * 3.2
	_art.draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), col)


func _draw_grid_node(id: String, pos: Vector2, font: Font) -> void:
	var n: Dictionary = board.node_by_id(id)
	if n.is_empty():
		return
	var type := String(n.get("type", "battle"))
	var terrain := String(n.get("terrain", ""))
	var consumed: bool = board.is_consumed(id)
	var is_cur: bool = id == String(board.current_id)
	var is_adj := _is_legal(id)
	var hovered := id == _selected_id and not is_cur
	var box := Rect2(pos, Vector2(_node_w, NODE_H))
	var c := pos + Vector2(_node_w * 0.5, NODE_H * 0.5)
	var is_path := type == MAP_TYPES.PATH
	var is_door := terrain == "door"

	# 格底：通路/门更暗，有内容的格略亮，让地图形状一眼可读。
	var fill := NODE_BG
	if is_path or is_door:
		fill = PATH_BG
	if consumed:
		fill = NODE_BG_DONE
	_art.draw_rect(box, fill)
	if is_cur:
		_art.draw_rect(box, Palette.FRAME_MAIN, false, 1.5)
	elif is_adj:
		_art.draw_rect(box, Palette.ACCENT_GOLD, false, 1.0)
	elif hovered:
		_art.draw_rect(box, Palette.MUTED, false, 1.0)
	elif type == "boss":
		_art.draw_rect(box, Palette.ACCENT_GOLD, false, 1.0)
	else:
		_art.draw_rect(box, _act_theme.get("node", Color("#3a2b31")), false, 1.0)

	# 单字：16.6px 格只放得下一个汉字，图标让位给可读性（设计稿口径）。
	var tag := "门" if is_door else String(SHORT.get(type, ""))
	if tag == "":
		return
	var col: Color = Palette.MUTED_DIM
	if type == "boss":
		col = Palette.ACCENT_GOLD
	elif MAP_TYPES.is_battle(type):
		col = Palette.ENEMY
	elif consumed:
		col = Palette.MUTED_DIM
	else:
		col = Palette.TITLE
	var w := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	_art_text(font, Vector2(c.x - w * 0.5, c.y + 3.5), tag, 10, col)


func _art_text(font: Font, pos: Vector2, text: String, size: int, col: Color) -> void:
	_art.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# 节点说明：通路 / 起点只写地形，内容节点写「类别 + 真实结算结果 + 陷阱影响」。
func _tooltip(n: Dictionary) -> String:
	if n.is_empty():
		return ""
	var lines: Array[String] = []
	var type := String(n.get("type", ""))
	if type == MAP_TYPES.PATH:
		return "通路"
	if type == MAP_TYPES.START:
		return "本幕起点"
	lines.append(_node_heading(n))
	lines.append(MAP_TYPES.label_of(type))
	var grant := _grant_text(String(n.get("id", "")))
	if grant != "":
		lines.append(grant)
	var trap := _trap_text(int(n.get("cell_id", -1)))
	if trap != "":
		lines.append(trap)
	var status := _node_status(n)
	if status != "":
		lines.append(status)
	return "\n".join(lines)


# 结算预告：写出具体数值或具体结果（§4.2 第 3 项），不出现资源路径与抽象数字。
func _grant_text(id: String) -> String:
	var rt = board.runtime
	if rt == null:
		return ""
	var cell := _cell_of(id)
	if cell < 0:
		return ""
	var g: Dictionary = rt.grant_preview(cell)
	if g.is_empty():
		return ""
	var lines: Array[String] = []
	var text := _grant_line(g)
	if text != "":
		lines.append(text)
	lines.append_array(_equip_lines(g))
	var out := "\n".join(lines)
	if out == "":
		return ""
	if bool(g.get("consumed", false)):
		out += "（已领取）"
	return out


# G4-03：装备格公开「替换影响」——与当前武器逐把比较攻击 / 命中（含熟练与铸式修正）。
# 只读计算，不改变任何状态。
func _equip_lines(g: Dictionary) -> Array[String]:
	var paths: Array = []
	var mode := String(g.get("mode", ""))
	if mode == "item" and String(g.get("category", "")) == "weapon":
		paths.append(String(g.get("path", "")))
	elif mode == "choose_one":
		paths = (g.get("options", []) as Array).duplicate()
	var out: Array[String] = []
	for p in paths:
		if String(p) != "":
			out.append(_equip_line(String(p)))
	return out


func _equip_line(path: String) -> String:
	if controller == null:
		return _item_name(path, "weapon")
	var wd: WeaponData = load(path)
	if wd == null:
		return _item_name(path, "weapon")
	var line := _item_name(path, "weapon")
	for old in controller.selected_loadout:
		var op := String(old)
		if op == path:
			continue
		var dmg: int = int(controller.weapon_power(path)) - int(controller.weapon_power(op))
		var hit: int = int(round((float(controller.weapon_hit(path)) - float(controller.weapon_hit(op))) * 100.0))
		line += " · 替换%s 攻%s 命%s%%" % [_item_name(op, "weapon"),
			("+" if dmg >= 0 else "") + str(dmg), ("+" if hit >= 0 else "") + str(hit)]
		break
	return line


func _grant_line(g: Dictionary) -> String:
	var mode := String(g.get("mode", ""))
	if mode == "gold":
		return "金币 +%d" % int(g.get("amount", 0))
	if mode == "item":
		return "获得%s %s" % [_cat_label(String(g.get("category", ""))),
			_item_name(String(g.get("path", "")), "weapon")]
	if mode == "active":
		return "获得消耗品 %s" % _item_name(String(g.get("path", "")), "consumable")
	if mode == "choose_one":
		return "武器 %d 选 1（放弃 +%d 金）" % [
			(g.get("options", []) as Array).size(), int(g.get("fallback_gold", 0))]
	if mode == "purchase":
		return "在售 %d 件 · 需付费购买" % (g.get("stock", []) as Array).size()
	if mode == "heal":
		return "恢复最大 HP %d%%" % int(round(float(g.get("pct", 0.0)) * 100.0))
	if mode == "shrine":
		return String(g.get("text", "神龛"))
	if mode == "battle":
		var room = g.get("room")
		return "战斗：%s" % ("未知房间" if room == null else String(room.name))
	return String(g.get("text", ""))


# 长名称截断：信息栏 132 宽放不下完整武器名，只保留可辨识的前若干字。
func _item_name(path: String, kind: String) -> String:
	if path == "" or controller == null:
		return "（空）"
	var n := String(controller._shop_name(path, kind))
	return n.substr(0, 10) if n.length() > 10 else n


func _cat_label(cat: String) -> String:
	return String({"weapon": "武器", "charm": "护符", "active": "消耗品"}.get(cat, ""))


# 陷阱对该格下一场战斗的真实影响（护甲 X → 0）。
func _trap_text(cell: int) -> String:
	var rt = board.runtime
	if rt == null or cell < 0:
		return ""
	if not rt.is_trap_cell(cell):
		return ""
	for t in rt.trap_preview():
		if int(t.get("cell", -1)) == cell and bool(t.get("armed", false)):
			return String(t.get("text", ""))
		if int(t.get("next", -1)) == cell and String(t.get("hint", "")) != "":
			return String(t["hint"])
	return "破甲陷阱：怪物踩到后护甲归零"


func _cell_of(id: String) -> int:
	var n: Dictionary = board.node_by_id(id)
	return int(n.get("cell_id", -1))


func _node_status(n: Dictionary) -> String:
	if n.is_empty():
		return ""
	var id := String(n["id"])
	if id == String(board.current_id):
		return "当前位置"
	if board.is_consumed(id):
		return "已探索（可再次经过）"
	if _is_legal(id):
		return "相邻 · 可移动"
	return "不相邻"


# §4.2：目标名称与类别 + 真实结算结果 + 陷阱影响 + 当前可执行操作。
func _refresh_info() -> void:
	var n: Dictionary = board.node_by_id(_selected_id)
	if n.is_empty():
		n = board.current_node()
	var id := String(n.get("id", ""))
	var type := String(n.get("type", ""))
	# 面板副标题：默认操作说明；悬停 / 选中其它格时改写成该格的真实结果。
	var parts: Array[String] = []
	var is_cur := id == String(board.current_id)
	if is_cur:
		# 站在该格时不重复报格名，直接给结算反馈或操作说明。
		if board.feedback != "":
			parts.append(board.feedback)
	elif type == MAP_TYPES.PATH:
		parts.append("通路")
		var ptrap := _trap_text(int(n.get("cell_id", -1)))
		if ptrap != "":
			parts.append(ptrap)
	elif type == MAP_TYPES.START:
		parts.append("本幕起点")
	else:
		parts.append(_node_heading(n))
		var grant := _grant_text(id)
		if grant != "":
			parts.append(grant)
		var trap := _trap_text(int(n.get("cell_id", -1)))
		if trap != "":
			parts.append(trap)
	if is_cur and board.feedback != "":
		parts.append(board.feedback)
	var status := _node_status(n)
	if status != "" and not is_cur:
		parts.append(status)
	if parts.size() <= 1:
		parts.append("点击相邻格移动，或选择等待 · 每次操作推进一回合")
	_map_hint_text = " · ".join(parts)
	if _art != null:
		_art.queue_redraw()


# §4.2 第 2/3 项：怪物当前格与下一格（箭头＋文字，不只靠颜色）+ 陷阱真实影响。
# 下一步方向词：cell 编号是内部标识，玩家只需要「往哪走」。
func _dir_word(a_cell: int, b_cell: int) -> String:
	var a := _node_rc(a_cell)
	var b := _node_rc(b_cell)
	if b.y < a.y:
		return "上"
	if b.y > a.y:
		return "下"
	if b.x < a.x:
		return "左"
	if b.x > a.x:
		return "右"
	return "原地"


func _node_rc(cell: int) -> Vector2i:
	var n: Dictionary = board.node_by_id(_id_at_cell(cell))
	return Vector2i(int(n.get("col", -1)), int(n.get("row", -1)))


func _refresh_patrol_info() -> void:
	var rt = board.runtime
	if rt == null or not rt.patrol_enabled:
		_card_desc_1.text = "本区无巡逻怪"
		_card_desc_3.text = "本图没有公开陷阱"
		_card_desc_4.text = "进战斗后按护甲原值结算"
		return
	var rows: Array[String] = []
	var trap_line := ""
	var battle_line := ""
	for t in rt.trap_preview():
		# 只显示地图上看得见的怪物：远处怪物对当前决策无意义。
		if not _pos.has(_id_at_cell(int(t.get("cell", -1)))) \
				and not _pos.has(_id_at_cell(int(t.get("next", -1)))):
			continue
		if rows.size() >= 1:
			break
		var dirw := _dir_word(int(t.get("cell", -1)), int(t.get("next", -1)))
		if bool(t.get("armed", false)):
			rows.append("预告：已破甲，与实际一致")
			trap_line = String(t.get("text", ""))
			battle_line = "下一战护甲 %d → %d" % [int(t.get("armor", 0)), int(t.get("armor_after", 0))]
		elif bool(t.get("next_is_trap", false)):
			rows.append("预告：向%s进入陷阱" % dirw)
			trap_line = String(t.get("hint", ""))
			battle_line = "踩中后下一战护甲归零"
		else:
			rows.append("预告：向%s移动" % dirw)
	# 卡片 ① 的说明随状态改写：等待是唯一推进回合的操作。
	_card_desc_1.text = rows[0] if not rows.is_empty() else "本图没有巡逻怪"
	_card_desc_3.text = trap_line if trap_line != "" else "触发公开破甲陷阱（护甲归零）"
	_card_desc_4.text = battle_line if battle_line != "" else "敌方护甲降低，仍靠 Build 击败"


# ---------------------------------------------------------------------------
# 输入：等待 / 悬停 / 点击相邻格
# ---------------------------------------------------------------------------

# 底栏「等待一回合」：原地不动，怪物按预告行动一次，地图推进一个回合（§2.2）。
func _on_wait() -> void:
	if board == null or _moving or _stepping or not _pending_node.is_empty():
		return
	var waited: Dictionary = board.wait_here()
	if not waited.is_empty():
		_pending_node = waited
		_confirm_layer.visible = true
	refresh()


func _on_node_hover(id: String) -> void:
	if board == null:
		return
	_selected_id = id
	_refresh_info()
	if _art != null:
		_art.queue_redraw()   # 悬停描边


func _on_node_pressed(id: String) -> void:
	if board == null:
		return
	_selected_id = id
	_refresh_info()
	if _art != null:
		_art.queue_redraw()   # 悬停描边
	if _moving or _stepping or not _pending_node.is_empty():
		return
	# 只允许进入四方向相邻格；已消耗格可再次经过（BoardSystem 只移动、不重复结算）。
	if id == String(board.current_id):
		return
	for n in board.legal_targets():
		if String(n["id"]) != id:
			continue
		var target: Dictionary = board.node_by_id(id)
		var ty := String(target.get("type", ""))
		# 精英 / BOSS 先打开确认层：不移动、不消耗、不改数字；
		# 玩家可以「继续探索 / 返回探索」，误点不会强制开战。
		if (ty == "elite" or ty == "boss") and not board.is_defeated(id):
			_show_battle_confirm(target)
			return
		if controller._journal != null:
			controller._journal.note_first_pick(id)
		_advance_to(id)
		return


func _advance_to(id: String, start_battle := false) -> void:
	if _moving or _stepping or board == null:
		return
	var node: Dictionary = board.advance_to(id)
	if node.is_empty():
		return
	var revisit: bool = bool(board.last_move_revisit)
	if not revisit and controller._journal != null:
		controller._journal.note_node(node)   # G5 工具：路线记录（自动前进/手动落点都算）
	_moving = true
	var from_pos: Vector2 = _piece.position
	refresh()
	_piece.position = from_pos   # refresh 会把棋子放到新节点；动画需从旧位置出发
	var tw := create_tween()
	tw.tween_property(_piece, "position", _piece_pos(id), STEP_SEC)
	await tw.finished
	_moving = false
	if board == null:
		return
	refresh()
	if revisit:
		return   # 已消耗格只移动，不重复结算奖励 / 战斗
	# 落点效果只在移动动画结束后执行一次；重复点击不会再次进入。
	# 普通怪先弹确认；网格精英 / BOSS 在确认层点「挑战」后以 start_battle=true 直接开战。
	if start_battle:
		controller._on_board_node_entered(node)
	elif String(node.get("type", "")) in ["battle", "elite", "boss"]:
		_show_battle_confirm(node)
	else:
		controller._on_board_node_entered(node)


# 战斗确认：普通怪在落点后确认；网格精英 / BOSS 在点击邻格时先行预览，不移动、不消耗。
func _show_battle_confirm(node: Dictionary) -> void:
	if node.is_empty():
		return
	_pending_node = node
	_selected_id = String(node.get("id", ""))
	var kind := String(node.get("type", "battle"))
	_confirm_title.text = {"battle": "遭遇战", "elite": "精英战", "boss": "BOSS 战"}.get(kind, "战斗")
	var r: RoomData = node.get("room")
	_confirm_enemy.text = r.name if r != null else "未知敌人"
	var bits: Array[String] = []
	if r != null:
		var s: Dictionary = controller._ante_scale(r, int(node.get("battle_index", -1)), int(node.get("ria", -1)))
		var base_hp: int = r.hp if r.hp > 0 else (r.archetype.hp_base if r.archetype != null else 0)
		var base_atk: int = r.atk if r.atk > 0 else (r.archetype.atk_base if r.archetype != null else 0)
		var hp := int(round(float(base_hp) * float(s["hp_scale"])))
		var atk := int(round(float(base_atk) * float(s["atk_scale"])))
		bits.append("HP %d · 攻 %d · %s" % [hp, atk, ElementCounter.label(r.element)])
		if r.gimmick_script != null:
			# 普通怪早期特性也走 mechanic_summary：确认层直接读出「它是什么」。
			var mech := String(r.mechanic_summary)
			bits.append(mech if mech != "" else "特殊机制")
		if kind == "boss":
			# 真实机制预览：BOSS 弱点 + 当前武器元素，不显示伪造胜率或装备门槛。
			bits.append(_weakness_line(String(r.element)))
			var elems := _player_weapon_elements()
			if not elems.is_empty():
				bits.append("你的武器元素：%s" % "、".join(elems))
	if kind == "elite":
		# 既有精英规则：金币囤 + 铁砧点固定，另 1 项高品质奖励来自武器 / 消耗品 / 生命回复。
		bits.append("战利品：金币囤 + 铁砧点 + 1 项高品质奖励")
		bits.append("高品质候选：武器 / 消耗品 / 生命回复")
		var targets := _adjacent_target_names(String(node.get("id", "")))
		if not targets.is_empty():
			bits.append("邻近目标：" + "、".join(targets))
	_confirm_stats.text = "\n".join(bits)
	if kind == "boss":
		_confirm_btn.text = "挑战 BOSS"
	elif kind == "elite":
		_confirm_btn.text = "挑战精英"
	else:
		_confirm_btn.text = "进入战斗"
	var alt := ""
	if kind == "boss":
		alt = "继续探索"
	elif kind == "elite":
		alt = "返回探索"
	_confirm_alt_btn.visible = alt != ""
	_confirm_alt_btn.text = alt
	_confirm_layer.visible = true
	refresh()


func _on_confirm_battle() -> void:
	if _pending_node.is_empty():
		return
	var node := _pending_node
	_pending_node = {}
	_confirm_layer.visible = false
	# 网格精英 / BOSS 预确认时玩家还没进入该格：先移动并消耗，再直接开战。
	if String(board.current_id) != String(node.get("id", "")):
		_advance_to(String(node.get("id", "")), true)
		return
	controller._on_board_node_entered(node)


# 「继续探索 / 返回探索」：关闭确认层，不移动、不消耗、不改数字 / HP / Build / RNG。
func _on_confirm_alt() -> void:
	_pending_node = {}
	_confirm_layer.visible = false
	refresh()


# BOSS 弱点：返回真实克制元素（×1.5），不预测胜率。
func _weakness_line(element: String) -> String:
	var names: Array[String] = []
	for e in ElementCounter.weakness(element):
		names.append(ElementCounter.label(String(e)))
	if names.is_empty():
		return "弱点：无（中性伤害）"
	return "弱点：%s ×1.5" % " / ".join(names)


func _player_weapon_elements() -> Array[String]:
	var out: Array[String] = []
	for p in controller.selected_loadout:
		var wd: WeaponData = load(String(p))
		if wd != null and String(wd.element) != "none":
			out.append(ElementCounter.label(String(wd.element)))
	return out


# 精英邻近的可见装备目标（只读；用于「高风险换定向奖励」预告）。
func _adjacent_target_names(id: String) -> Array[String]:
	var out: Array[String] = []
	var n: Dictionary = board.node_by_id(id)
	for nx in n.get("next", []):
		var t: Dictionary = board.node_by_id(String(nx))
		var ty := String(t.get("type", ""))
		var path := String(t.get("item_path", ""))
		if path == "":
			continue
		if ty == "weapon":
			out.append("武器「%s」" % controller._shop_name(path, "weapon"))
		elif ty == "charm":
			out.append("护符「%s」" % controller._shop_name(path, "passive"))
	return out
