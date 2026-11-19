extends Control

# ============================================================================
# BranchScreen — 分岔路线图 UI（唯一地图，2026-11-19）
# 480×270 全屏，画 N 层 DAG（层×候选节点 + 连线），滚动视口，点击下一层节点前进。
# 由 BattleHud 作为唯一地图屏显示（网格已删）。
# 节点结算全部委托 controller._on_board_node_entered(node)（与地图拓扑无关）。
# ============================================================================

const Palette = preload("res://scripts/ui/palette.gd")

const VIEW := Vector2(480.0, 270.0)
const TOP_RECT := Rect2(4.0, 3.0, 472.0, 20.0)
const MAP_RECT := Rect2(8.0, 30.0, 320.0, 220.0)
const INFO_RECT := Rect2(334.0, 30.0, 142.0, 220.0)
const FOOT_RECT := Rect2(8.0, 252.0, 464.0, 16.0)

# 节点强调色（按类型）— 深色底 + 鲜明边框/图标，文字统一亮白（2026-11-18 可读性优化）
# 底色统一用 NODE_BG，颜色只做边框/图标，避免浅底压浅字看不清。
const NODE_BG := Color("#1d1219")
const NODE_BG_CURRENT := Color("#3a2b31")
const NODE_TEXT := Color("#f2ead8")       # 亮白暖字（高对比）
const NODE_TEXT_DIM := Color("#8a7f74")   # 不可走节点弱化文字
const LINE_DIM := Color(0.32, 0.34, 0.37, 0.5)  # 非可选连线：压暗
const LINE_LIT := Color("#d5a33d")        # 可选连线：交互金高亮
const COLORS := {
	"battle": Color("#a4bc4d"), "elite": Color("#e35b50"),
	"boss": Color("#b98cff"), "chest": Color("#e3c84d"),
	"armory": Color("#c9a24d"), "shop": Color("#62a1c2"),
	"rest": Color("#5fc9a8"), "event": Color("#e09b4d"),
	"start": Color("#a99d89"),
}
const ICONS := {
	"battle": "⚔", "elite": "★", "boss": "👑", "chest": "🎁",
	"armory": "🏛", "shop": "🛒", "rest": "🔥", "event": "⛩", "start": "🚩",
}
const NODE_W := 92.0
const NODE_H := 22.0        # 滚动视口：节点恢复正常尺寸（不再压缩塞进一屏）
const LAYER_STEP := 30.0    # 每层行距（节点高 22 + 8 间距）
const VISIBLE_LAYERS := 7.0 # 视口可见层数（220px / 30px ≈ 7.3，取整 7）

var controller
var hud
var board = null
var _art: Control = null
var _buttons: Array[Button] = []
var _confirm_layer: Control = null
var _pending_node: Dictionary = {}
var _scroll_top: float = 0.0            # 视口顶部对应的层号（float，支持平滑滚动）
var _dragging: bool = false
var _drag_start_y: float = 0.0
var _drag_start_scroll: float = 0.0
var _jump_btn: Button = null            # 顶栏「跳到 BOSS」按钮


func _ready() -> void:
	custom_minimum_size = VIEW
	mouse_filter = Control.MOUSE_FILTER_STOP
	_art = Control.new()
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.draw.connect(_draw_screen)
	add_child(_art)
	_layout_art()
	# 顶栏「跳到 BOSS」快速跳转按钮（滚动视口下方便直接看幕底）
	_jump_btn = Button.new()
	_jump_btn.text = "👑 BOSS"
	_jump_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_jump_btn.position = Vector2(TOP_RECT.position.x + TOP_RECT.size.x - 62.0, TOP_RECT.position.y + 1.0)
	_jump_btn.size = Vector2(58.0, 18.0)
	_jump_btn.add_theme_font_size_override("font_size", 9)
	_jump_btn.pressed.connect(_on_jump_boss)
	add_child(_jump_btn)


func _on_jump_boss() -> void:
	_center_on_layer(_total_layers() - 1)
	_apply_scroll()


func configure(ctrl, h: BattleHud) -> void:
	controller = ctrl
	hud = h


func _layout_art() -> void:
	if _art == null:
		return
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)


