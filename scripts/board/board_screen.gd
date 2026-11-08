extends Control

# ============================================================================
# BoardScreen — ACT1 棋盘灰盒主视图（M2）
# 规格：docs/棋盘探索_战后成长与局外生涯_制作执行方案.md §5.3、§9、§11 M2
#
# 独立满屏视图：显示时 hud.hide()，进入战斗 / 商店时切回战斗 HUD。
# 由 BattleHud._build_board_screen 挂到 Duel 根（与整备场景同级），不挤进战斗中央区域。
#
# 移动时序：掷 1D3 得到步数预算 → 每次沿一条边前进一格并立即结算 →
# 有剩余步数时显示「继续」，分支处高亮两条路等待点击。
# 掷骰是唯一使用 RNG 的步骤；移动动画不消耗 RNG。
# ============================================================================

const UI_BUTTON = preload("res://scenes/ui/ui_button.tscn")
const NODE = preload("res://scripts/board/board_node_data.gd")

# G3-02：16×16 点阵图标（tools/art_pipeline/make_board_icons.py 生成，≤3 色）
const ICON := {
	"start": preload("res://assets/icons/16/board_start.png"),
	"normal": preload("res://assets/icons/16/board_normal.png"),
	"elite": preload("res://assets/icons/16/board_elite.png"),
	"boss": preload("res://assets/icons/16/board_boss.png"),
	"weapon": preload("res://assets/icons/16/fire_sword.png"),
	"charm": preload("res://assets/icons/16/board_charm.png"),
	"shop": preload("res://assets/icons/16/board_shop.png"),
	"rest": preload("res://assets/icons/16/board_rest.png"),
	"treasure": preload("res://assets/icons/16/board_treasure.png"),
	"shrine": preload("res://assets/icons/16/board_shrine.png"),
	"armory": preload("res://assets/icons/16/board_armory.png"),
}
const PIECE_ICON = preload("res://assets/icons/16/board_piece.png")

const NODE_H := 28.0
const STEP_SEC := 0.12

# 节点位置由 BoardSystem.layout 决定（G4-02 两种骨架：标准 / 长尾）：
# x = x0 + depth·dx（depth 即列号），y = row_y[node.row]。
# 标准 25 节点沿用 G3 坐标（x0 6 / dx 36 / 宽 34）；长尾 29 节点压缩到 14 列（x0 4 / dx 34 / 宽 30）。
const DEFAULT_LAYOUT := {
	"x0": 6.0, "dx": 36.0, "node_w": 34.0, "row_y": [24.0, 58.0, 92.0, 126.0, 160.0],
}

# 34 / 30px 宽的节点放不下 emoji + 汉字（点阵字体缺字形会显示成方框），
# 节点统一用几何图标 + 单字标签；BOSS 例外，显示名字前两字。
const SHORT := {
	"start": "起", "normal": "战", "elite": "精", "boss": "王",
	"weapon": "武", "charm": "符", "shop": "店", "rest": "营", "treasure": "宝", "shrine": "龛",
	"armory": "库",
}

# 道路 / 节点状态色（与样稿一致；语义仍由 Palette 决定）
const ROAD_DONE := Color("#4b3b33")
const ROAD_UNDONE := Color("#3a2b31")
const NODE_BG := Color("#1d1219")
const NODE_BG_DONE := Color("#120b11")

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
var _art: Control = null     # 地图绘制层（道路 / 节点 / 状态框 / 图标）
var _bg: ColorRect = null
var _title_label: Label = null
var _act_theme: Dictionary = Palette.ACT_THEME[1]   # G7-A S3：按幕换配色
var _piece: TextureRect = null
var _advance_btn: Button = null
var _trim_btn: Button = null
var _dice_label: Label = null
var _node_title: Label = null
var _node_desc: Label = null
var _summary: Label = null
var _top_right: Label = null

