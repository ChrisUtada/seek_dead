extends Control

# ReelSpinView — 转轮纵向滚动视觉（2026-10-30 UI 反馈）
# 仅旋转中覆盖在单个转轮格子上：把带子符号按节拍纵向滚动，停止后隐藏，由格子自身显示最终结果。
# 纯展示层：不推进 cursor、不改 grid、不参与结算；带子与节拍均从 ReelSystem 读取。
# 由 battle_hud._build_ui 作为每个 symbol_cell 的子节点创建（不注册 class_name）。
#
# 观感要点：滚动槽间距（SPACING）小于格子高度（38），窗口里同时能看到 2 个符号——
# 只放 3 个与格子等高的大槽时，滚动中格心会空出来，看着像「符号跳动」而不是「转轮」。
# 槽位覆盖方向按符号流动方向排列：索引大的槽在下（先滚出视野）。

const SLOTS := 5          # 滚动槽数量（覆盖 38px 窗口 + 上下各一格余量）
const SPACING := 19.0     # 相邻符号的中心距（≈ 符号高度，与 38px 格同步）

var controller   # DuelController
var reel: int = 0

var _entries: Array[Control] = []
var _labels: Array[Label] = []
var _textures: Array[TextureRect] = []
var _index := 0
var _frac := 0.0
var _active := false
var _preview: Label = null   # M2-01 洞察：旋转中在格底显示下一格（滚动把格子文字清空后的替代展示）


func configure(ctrl, r: int) -> void:
	controller = ctrl
	reel = r
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in SLOTS:
		var e := Control.new()
		e.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(e)
		var lbl := Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		lbl.add_theme_font_size_override("font_size", TypeScale.SYMBOL)
		e.add_child(lbl)
		var tex := TextureRect.new()
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tex.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		tex.visible = false
		e.add_child(tex)
		_entries.append(e)
		_labels.append(lbl)
		_textures.append(tex)
	# 洞察预览：贴格子底边的小字（有洞察技艺时才显示）
	_preview = Label.new()
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview.add_theme_font_size_override("font_size", TypeScale.REEL)
	_preview.add_theme_color_override("font_color", Palette.ACCENT_GOLD)
	_preview.visible = false
	add_child(_preview)
	visible = false
	set_process(true)


# ReelSystem 每个逻辑节拍推进 1 格；视觉按同一节拍速度连续滚动，观感才像真转轮。
func _process(delta: float) -> void:
	if controller == null:
		return
	var rs = controller.reel_system
	if rs == null or not rs.spinning or _strip(rs).is_empty() or _reel_stopped(rs):
		if _active:
			_active = false
			visible = false
			_preview.visible = false
		return
	if not _active:
		_activate(rs)
	var wait: float = rs.current_spin_wait()
	if wait <= 0.0:
		wait = 0.06
	_frac += delta / wait
	var n: int = _strip(rs).size()
	while _frac >= 1.0:
		_frac -= 1.0
		_index = (_index + 1) % n
		_fill(rs)
	_layout_entries()
	_sync_preview(rs)


func _activate(rs) -> void:
	var strip: Array = _strip(rs)
	_index = int(rs.reel_cursor[reel]) % strip.size()
	_frac = 0.0
	_active = true
	visible = true
	_fill(rs)
	_layout_entries()
	# 旋转期间格子自身隐藏文字；停止后由 _refresh_cell 写回最终结果
	var cell: Button = get_parent() as Button
	if cell != null:
		cell.text = ""
		cell.icon = null


# P1 视觉落点：当前最靠近窗口中心的带子索引。
# 布局把槽位 i 放在 (i - mid - _frac)·SPACING，故中心 = _index + round(_frac)。
# 未激活时回落到逻辑游标，避免首帧按停取到上一局的陈旧视觉索引。
func center_index() -> int:
	if controller == null:
		return -1
	var rs = controller.reel_system
	if rs == null:
		return -1
	var strip: Array = _strip(rs)
	if strip.is_empty():
		return -1
	var n: int = strip.size()
	if not _active:
		if rs.reel_cursor.size() <= reel:
			return -1
		return int(rs.reel_cursor[reel]) % n
	return (_index + (1 if _frac >= 0.5 else 0)) % n


# P1 预览：从视觉中心之后取 count 个符号（不含中心本身）。
func next_symbols(count: int) -> Array:
	if controller == null:
		return []
	var rs = controller.reel_system
	if rs == null:
		return []
	return rs.next_symbols(reel, count, center_index())


func _fill(rs) -> void:
	var strip: Array = _strip(rs)
	var n: int = strip.size()
	for i in SLOTS:
		var sym: SymbolData = strip[(_index + i - (SLOTS / 2) + n) % n][0]
		var lbl := _labels[i]
		var tex := _textures[i]
		if sym.icon_tex != null:
			tex.texture = sym.icon_tex
			tex.visible = true
			lbl.visible = false
			lbl.text = ""
		else:
			tex.visible = false
			lbl.visible = true
			lbl.text = sym.label
			lbl.add_theme_color_override("font_color", sym.color)


func _layout_entries() -> void:
	var mid := float(SLOTS / 2)
	var pad := (size.y - SPACING) * 0.5   # 让「当前格」落在窗口正中，而不是贴着上沿
	for i in SLOTS:
		var e := _entries[i]
		e.position = Vector2(0, pad + (float(i) - mid - _frac) * SPACING)
		e.size = Vector2(size.x, SPACING)


# M2-01 洞察：旋转中格子文字被滚动视觉清空，下一格预览改由本层贴在格底显示。
func _sync_preview(rs) -> void:
	# P1 预览行开启时，下一格由 ReelDock 右侧独立行显示（洞察会在该行 +1 格），
	# 避免格底小字与预览行重复；control（预览 0）保持原洞察行为。
	if controller.readability != null and int(controller.readability.preview_slots) > 0:
		_preview.visible = false
		return
	if controller.growth == null or not controller.growth.has_perk("insight"):
		_preview.visible = false
		return
	var nxt = rs.next_symbol(reel)
	if nxt == null:
		_preview.visible = false
		return
	_preview.text = "▸" + nxt.label
	_preview.add_theme_color_override("font_color", nxt.color if nxt.icon_tex == null else Palette.ACCENT_GOLD)
	_preview.visible = true


func _strip(rs) -> Array:
	if rs.reel_strips.size() <= reel:
		return []
	return rs.reel_strips[reel]


func _reel_stopped(rs) -> bool:
	return rs.reel_stopped.size() <= reel or bool(rs.reel_stopped[reel])