# 6.x 信息隐藏：普通战节点不公开具体敌人身份（地图显示"战斗"），进战斗才揭示。
# 精英/BOSS/其它节点保留具体名（可针对性构筑，是玩家规划路线的依据）。
func _display_title(n: Dictionary, t: String) -> String:
	if t == "battle":
		return "战斗"
	return String(n.get("title", t))


# ---------- 显隐 ----------

func show_board(board_sys) -> void:
	board = board_sys
	_pending_node = {}
	_selected_id = ""
	_apply_act_theme()
	# 首次打开：视口定位到当前层（玩家一进来就看到自己所在位置 + 后续路径）
	var cur_layer: int = _parse_layer(String(board.current_id))
	_center_on_layer(cur_layer)
	_rebuild_buttons()
	visible = true
	if hud != null:
		hud.hide()
	if _art != null:
		_art.queue_redraw()
	_refresh_info()


func hide_board(show_hud: bool = false) -> void:
	visible = false
	if _confirm_layer != null:
		_confirm_layer.visible = false
	if show_hud and hud != null:
		hud.show()
		hud._refresh_meta()


func refresh() -> void:
	# 若当前层已滚出视口，自动跟随（只在前进一步跨出视口时触发，不打断手动浏览）
	if board != null:
		var cur_layer: int = _parse_layer(String(board.current_id))
		if float(cur_layer) < _scroll_top or float(cur_layer) > _scroll_top + VISIBLE_LAYERS:
			_center_on_layer(cur_layer)
	_rebuild_buttons()
	if _art != null:
		_art.queue_redraw()
	_refresh_info()


func _apply_act_theme() -> void:
	# 顶栏配色沿用 Palette 的幕主题（无则默认）
	pass


func _font() -> Font:
	return get_theme_default_font()


var _selected_id: String = ""


# ---------- 布局计算 ----------

# 从 id（形如 b14_2）解析层号，支持两位数层号
static func _parse_layer(id: String) -> int:
	var head: String = id.split("_")[0]
	return head.trim_prefix("b").to_int()


# 总层数（从 board.layout.rows 读，默认 15）
func _total_layers() -> int:
	if board != null:
		return int(board.layout.get("rows", 15)) if board.layout.has("rows") else 15
	return 15


# 层 y：基于滚动视口（只显示 VISIBLE_LAYERS 层，其余通过滚动查看）
func _layer_y(layer: int, _total_layers: int) -> float:
	return MAP_RECT.position.y + 4.0 + (float(layer) - _scroll_top) * LAYER_STEP


# 节点 x：同层节点水平均分居中
func _node_rect(n: Dictionary, layer: int, count_in_layer: int, index_in_layer: int) -> Rect2:
	var total_w: float = float(count_in_layer) * NODE_W + float(maxi(0, count_in_layer - 1)) * 8.0
	var x0: float = MAP_RECT.position.x + (MAP_RECT.size.x - total_w) / 2.0
	var x: float = x0 + float(index_in_layer) * (NODE_W + 8.0)
	return Rect2(x, _layer_y(layer, _total_layers()), NODE_W, NODE_H)


# 按层分组节点（保持 id 顺序）
func _nodes_by_layer() -> Dictionary:
	var out: Dictionary = {}
	if board == null:
		return out
	for n in board.nodes:
		var layer: int = _parse_layer(String(n["id"]))
		if not out.has(layer):
			out[layer] = []
		out[layer].append(n)
	return out


func _node_layer(n: Dictionary) -> int:
	return _parse_layer(String(n["id"]))


# ---------- 滚动视口 ----------

func _max_scroll() -> float:
	var total: float = float(_total_layers())
	return maxf(0.0, total - VISIBLE_LAYERS)


func _clamp_scroll() -> void:
	_scroll_top = clampf(_scroll_top, 0.0, _max_scroll())


# 把某层定位到视口中间偏上（玩家看到"当前 + 后续路径"）
func _center_on_layer(layer: int) -> void:
	_scroll_top = float(layer) - VISIBLE_LAYERS * 0.4
	_clamp_scroll()


