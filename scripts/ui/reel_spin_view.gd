extends Control

# ReelSpinView — 转轮纵向滚动视觉（2026-10-30 UI 反馈）
# 仅旋转中覆盖在单个转轮格子上：把带子符号按节拍纵向滚动，停止后隐藏，由格子自身显示最终结果。
# 纯展示层：不推进 cursor、不改 grid、不参与结算；带子与节拍均从 ReelSystem 读取。
# 由 battle_hud._build_ui 作为每个 symbol_cell 的子节点创建（不注册 class_name）。
#
# 观感要点：SPACING=30 与 32px 图标基本等宽（仅重叠 2px 透明角），38px 窗口内
# 主要看到 1 个完整符号，上下相邻槽各露出约 4px 边缘；靠连续位移呈现滚动，
# 而不是靠堆叠多个大槽（旧 19px 槽距时代「同时看到 2 个符号」的结论已不适用）。
# 槽位覆盖方向按符号流动方向排列：索引大的槽在下（先滚出视野）。

const SLOTS := 5          # 滚动槽数量（覆盖 38px 窗口 + 上下各一格余量）
const SPACING := 30.0     # 相邻符号的中心距（符号图标 32px，30 只重叠 2px，都在透明角上）

var controller   # DuelController
var reel: int = 0

var _entries: Array[Control] = []
var _labels: Array[Label] = []
var _textures: Array[TextureRect] = []
var _index := 0
var _frac := 0.0
var _active := false
var _preview: Label = null   # M2-01 洞察：旋转中在格底显示下一格（滚动把格子文字清空后的替代展示）
# 2026-11-12 Step 2：停轮吸附。进度由 ReelSystem 的 tween 提供，本层只负责把视觉
# 从请求时的位置缓出到记录的落点；不写 grid、不改逻辑游标、不参与结算。
var _absorb_active := false
var _absorb_from := -1.0


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
		# 必须无条件隐藏：之前只在 _active 为真时才隐藏，导致停轮后若从未激活
		# （或 _active 被重置）就留下 5 个符号槽一直挂在格子里，和静止图标叠成一团。
		_active = false
		_absorb_active = false
		visible = false
		_preview.visible = false
		return
	# 停轮吸附：视觉缓出到请求时记录的落点，完成后由 ReelSystem 写格子并隐藏本层。
	if rs.has_method("is_absorbing") and rs.is_absorbing(reel):
		_render_absorb(rs)
		return
	_absorb_active = false
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
	_absorb_active = false
	_absorb_from = -1.0
	_active = true
	visible = true
	_fill(rs)
	_layout_entries()
	# 旋转期间格子自身隐藏文字；停止后由 _refresh_cell 写回最终结果
	var cell: Button = get_parent() as Button
	if cell != null:
		cell.text = ""
		cell.icon = null


# 停轮吸附：从请求时的连续位置缓出到 ReelSystem 记录的落点格。
# 进度由逻辑层的 tween 提供，因此 30/60/120fps 下停稳位置一致。
func _render_absorb(rs) -> void:
	var strip: Array = _strip(rs)
	var n: int = strip.size()
	if n <= 0:
		return
	if not _active:
		_activate(rs)
	if not _absorb_active:
		_absorb_from = float(_index) + _frac
		_absorb_active = true
	var target: int = rs.absorb_target(reel)
	if target < 0:
		return
	var p: float = clampf(rs.absorb_progress(reel), 0.0, 1.0)
	# 取最短有符号距离：落点与当前视觉位置通常相差 ≤0.5 格，避免绕整圈。
	var diff: float = fposmod(float(target) - _absorb_from, float(n))
	if diff > float(n) * 0.5:
		diff -= float(n)
	var eased: float = 1.0 - (1.0 - p) * (1.0 - p)
	var pos: float = _absorb_from + diff * eased
	var idx: int = floori(pos)
	_index = ((idx % n) + n) % n
	_frac = pos - float(idx)
	_fill(rs)
	_layout_entries()
	_preview.visible = false


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
		var entry: Array = strip[(_index + i - (SLOTS / 2) + n) % n]
		var sym: SymbolData = entry[0]
		var elem: String = String(entry[1]) if entry.size() > 1 else "none"
		var src: String = String(entry[2]) if entry.size() > 2 else ""
		var lbl := _labels[i]
		var tex := _textures[i]
		if sym.icon_tex != null:
			tex.texture = _reel_icon(sym.icon_tex, sym, elem, src)
			tex.visible = true
			lbl.visible = false
			lbl.text = ""
		else:
			tex.visible = false
			lbl.visible = true
			lbl.text = sym.label
			lbl.add_theme_color_override("font_color", sym.color)


## 滚动流与静止格使用同一份来源，旋转中和停下后都显示该格的完整武器图标。
func _reel_icon(base: Texture2D, s: SymbolData = null, elem: String = "none", source_id: String = "") -> Texture2D:
	if s != null and s.resource_path.ends_with("_slash.tres") and controller != null:
		var wid: String = source_id
		if wid == "":
			wid = String(controller._sym_src_map.get(s.resource_path + "|" + elem, ""))
		var wtex := WeaponIcons.cell_icon_for_id(wid)
		if wtex != null:
			return wtex
	if base == null:
		return null
	var p := base.resource_path
	if p == "" or not p.contains("/symbols/16/"):
		return base
	var big := p.replace("/symbols/16/", "/symbols/")
	return load(big) as Texture2D if ResourceLoader.exists(big) else base


func _layout_entries() -> void:
	var mid := float(SLOTS / 2)
	var pad := (size.y - SPACING) * 0.5   # 让「当前格」落在窗口正中，而不是贴着上沿
	for i in SLOTS:
		var e := _entries[i]
		e.position = Vector2(0, pad + (float(i) - mid - _frac) * SPACING)
		e.size = Vector2(size.x, SPACING)


# M2-01 洞察：旋转中格子文字被滚动视觉清空，下一格预览改由本层贴在格底显示。
func _sync_preview(rs) -> void:
	# 2026-11-12 Step 1：目盲隐藏格底预览（当前中心符号不受影响）。
	if controller.debuffs != null and controller.debuffs.preview_hidden():
		_preview.visible = false
		return
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
