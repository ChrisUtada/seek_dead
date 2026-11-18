extends Control

# ============================================================================
# BranchScreen — 分岔路线图 UI（2026-11-18，L2-C）
# 480×270 全屏，画 7 层 DAG（层×候选节点 + 连线），点击下一层节点前进。
# 与 board_screen（14×9 网格）并列，由 BattleHud 按 board.branch_mode 选择显示。
# 节点结算全部委托 controller._on_board_node_entered(node)（与地图拓扑无关）。
# ============================================================================

const Palette = preload("res://scripts/ui/palette.gd")

const VIEW := Vector2(480.0, 270.0)
const TOP_RECT := Rect2(4.0, 3.0, 472.0, 20.0)
const MAP_RECT := Rect2(8.0, 30.0, 320.0, 220.0)
const INFO_RECT := Rect2(334.0, 30.0, 142.0, 220.0)
const FOOT_RECT := Rect2(8.0, 252.0, 464.0, 16.0)

# 节点颜色（按类型）
const COLORS := {
	"battle": Color(0.82, 0.90, 0.82), "elite": Color(0.96, 0.82, 0.78),
	"boss": Color(0.85, 0.82, 0.98), "chest": Color(0.98, 0.94, 0.72),
	"armory": Color(0.92, 0.86, 0.72), "shop": Color(0.78, 0.88, 0.96),
	"rest": Color(0.78, 0.92, 0.88), "event": Color(0.98, 0.88, 0.72),
	"start": Color(0.90, 0.90, 0.88),
}
const ICONS := {
	"battle": "⚔", "elite": "★", "boss": "👑", "chest": "🎁",
	"armory": "🏛", "shop": "🛒", "rest": "🔥", "event": "⛩", "start": "🚩",
}
const NODE_W := 66.0
const NODE_H := 22.0

var controller
var hud
var board = null
var _art: Control = null
var _buttons: Array[Button] = []
var _confirm_layer: Control = null
var _pending_node: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = VIEW
	mouse_filter = Control.MOUSE_FILTER_STOP
	_art = Control.new()
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.draw.connect(_draw_screen)
	add_child(_art)
	_layout_art()


func configure(ctrl, h: BattleHud) -> void:
	controller = ctrl
	hud = h


func _layout_art() -> void:
	if _art == null:
		return
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)


# ---------- 显隐 ----------

func show_board(board_sys) -> void:
	board = board_sys
	_pending_node = {}
	_selected_id = ""
	_apply_act_theme()
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

# 层 y：从地图面板顶部往下均分（7 层）
func _layer_y(layer: int, total_layers: int) -> float:
	var usable: float = MAP_RECT.size.y - NODE_H - 8.0
	var step: float = usable / float(maxi(1, total_layers - 1))
	return MAP_RECT.position.y + 4.0 + float(layer) * step


# 节点 x：同层节点水平均分居中
func _node_rect(n: Dictionary, layer: int, count_in_layer: int, index_in_layer: int) -> Rect2:
	var total_w: float = float(count_in_layer) * NODE_W + float(maxi(0, count_in_layer - 1)) * 8.0
	var x0: float = MAP_RECT.position.x + (MAP_RECT.size.x - total_w) / 2.0
	var x: float = x0 + float(index_in_layer) * (NODE_W + 8.0)
	return Rect2(x, _layer_y(layer, 7), NODE_W, NODE_H)


# 按层分组节点（保持 id 顺序）
func _nodes_by_layer() -> Dictionary:
	var out: Dictionary = {}
	if board == null:
		return out
	for n in board.nodes:
		var layer: int = int(String(n["id"]).substr(1, 1))
		if not out.has(layer):
			out[layer] = []
		out[layer].append(n)
	return out


func _node_layer(n: Dictionary) -> int:
	return int(String(n["id"]).substr(1, 1))


# ---------- 绘制 ----------

func _draw_screen() -> void:
	# 背景 + 顶栏 + 信息栏（即使 board 为空也画骨架）
	_art.draw_rect(Rect2(Vector2.ZERO, VIEW), Color(0.07, 0.08, 0.10))
	_art.draw_rect(TOP_RECT, Color(0.12, 0.14, 0.18))
	_art.draw_rect(INFO_RECT, Color(0.12, 0.14, 0.18))
	_art.draw_rect(FOOT_RECT, Color(0.10, 0.11, 0.14))
	var font: Font = _font()
	_art.draw_string(font, Vector2(TOP_RECT.position.x + 6, TOP_RECT.position.y + 14),
		"第 %d 幕 · 分岔路线（%d 层）" % [board.act if board != null else 1, 7], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.95, 0.88, 0.60))
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
	# 底部提示
	_art.draw_string(font, Vector2(FOOT_RECT.position.x + 6, FOOT_RECT.position.y + 12),
		"点击高亮节点前进 · 只能沿连线走向下一层 · 不可回头", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.70, 0.72, 0.75))

	var layers: Dictionary = _nodes_by_layer()
	# 先画连线（节点中心 → 下一层节点中心）
	for layer in layers:
		for n in layers[layer]:
			var from: Vector2 = _node_center(n, layers)
			for nid in n.get("next", []):
				var target = board.node_by_id(nid)
				if target == null:
					continue
				var to: Vector2 = _node_center(target, layers)
				var col: Color = Color(0.55, 0.55, 0.55, 0.6)
				_art.draw_line(from, to, col, 1.0)
	# 再画节点底色块（文本由 Button 负责，避免字体重复）
	for layer in layers:
		var arr: Array = layers[layer]
		for i in range(arr.size()):
			var n: Dictionary = arr[i]
			var r: Rect2 = _node_rect(n, int(layer), arr.size(), i)
			var t: String = String(n.get("type", ""))
			var col: Color = COLORS.get(t, Color(0.9, 0.9, 0.9))
			if String(board.current_id) == String(n["id"]):
				col = col.darkened(0.25)
			_art.draw_rect(r, col)


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
			var b := Button.new()
			b.set_anchors_preset(Control.PRESET_TOP_LEFT)
			b.position = r.position
			b.size = r.size
			b.flat = true
			var t: String = String(n.get("type", ""))
			b.text = "%s %s" % [ICONS.get(t, "•"), String(n.get("title", t))]
			b.tooltip_text = "%s · %s" % [String(n.get("title", t)), String(n.get("desc", ""))]
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
				(child as Label).text = "挑战「%s」？" % String(node.get("title", "敌人"))
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