func _apply_scroll() -> void:
	_clamp_scroll()
	# 重新定位按钮（_draw_screen 由 queue_redraw 触发）
	for b in _buttons:
		var layer: int = int(b.get_meta("layer", 0))
		var idx: int = int(b.get_meta("idx", 0))
		var cnt: int = int(b.get_meta("cnt", 1))
		b.position = _node_rect({"id": "b%d_%d" % [layer, idx]}, layer, cnt, idx).position
	if _art != null:
		_art.queue_redraw()


# 滚轮滚动（地图区域内）
func _on_scroll(amount: float) -> void:
	_scroll_top += amount
	_apply_scroll()


# 输入：滚轮滚动 + 拖拽平移。按钮点击由 Button 自身处理（未拖动时不干扰）。
func _input(event: InputEvent) -> void:
	if not visible or (_confirm_layer != null and _confirm_layer.visible):
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			if MAP_RECT.has_point(mb.position):
				_on_scroll(-1.0)
				get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			if MAP_RECT.has_point(mb.position):
				_on_scroll(1.0)
				get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and MAP_RECT.has_point(mb.position):
				_dragging = true
				_drag_start_y = mb.position.y
				_drag_start_scroll = _scroll_top
			elif not mb.pressed and _dragging:
				_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var dy: float = mm.position.y - _drag_start_y
		_scroll_top = _drag_start_scroll - dy / LAYER_STEP
		_apply_scroll()
		get_viewport().set_input_as_handled()


# ---------- 绘制 ----------