# 战斗确认层：落到战斗节点后不立刻开打，先展示敌人与属性，由玩家点「进入战斗」。
var _confirm_layer: Control = null
var _confirm_title: Label = null
var _confirm_enemy: Label = null
var _confirm_stats: Label = null
var _confirm_btn: Button = null
var _pending_node: Dictionary = {}


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

	# 道路 / 节点 / 状态框全部画在一层 art 上；节点按钮只做透明热区，负责点击与 tooltip。
	# art 必须在背景之后、按钮之前：按钮不画内容，避免像旧版那样用按钮底框当节点。
	_art = Control.new()
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	_art.draw.connect(_draw_art)

	var title := _label("棋盘 · ACT I", 10, Palette.ACCENT_GOLD)
	title.position = Vector2(8, 2)
	title.size = Vector2(220, 18)
	add_child(title)
	_title_label = title

	_top_right = _label("", 9, Palette.MUTED)
	_top_right.position = Vector2(240, 3)
	_top_right.size = Vector2(232, 16)
	_top_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_top_right)

	# 节点按钮不在这里建：骨架每局可能不同（25 / 29 个节点、列宽变化），
	# 由 show_board → _ensure_buttons() 按当前棋盘重建（保持在确认层之下）。

	_piece = TextureRect.new()
	_piece.texture = PIECE_ICON
	_piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_piece.stretch_mode = TextureRect.STRETCH_SCALE
	_piece.size = Vector2(12, 12)
	_piece.position = Vector2(30, 14)
	_piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_piece)

	# 底栏（G3-01）：地图到 y 198，详情 / 构筑 200–244，掷骰条 246–268。
	var left := _panel(Vector2(6, 194), Vector2(302, 44))
	var lv: VBoxContainer = left.get_node("VBox")
	lv.add_theme_constant_override("separation", 1)
	_node_title = _label("", 9, Palette.TITLE)
	lv.add_child(_node_title)
	_node_desc = _label("", 8, Palette.MUTED)
	_node_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_node_desc.clip_text = true
	_node_desc.add_theme_constant_override("line_spacing", 0)
	_node_desc.max_lines_visible = 2
	_node_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(_node_desc)

	var right := _panel(Vector2(312, 194), Vector2(162, 44))
	var rv: VBoxContainer = right.get_node("VBox")
	_summary = _label("", 8, Palette.PLAYER)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.clip_text = true
	_summary.add_theme_constant_override("line_spacing", 0)
	_summary.max_lines_visible = 3
	_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(_summary)

	_advance_btn = UI_BUTTON.instantiate()
	_advance_btn.position = Vector2(6, 238)
	_advance_btn.size = Vector2(126, 22)
	_advance_btn.custom_minimum_size = Vector2(126, 22)
	_advance_btn.text = "🎲 前进"
	_advance_btn.pressed.connect(_on_advance)
	add_child(_advance_btn)

	_dice_label = _label("", 8, Palette.MUTED)
	_dice_label.position = Vector2(140, 238)
	_dice_label.size = Vector2(254, 30)
	add_child(_dice_label)

	# G7-B B3：主动减带入口（每幕 1 次）。弹层在 battle_hud，这里只放按钮与状态。
	_trim_btn = UI_BUTTON.instantiate()
	_trim_btn.position = Vector2(400, 238)
	_trim_btn.size = Vector2(74, 22)
	_trim_btn.custom_minimum_size = Vector2(74, 22)
	_trim_btn.add_theme_font_size_override("font_size", 9)
	_trim_btn.text = "✂ 精简 1/1"
	_trim_btn.pressed.connect(_on_trim_pressed)
	add_child(_trim_btn)

	_build_confirm_layer()


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
	panel.position = Vector2(90, 68)
	panel.size = Vector2(300, 136)
	panel.custom_minimum_size = Vector2(300, 136)
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
	vb.add_child(row)
	_confirm_btn = UI_BUTTON.instantiate()
	_confirm_btn.custom_minimum_size = Vector2(150, 30)
	_confirm_btn.size = Vector2(150, 30)
	_confirm_btn.text = "进入战斗"
	_confirm_btn.pressed.connect(_on_confirm_battle)
	row.add_child(_confirm_btn)


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