func _draw_screen() -> void:
	# 背景 + 顶栏 + 信息栏（即使 board 为空也画骨架）
	_art.draw_rect(Rect2(Vector2.ZERO, VIEW), Color(0.07, 0.08, 0.10))
	_art.draw_rect(TOP_RECT, Color(0.12, 0.14, 0.18))
	_art.draw_rect(INFO_RECT, Color(0.12, 0.14, 0.18))
	_art.draw_rect(FOOT_RECT, Color(0.10, 0.11, 0.14))
	var font: Font = _font()
	_art.draw_string(font, Vector2(TOP_RECT.position.x + 6, TOP_RECT.position.y + 14),
		"第 %d 幕 · 分岔路线（%d 层）" % [board.act if board != null else 1, _total_layers()], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.95, 0.88, 0.60))
	if board == null or not visible:
		return

	# 顶栏右侧：提前公开的 BOSS
	var boss_node: Dictionary = {}
	for n in board.nodes:
		if String(n.get("type", "")) == "boss":
			boss_node = n
			break
	var boss_name: String = String(boss_node.get("title", "?"))
	var boss_elem: String = ""
	if boss_node.get("room") != null:
		boss_elem = String(boss_node["room"].element)
	_art.draw_string(font, Vector2(TOP_RECT.position.x + 250, TOP_RECT.position.y + 14),
		"👑 %s [%s]" % [boss_name, boss_elem], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.80, 0.98))

	# 信息栏：当前位置 + 可选目标 + 战果提示
	var cur: Dictionary = board.current_node()
	var lines := [
		"当前：%s" % String(cur.get("title", "-")),
		"可选：%d 个" % board.legal_targets().size(),
		"进度：%s" % board.progress_text(),
		"",
		String(board.feedback),
	]
	var y: float = INFO_RECT.position.y + 18
	for line in lines:
		_art.draw_string(font, Vector2(INFO_RECT.position.x + 6, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.85, 0.86, 0.88))
		y += 18.0
	var layers: Dictionary = _nodes_by_layer()
	# 视口裁剪范围（层号）
	var vlo: float = _scroll_top - 1.0
	var vhi: float = _scroll_top + VISIBLE_LAYERS + 1.0
	# 当前节点 → 下一层合法目标 id 集合（用于高亮可选连线）
	var legal_ids: Dictionary = {}
	for n in board.legal_targets():
		legal_ids[String(n["id"])] = true
	var cur_id: String = String(board.current_id)

	# 先画连线（节点中心 → 下一层节点中心），只画视口附近
	# 高亮规则：只有「当前节点 → 合法目标」的连线用交互金加粗，其余压暗 —— 一眼看出能往哪走
	for layer in layers:
		if float(layer) < vlo or float(layer) > vhi:
			continue
		for n in layers[layer]:
			var from: Vector2 = _node_center(n, layers)
			var is_from_cur: bool = String(n["id"]) == cur_id
			for nid in n.get("next", []):
				var target = board.node_by_id(nid)
				if target == null:
					continue
				var to: Vector2 = _node_center(target, layers)
				# 两端节点中心都必须在视口内才画（避免底栏边缘悬空线段）
				if not MAP_RECT.has_point(from) or not MAP_RECT.has_point(to):
					continue
				var lit: bool = is_from_cur and legal_ids.has(String(nid))
				if lit:
					_art.draw_line(from, to, LINE_LIT, 2.0)
				else:
					_art.draw_line(from, to, LINE_DIM, 1.0)
	# 再画节点底色块 + 类型色边框（文本由 Button 负责），视口外跳过
	for layer in layers:
		if float(layer) < vlo or float(layer) > vhi:
			continue
		var arr: Array = layers[layer]
		for i in range(arr.size()):
			var n: Dictionary = arr[i]
			var r: Rect2 = _node_rect(n, int(layer), arr.size(), i)
			# 节点必须完整落在地图视口内才画（避免最后一层被底部提示条压住）
			if not MAP_RECT.encloses(r):
				continue
			var t: String = String(n.get("type", ""))
			var accent: Color = COLORS.get(t, Color(0.9, 0.9, 0.9))
			var is_cur: bool = cur_id == String(n["id"])
			var is_legal: bool = legal_ids.has(String(n["id"]))
			# 深色底：当前节点略亮、可选节点稍提亮，其余最暗
			var bg: Color = NODE_BG
			if is_cur:
				bg = NODE_BG_CURRENT
			_art.draw_rect(r, bg)
			# 边框：合法目标=金色 2px（指引下一步），其余=类型色 1px
			if is_legal or is_cur:
				_draw_rect_border(r, LINE_LIT if is_legal else accent, 2.0)
			else:
				_draw_rect_border(r, accent, 1.0)
			# L2 修复：节点文字改由 _art 与边框同帧绘制（Button 只做热区）。
			# 避免 Button theme 在缩放/重建后偶发不渲染文字（"第二次开局文字消失"）。
			var tname: String = _display_title(n, t)
			var label: String = "%s %s" % [ICONS.get(t, "•"), tname]
			_art.draw_string(font, Vector2(r.position.x + 5, r.position.y + r.size.y - 6),
				label, HORIZONTAL_ALIGNMENT_LEFT, NODE_W - 10, 10,
				NODE_TEXT if is_legal or is_cur else NODE_TEXT_DIM)

	# 底部提示（画在节点之上，加深色底衬避免与节点文字重叠看不清）
	_art.draw_rect(FOOT_RECT, Color(0.10, 0.11, 0.14, 0.95))
	_art.draw_string(font, Vector2(FOOT_RECT.position.x + 6, FOOT_RECT.position.y + 12),
		"滚轮/拖拽切屏 · 点击高亮节点前进 · 沿连线走向下一层 · 不可回头", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.78, 0.80, 0.83))

	# 视口右侧滚动条（指示当前看到整条路线的哪一段）
	var total: float = float(_total_layers())
	if total > VISIBLE_LAYERS:
		var bar_x: float = MAP_RECT.position.x + MAP_RECT.size.x + 3.0
		var bar_h: float = MAP_RECT.size.y
		_art.draw_rect(Rect2(bar_x, MAP_RECT.position.y, 3.0, bar_h), Color(0.25, 0.27, 0.30))
		var thumb_h: float = bar_h * (VISIBLE_LAYERS / total)
		var thumb_y: float = MAP_RECT.position.y + (_scroll_top / maxf(1.0, _max_scroll())) * (bar_h - thumb_h)
		_art.draw_rect(Rect2(bar_x, thumb_y, 3.0, thumb_h), Color(0.85, 0.78, 0.50))


func _draw_rect_border(r: Rect2, c: Color, w: float) -> void:
	_art.draw_line(Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), c, w)
	_art.draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), c, w)
	_art.draw_line(Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y), c, w)
	_art.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.position.y), c, w)


func _node_center(n: Dictionary, layers: Dictionary) -> Vector2:
	var layer: int = _node_layer(n)
	var arr: Array = layers.get(layer, [])
	var idx: int = 0
	for i in range(arr.size()):
		if String(arr[i]["id"]) == String(n["id"]):
			idx = i
			break
	var r: Rect2 = _node_rect(n, layer, arr.size(), idx)
	return r.position + r.size / 2.0


# ---------- 按钮（点击热区）----------

func _rebuild_buttons() -> void:
	for b in _buttons:
		b.queue_free()
	_buttons.clear()
	if board == null:
		return
	var layers: Dictionary = _nodes_by_layer()
	var legal: Array = board.legal_targets()
	var legal_ids: Array = []
	for n in legal:
		legal_ids.append(String(n["id"]))
	for layer in layers:
		var arr: Array = layers[layer]
		for i in range(arr.size()):
			var n: Dictionary = arr[i]
			var r: Rect2 = _node_rect(n, int(layer), arr.size(), i)
			if not MAP_RECT.encloses(r):
				continue
			var b := Button.new()
			b.set_anchors_preset(Control.PRESET_TOP_LEFT)
			b.position = r.position
			b.size = r.size
			# L2 修复：文字由 _art 与边框同帧绘制，Button 退化为纯点击热区（text 留空），
			# 彻底避开 Button theme 在缩放/重建后偶发不渲染文字的问题。
			b.set_meta("layer", int(layer))
			b.set_meta("idx", i)
			b.set_meta("cnt", arr.size())
			var t: String = String(n.get("type", ""))
			b.tooltip_text = "%s · %s" % [_display_title(n, t), String(n.get("desc", ""))]
			b.disabled = not legal_ids.has(String(n["id"]))
			b.pressed.connect(_on_node_pressed.bind(String(n["id"])))
			add_child(b)
			_buttons.append(b)


func _on_node_pressed(id: String) -> void:
	if board == null:
		return
	var node: Dictionary = board.node_by_id(id)
	if node.is_empty():
		return
	var t: String = String(node.get("type", ""))
	# 精英/BOSS 先确认，避免误点开战
	if t in ["elite", "boss"]:
		_pending_node = node
		_show_confirm(node)
		return
	_enter_node(id)


func _enter_node(id: String) -> void:
	if board == null:
		return
	var node: Dictionary = board.advance_to(id)
	if node.is_empty():
		return
	refresh()
	controller._on_board_node_entered(node)


# ---------- 战斗确认层 ----------

func _show_confirm(node: Dictionary) -> void:
	if _confirm_layer == null:
		_confirm_layer = _make_confirm_layer()
	if _confirm_layer == null:
		_enter_node(String(_pending_node.get("id", "")))
		return
	for child in _confirm_layer.get_children():
		if child is Label:
			var t: String = String(child.name)
			if t == "Title":
				(child as Label).text = "挑战「%s」？" % _display_title(node, String(node.get("type", "")))
			elif t == "Desc":
				(child as Label).text = String(node.get("desc", ""))
	_confirm_layer.visible = true


func _make_confirm_layer() -> Control:
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var panel := Panel.new()
	panel.position = Vector2(90, 80)
	panel.size = Vector2(300, 110)
	layer.add_child(panel)
	var title := Label.new()
	title.name = "Title"
	title.position = Vector2(105, 92)
	title.size = Vector2(270, 24)
	panel.add_child(title)
	var desc := Label.new()
	desc.name = "Desc"
	desc.position = Vector2(15, 26)
	desc.size = Vector2(270, 24)
	panel.add_child(desc)
	var yes := Button.new()
	yes.text = "挑战"
	yes.position = Vector2(30, 70)
	yes.size = Vector2(100, 26)
	yes.pressed.connect(_on_confirm_yes)
	panel.add_child(yes)
	var no := Button.new()
	no.text = "返回"
	no.position = Vector2(170, 70)
	no.size = Vector2(100, 26)
	no.pressed.connect(_on_confirm_no)
	panel.add_child(no)
	add_child(layer)
	return layer


func _on_confirm_yes() -> void:
	if _confirm_layer != null:
		_confirm_layer.visible = false
	_enter_node(String(_pending_node.get("id", "")))


func _on_confirm_no() -> void:
	if _confirm_layer != null:
		_confirm_layer.visible = false
	_pending_node = {}


# ---------- 右侧信息 ----------

func _refresh_info() -> void:
	# 信息栏在 _draw_screen 里绘制，这里只触发重绘
	if _art != null:
		_art.queue_redraw()