# 从 BoardSystem.layout 计算节点坐标：x = x0 + depth·dx，y = row_y[row]。
func _apply_layout() -> void:
	if board == null:
		return
	var layout: Dictionary = board.layout if not board.layout.is_empty() else DEFAULT_LAYOUT
	_node_w = float(layout.get("node_w", DEFAULT_LAYOUT["node_w"]))
	var x0: float = float(layout.get("x0", DEFAULT_LAYOUT["x0"]))
	var dx: float = float(layout.get("dx", DEFAULT_LAYOUT["dx"]))
	var rows: Array = layout.get("row_y", DEFAULT_LAYOUT["row_y"])
	_pos.clear()
	for n in board.nodes:
		var row := clampi(int(n.get("row", 2)), 0, rows.size() - 1)
		_pos[String(n["id"])] = Vector2(x0 + float(int(n["depth"])) * dx, float(rows[row]))


func _layout_buttons() -> void:
	for id in _buttons:
		var b: Button = _buttons[id]
		b.position = _node_pos(String(id))
		b.custom_minimum_size = Vector2(_node_w, NODE_H)
		b.size = Vector2(_node_w, NODE_H)


func _panel(pos: Vector2, sz: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = pos
	p.size = sz
	p.custom_minimum_size = sz
	var vb := VBoxContainer.new()
	vb.name = "VBox"
	vb.add_theme_constant_override("separation", 2)
	p.add_child(vb)
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
	if _title_label != null:
		_title_label.text = "棋盘 · %s" % String(_act_theme.get("name", "ACT I"))
	if _bg != null:
		_bg.color = _act_theme.get("bg", Palette.BG_MAIN)


func refresh() -> void:
	if board == null:
		return
	_apply_act_theme()
	queue_redraw()
	if board.feedback != "":
		_selected_id = String(board.current_id)
	var legal := {}
	for n in board.legal_targets():
		legal[String(n["id"])] = true
	for id in _buttons:
		var b: Button = _buttons[id]
		b.tooltip_text = _tooltip(board.node_by_id(String(id)))
	if _art != null:
		_art.queue_redraw()   # 节点外观 / 道路状态统一由 _draw_art 重画
	_piece.position = _piece_pos(String(board.current_id))
	_piece.visible = true
	if not _pending_node.is_empty():
		_advance_btn.disabled = true
		_advance_btn.text = "待确认"
		_dice_label.text = "确认后进入战斗"
	elif _moving:
		_advance_btn.disabled = true
		_advance_btn.text = "…"
		_dice_label.text = "移动中…"
	elif board.current_is_boss():
		_advance_btn.disabled = true
		_advance_btn.text = "👑 BOSS"
		_dice_label.text = "抵达 BOSS 节点"
	elif board.dice > 0:
		_advance_btn.disabled = false
		_advance_btn.text = "▶ 继续"
		if legal.size() > 1:
			_dice_label.text = "剩 %d 步 · 分支：点击高亮格（%d 个）" % [board.dice, legal.size()]
		else:
			_dice_label.text = "剩 %d 步 · 继续前进" % board.dice
	else:
		_advance_btn.disabled = not board.can_roll()
		_advance_btn.text = "🎲 前进"
		_dice_label.text = "掷 1D3：逐格前进，每格结算"
	_top_right.text = "HP %d/%d · 💰 %d · 已走 %d/%d" % [
		controller.player_hp, controller.player_hp_max, controller.gold,
		board.visited_count(), board.route_length()]
	_refresh_trim_btn()
	_refresh_info()
	_refresh_summary()


# G7-B B3：精简入口状态（ready 可点 / used 本幕已用 / none 隐藏）。
func _refresh_trim_btn() -> void:
	if _trim_btn == null:
		return
	var st := "none"
	if controller != null and controller._trim != null:
		st = controller._trim.entry_state()
	_trim_btn.visible = st != "none"
	_trim_btn.disabled = st != "ready" or _moving or _stepping or not _pending_node.is_empty()
	_trim_btn.text = "✂ 精简 1/1" if st == "ready" else "✂ 本幕已用"


func _on_trim_pressed() -> void:
	if hud != null:
		hud.show_trim_dialog()


# 信息栏标题：点阵字体缺 emoji 字形，这里只用文字，不再拼图标。
func _node_heading(n: Dictionary) -> String:
	if n.is_empty():
		return ""
	var t := String(n.get("title", ""))
	if t != "":
		return t
	return NODE.label(String(n.get("type", "")))


func _node_tag(id: String, type: String, n: Dictionary = {}) -> String:
	if type == "boss":
		var r: RoomData = n.get("room")
		if r != null and String(r.name) != "":
			return String(r.name).substr(0, 2)
		return "王"
	return String(SHORT.get(type, "•"))


func _node_pos(id: String) -> Vector2:
	return _pos.get(id, Vector2.ZERO)


func _node_center(id: String) -> Vector2:
	return _node_pos(id) + Vector2(_node_w * 0.5, NODE_H * 0.5)


# 棋子放在节点右上角，避免遮挡节点文字与顶栏。
func _piece_pos(id: String) -> Vector2:
	return _node_pos(id) + Vector2(_node_w - 13, -4)


# ---------------------------------------------------------------------------
# G3-01 地图绘制：直角道路 / 节点状态框 / 几何图标 / 区域标注
# 只读 BoardSystem 的查询结果，不改任何规则；refresh() 时整层重画。
# ---------------------------------------------------------------------------

func _draw_art() -> void:
	if board == null:
		return
	var font := get_theme_default_font()
	# 地图底：比整屏略亮的低对比底 + 16px 石砖网格（只作质感，不参与交互）。
	# G7-A S3：底色按幕取（ACT1 紫褐 / ACT2 青灰 / ACT3 暗红），不新增美术资源。
	var map_bg: Color = _act_theme.get("map", Color("#1a1016"))
	var grid_col: Color = _act_theme.get("grid", Color("#1e1319"))
	var node_line: Color = _act_theme.get("node", Color("#3a2b31"))
	_art.draw_rect(Rect2(0, 22, 480, 170), map_bg)
	for gx in range(0, 481, 16):
		_art.draw_line(Vector2(gx, 22), Vector2(gx, 192), grid_col, 1)
	for gy in range(22, 193, 16):
		_art.draw_line(Vector2(0, gy), Vector2(480, gy), grid_col, 1)
	for n in board.nodes:
		var from_id := String(n["id"])
		for nx in n.get("next", []):
			_draw_road(_node_center(from_id), _node_center(String(nx)),
				_road_color(from_id, String(nx)))
	_art_text(font, Vector2(206, 82), "岔路 A", 8, Palette.MUTED_DIM)
	_art_text(font, Vector2(250, 44), "尾路 → 四座 BOSS", 8, Palette.MUTED_DIM)
	_art_text(font, Vector2(6, 44), "金框=可达 · 暗色=已走 · 红=敌人", 7, Palette.MUTED_DIM)
	for n in board.nodes:
		var id := String(n["id"])
		_draw_node(id, _node_pos(id), font)


func _road_color(a: String, b: String) -> Color:
	for n in board.legal_targets():
		if String(n["id"]) == b:
			return Palette.ACCENT_GOLD
	if board.is_consumed(a) and board.is_consumed(b):
		return ROAD_DONE
	return ROAD_UNDONE


# 直角折线：横 → 竖 → 横，3px 方头，避免斜线在点阵画面上发虚。
func _draw_road(a: Vector2, b: Vector2, col: Color) -> void:
	if absf(a.y - b.y) < 0.5:
		_art.draw_rect(Rect2(a.x, a.y - 1.5, b.x - a.x, 3), col)
		return
	var mid := (a.x + b.x) * 0.5
	_art.draw_rect(Rect2(a.x, a.y - 1.5, mid - a.x, 3), col)
	_art.draw_rect(Rect2(mid - 1.5, minf(a.y, b.y), 3, absf(b.y - a.y)), col)
	_art.draw_rect(Rect2(mid, b.y - 1.5, b.x - mid, 3), col)


func _draw_node(id: String, pos: Vector2, font: Font) -> void:
	var n: Dictionary = board.node_by_id(id)
	if n.is_empty():
		return
	var type := String(n.get("type", "normal"))
	var consumed: bool = board.is_consumed(id)
	var is_cur: bool = id == String(board.current_id)
	var is_legal := false
	for t in board.legal_targets():
		if String(t["id"]) == id:
			is_legal = true
	var hovered := id == _selected_id and not is_cur and not is_legal
	var box := Rect2(pos, Vector2(_node_w, NODE_H))
	var c := pos + Vector2(_node_w * 0.5, NODE_H * 0.5)

	_art.draw_rect(box, NODE_BG_DONE if consumed else NODE_BG)
	if is_cur:
		_art.draw_rect(box, Palette.FRAME_MAIN, false, 2.0)
		_art.draw_rect(Rect2(pos.x, pos.y + NODE_H - 3, _node_w, 3), Palette.ACCENT_GOLD)
	elif is_legal:
		_art.draw_rect(box, Palette.ACCENT_GOLD, false, 2.0)
		_art.draw_circle(c + Vector2(_node_w * 0.5 - 4, -10), 2.0, Palette.ACCENT_GOLD)
	elif hovered:
		_art.draw_rect(box, Palette.MUTED, false, 1.0)
	elif String(type) == "boss":
		# 祭坛双层金框，和普通节点区分
		_art.draw_rect(box, Palette.ACCENT_GOLD, false, 1.0)
		_art.draw_rect(Rect2(pos.x + 2, pos.y + 2, _node_w - 4, NODE_H - 4), Color("#8c6a24"), false, 1.0)
	else:
		_art.draw_rect(box, _act_theme.get("node", Color("#3a2b31")), false, 1.0)

	_draw_icon(type, c + Vector2(0, -4), consumed)
	var tag := _node_tag(id, type, n)
	var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
	_art_text(font, Vector2(c.x - tw * 0.5, pos.y + NODE_H - 1), tag, 7,
		Palette.MUTED_DIM if consumed else Palette.TITLE)


func _draw_icon(type: String, c: Vector2, consumed: bool) -> void:
	var tex: Texture2D = ICON.get(type)
	if tex == null:
		return
	_art.draw_texture_rect(tex, Rect2(c - Vector2(8, 8), Vector2(16, 16)), false,
		Color(1, 1, 1, 0.45) if consumed else Color.WHITE)


func _art_text(font: Font, pos: Vector2, text: String, size: int, col: Color) -> void:
	_art.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _tooltip(n: Dictionary) -> String:
	if n.is_empty():
		return ""
	var status := _node_status(n)
	var impact := _equip_impact(n)
	return "%s\n%s\n%s%s%s" % [NODE.display_title(n), NODE.display_desc(n),
		NODE.hint(String(n["type"])), impact, "\n" + status if status != "" else ""]


# G4-03：武器格公开「替换影响」——与当前已带武器逐把比较攻击 / 命中（含熟练与铸式修正）。
# 只读计算，不改变任何状态；护符是效果型，不在节点层伪造量化差异。
func _equip_impact(n: Dictionary) -> String:
	if String(n.get("type", "")) != "weapon":
		return ""
	var path := String(n.get("item_path", ""))
	if path == "" or controller == null:
		return ""
	var wd: WeaponData = load(path)
	if wd == null:
		return ""
	var lines: Array[String] = []
	for old in controller.selected_loadout:
		var op := String(old)
		if op == path:
			continue
		var owd: WeaponData = load(op)
		var oname: String = String(owd.weapon_name) if owd != null else op.get_file().get_basename()
		var dmg: int = int(controller.weapon_power(path)) - int(controller.weapon_power(op))
		var hit: int = int(round((float(controller.weapon_hit(path)) - float(controller.weapon_hit(op))) * 100.0))
		lines.append("替换 %s：攻%s / 命中%s%%" % [oname,
			("+" if dmg >= 0 else "") + str(dmg), ("+" if hit >= 0 else "") + str(hit)])
	if lines.is_empty():
		return ""
	return "\n" + "\n".join(lines)


func _node_status(n: Dictionary) -> String:
	if n.is_empty():
		return ""
	var id := String(n["id"])
	if id == String(board.current_id):
		return "当前位置"
	if board.is_consumed(id):
		return "已探索"
	for t in board.legal_targets():
		if String(t["id"]) == id:
			return "可到达（高亮落点）"
	var d: int = int(n["depth"]) - board.current_depth()
	if d > 0:
		return "前方 %d 格" % d
	return ""


func _refresh_info() -> void:
	var n: Dictionary = board.node_by_id(_selected_id)
	if n.is_empty():
		n = board.current_node()
	_node_title.text = _node_heading(n)
	var status := _node_status(n)
	var text := NODE.display_desc(n)
	if board.feedback != "" and String(n.get("id", "")) == String(board.current_id):
		text = board.feedback
	if status != "":
		text += "\n%s" % status
	_node_desc.text = text


func _refresh_summary() -> void:
	var names: Array[String] = []
	for p in controller.selected_loadout:
		names.append(controller._shop_name(String(p), "weapon"))
	var growth: String = controller.growth.progress_short()
	if controller.growth.perk_ids.size() > 0:
		growth += " · 艺%d" % controller.growth.perk_ids.size()
	var imp: int = controller.mastery.imprint_total()
	if imp > 0:
		growth += " · 铭%d" % imp
	_summary.text = "武器：%s\n成长：%s\n护符：%d/%d" % [
		" / ".join(names) if not names.is_empty() else "无",
		growth,
		controller.selected_charms.size(), controller._loadout_system.cat_max("passive")]


# ---------------------------------------------------------------------------
# 输入：掷骰 / 继续 / 悬停 / 选择落点
# ---------------------------------------------------------------------------

func _on_advance() -> void:
	if board == null or _moving or _stepping or not _pending_node.is_empty():
		return
	if board.current_is_boss():
		return
	if board.dice == 0:
		var r: int = board.roll_dice()
		if r <= 0:
			return
		refresh()
	await _step_once()


# 走一格：唯一去路自动前进；分支处只高亮，等玩家点击。
func _step_once() -> void:
	if board == null or _moving or _stepping or not _pending_node.is_empty():
		return
	_stepping = true
	var legal: Array = board.legal_targets()
	if legal.is_empty():
		_stepping = false
		refresh()
		return
	if legal.size() > 1:
		_stepping = false
		refresh()
		return
	await get_tree().create_timer(STEP_SEC).timeout
	_stepping = false
	if not visible or board == null or _moving:
		return
	_advance_to(String(legal[0]["id"]))


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
	if _moving or _stepping or not _pending_node.is_empty() or board.dice <= 0:
		return
	for n in board.legal_targets():
		if String(n["id"]) == id:
			if controller._journal != null:
				controller._journal.note_first_pick(id)   # G5 工具：首次手动落点用时
			_advance_to(id)
			return


func _advance_to(id: String) -> void:
	if _moving or _stepping or board == null:
		return
	var node: Dictionary = board.advance_to(id)
	if node.is_empty():
		return
	if controller._journal != null:
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
	# 落点效果只在移动动画结束后执行一次；重复点击不会再次进入。
	# 战斗节点先弹确认，由玩家点击后再开打。
	if String(node.get("type", "")) in ["normal", "elite", "boss"]:
		_show_battle_confirm(node)
	else:
		controller._on_board_node_entered(node)


# 战斗确认：展示敌人、预览 HP/攻/属性与特殊机制；不提供取消（节点已消耗，不能跳过）。
func _show_battle_confirm(node: Dictionary) -> void:
	if node.is_empty():
		return
	_pending_node = node
	_selected_id = String(node.get("id", ""))
	var kind := String(node.get("type", "normal"))
	_confirm_title.text = {"normal": "遭遇战", "elite": "精英战", "boss": "BOSS 战"}.get(kind, "战斗")
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
			bits.append("特殊机制")
	if board != null and board.dice > 0:
		bits.append("战后剩余 %d 步" % board.dice)
	_confirm_stats.text = "\n".join(bits)
	_confirm_btn.text = "挑战 BOSS" if kind == "boss" else "进入战斗"
	_confirm_layer.visible = true
	refresh()


func _on_confirm_battle() -> void:
	if _pending_node.is_empty():
		return
	var node := _pending_node
	_pending_node = {}
	_confirm_layer.visible = false
	controller._on_board_node_entered(node)
