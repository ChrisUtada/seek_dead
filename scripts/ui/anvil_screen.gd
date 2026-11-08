extends Control
class_name AnvilScreen

# anvil_screen — 铁砧纯 gacha 覆盖层（§6 纯 gacha 定案：抽装备注入 owned_* 拥有池）
# 静态骨架由 anvil_screen.tscn 提供；本脚本负责显隐 / 填数据 / 摇按钮 / 旋转三连仪式动画。

var controller
var hud: BattleHud
const ANVIL_CELL = preload("res://scenes/ui/anvil_cell.tscn")

var _spinning := false
var _stop_all := false
const _SPIN_AUTO_STOP := 4.0   # 手动按停超时兜底（防软锁：不点也会停）

# G6-04 图鉴详情覆盖层（运行时构建，不改 anvil_screen.tscn）
var _codex_btn: Button = null
var _codex_panel: PanelContainer = null
var _codex_list: VBoxContainer = null
var _codex_detail: VBoxContainer = null
var _codex_kind := "weapon"
var _codex_sel := ""

@onready var bg = $Bg
@onready var title_label = $Margin/Content/TitleLabel
@onready var points_label = $Margin/Content/PointsLabel
@onready var sub_label = $Margin/Content/SubLabel
@onready var info_label = $Margin/Content/InfoLabel
@onready var reel_box = $Margin/Content/ReelBox
@onready var roll_btn = $Margin/Content/Bot/RollBtn
@onready var back_btn = $Margin/Content/Bot/BackBtn

func configure(ctrl, h: BattleHud) -> void:
	controller = ctrl
	hud = h
	bg.color = Palette.BG_ANVIL
	title_label.text = "🔨 铁砧 · 抽装备"
	sub_label.text = "消耗铁砧点数摇一次，单格揭晓一件装备（按停锁定落点）"
	# 摇/返回按钮为静态节点（anvil_screen.tscn），这里只填动态文案 + 接线
	roll_btn.text = "🔨 摇动 (%d点)" % controller.BALANCE.anvil_roll_cost
	roll_btn.connect("pressed", _on_roll_pressed)
	back_btn.connect("pressed", hud.anvil_back_requested.emit)
	_build_codex_ui()

func show_screen() -> void:
	refresh()
	visible = true

func refresh() -> void:
	# 旋转动画进行中：格子由 _play_spin 接管，此处不重绘，避免清掉转动中的标签
	if _spinning:
		return
	var meta = controller.state.meta
	var info = controller._anvil_system.collection_info()
	points_label.text = "铁砧点数: %d" % meta["anvil_points"]
	var pity = meta["anvil_pity"]
	var pity_txt = ""
	if info["not_yet"] > 0 and pity >= controller.BALANCE.anvil_pity_max:
		pity_txt = "（保底触发：下次必出未拥有）"
	info_label.text = "图鉴 %.0f%%  已拥有 %d / 全池 %d\n未拥有 %d 件 · 连续重复 %d/%d %s" % [
		info["pct"] * 100, info["owned"], info["total"], info["not_yet"], pity, controller.BALANCE.anvil_pity_max, pity_txt]
	for c in reel_box.get_children():
		reel_box.remove_child(c)
		c.queue_free()
	if controller._anvil_system.last_anvil_drops.is_empty():
		# 未摇过：单格显示问号，制造悬念
		reel_box.add_child(_make_placeholder())
	else:
		for d in controller._anvil_system.last_anvil_drops:
			reel_box.add_child(_make_cell(d))
func _on_roll_pressed() -> void:
	if _spinning:
		# 转动中：按钮变为「停止」，一键停止转轮
		_stop_all = true
		return
	if controller.meta["anvil_points"] < controller.BALANCE.anvil_roll_cost:
		sub_label.text = "铁砧点数不足，先去局内赚点数吧"
		return
	_spinning = true
	_stop_all = false
	roll_btn.text = "⏹ 停止"
	sub_label.text = "转动中…"
	controller._on_anvil_roll_pressed()  # 扣点 + 结算 + 写入 last_anvil_drops（单格结果）
	_play_spin(controller._anvil_system.last_anvil_drops)


func _input(event: InputEvent) -> void:
	# 空格/回车：一键停止转轮（按停便捷键）
	if _spinning and event.is_action_pressed("ui_accept"):
		_stop_all = true
		get_viewport().set_input_as_handled()


func _play_spin(final_drops: Array) -> void:
	# 清空旧格，建立单格转动（手动按停：点格子 / 停止按钮 / 空格）
	for c in reel_box.get_children():
		reel_box.remove_child(c)
		c.queue_free()
	var names = controller._anvil_system.collection_info()["names"]
	var final_d: Dictionary = final_drops[0] if final_drops.size() > 0 else {"kind": "blank"}
	var cell: AnvilCell = ANVIL_CELL.instantiate()
	reel_box.add_child(cell)
	sub_label.text = "点击格子 / 停止按钮（空格停止）"
	await _spin_cell(cell, names, final_d)
	_spinning = false
	roll_btn.text = "🔨 摇动 (%d点)" % controller.BALANCE.anvil_roll_cost
	sub_label.text = "消耗铁砧点数摇一次，单格揭晓装备（物品与稀有度随机）"
	refresh()  # 旋转收尾：用正式单元格重渲染（名称/稀有度/新获取标记）并刷新点数


func _spin_cell(cell: AnvilCell, names: Array, final_d: Dictionary) -> void:
	# 让格子可点：自身接收鼠标，子节点全部 IGNORE（点击穿透到 cell 本体）
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for n in cell.find_children("*", "Control", true, false):
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stopped := false
	var on_click := func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			stopped = true
	cell.gui_input.connect(on_click)
	var t := 0.0
	var step := 0.06
	while not stopped and t < _SPIN_AUTO_STOP:
		# 旋转中屏幕可能被关闭/重建（返回整备、run 重置等），标签已释放则直接退出协程，避免写已释放对象
		if not is_instance_valid(cell):
			return
		if _stop_all:
			stopped = true
		cell.configure(names[randi() % names.size()])
		t += step
		await get_tree().create_timer(step).timeout
	if not is_instance_valid(cell):
		return
	cell.gui_input.disconnect(on_click)
	cell.mouse_default_cursor_shape = Control.CURSOR_ARROW
	# 落定到本次真实结果
	if final_d.get("kind", "") == "blank":
		cell.configure("?")
	else:
		cell.configure(final_d.get("name", "?"))
func _make_placeholder() -> Control:
	var cell: AnvilCell = ANVIL_CELL.instantiate()
	cell.configure("?")
	return cell

func _make_cell(d: Dictionary) -> Control:
	var cell: AnvilCell = ANVIL_CELL.instantiate()
	if d.get("kind", "") == "blank":
		cell.configure("空白格")
	else:
		var tag = "✨ 新获取" if d.get("is_new", false) else "↺ 重复"
		cell.configure(d.get("name", "?"), "%s · %s" % [d.get("rarity", "?"), tag])
		var p: String = d.get("path", "")
		if p != "":
			cell.tooltip_text = ItemTooltip.for_resource(load(p))   # 物品悬停信息窗（ItemTooltip 生成器）
	return cell

# ---------------------------------------------------------------------------
# G6-04 图鉴详情：分类列表 + 详情（路线 / 机制 / 来源 / 使用 / 熟练 / 铭印）。
# 数据全部来自 CodexSystem（只读资源 + meta.codex / item_sources），本屏不改存档。
# ---------------------------------------------------------------------------
func _build_codex_ui() -> void:
	if _codex_panel != null:
		return
	_codex_btn = Button.new()
	_codex_btn.text = "📖 图鉴"
	_codex_btn.custom_minimum_size = Vector2(78, 40)
	_codex_btn.add_theme_font_size_override("font_size", 9)
	_codex_btn.tooltip_text = "查看装备路线 / 机制 / 真实来源 / 使用次数 / 最高熟练 / 铭印"
	_codex_btn.pressed.connect(_toggle_codex)
	var bot: Node = roll_btn.get_parent()
	bot.add_child(_codex_btn)
	bot.move_child(_codex_btn, 0)

	_codex_panel = PanelContainer.new()
	_codex_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_codex_panel.z_index = 60
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.PANEL_BG
	sb.border_color = Palette.ACCENT_GOLD
	sb.set_border_width_all(1)
	_codex_panel.add_theme_stylebox_override("panel", sb)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "📖 图鉴"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Palette.ACCENT_GOLD)
	head.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var close := Button.new()
	close.text = "✕ 关闭"
	close.add_theme_font_size_override("font_size", 9)
	close.pressed.connect(func() -> void: _codex_panel.visible = false)
	head.add_child(close)
	root.add_child(head)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	var tab_labels := {"weapon": "武器", "passive": "护符", "active": "消耗品"}
	for k in ["weapon", "passive", "active"]:
		var b := Button.new()
		b.text = String(tab_labels[k])
		b.add_theme_font_size_override("font_size", 9)
		b.pressed.connect(_set_codex_kind.bind(String(k)))
		tabs.add_child(b)
	root.add_child(tabs)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(168, 0)
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_codex_list = VBoxContainer.new()
	_codex_list.add_theme_constant_override("separation", 1)
	_codex_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(_codex_list)
	body.add_child(left_scroll)
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_codex_detail = VBoxContainer.new()
	_codex_detail.add_theme_constant_override("separation", 2)
	_codex_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(_codex_detail)
	body.add_child(right_scroll)
	root.add_child(body)

	margin.add_child(root)
	_codex_panel.add_child(margin)
	add_child(_codex_panel)
	_codex_panel.visible = false


func _toggle_codex() -> void:
	if _codex_panel == null:
		return
	_codex_panel.visible = not _codex_panel.visible
	if _codex_panel.visible:
		_refresh_codex()


func _set_codex_kind(kind: String) -> void:
	_codex_kind = kind
	_codex_sel = ""
	_refresh_codex()


func _refresh_codex() -> void:
	if _codex_list == null or controller._codex == null:
		return
	for c in _codex_list.get_children():
		_codex_list.remove_child(c)
		c.queue_free()
	var entries: Array = controller._codex.list_entries(_codex_kind)
	var owned := 0
	for e in entries:
		if bool(e.get("owned", false)):
			owned += 1
	var head := Label.new()
	head.text = "已拥有 %d / %d" % [owned, entries.size()]
	head.add_theme_font_size_override("font_size", 9)
	head.add_theme_color_override("font_color", Palette.ACCENT_GOLD)
	_codex_list.add_child(head)
	for e in entries:
		var row := Button.new()
		var mark := "✓" if bool(e.get("owned", false)) else "·"
		var txt := "%s %s" % [mark, String(e.get("name", ""))]
		if int(e.get("rank", 0)) > 0:
			txt += " R%d" % int(e["rank"])
		row.text = txt
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_theme_font_size_override("font_size", 9)
		row.custom_minimum_size = Vector2(158, 0)
		row.disabled = not bool(e.get("owned", false))
		row.tooltip_text = "使用 %d 次" % int(e.get("uses", 0))
		row.pressed.connect(_select_codex.bind(String(e.get("path", ""))))
		_codex_list.add_child(row)
	# 默认选中第一件已拥有，打开即有内容。
	if _codex_sel == "":
		for e in entries:
			if bool(e.get("owned", false)):
				_codex_sel = String(e.get("path", ""))
				break
	_refresh_codex_detail()


func _select_codex(path: String) -> void:
	if path == "":
		return
	_codex_sel = path
	_refresh_codex_detail()


func _refresh_codex_detail() -> void:
	if _codex_detail == null:
		return
	for c in _codex_detail.get_children():
		_codex_detail.remove_child(c)
		c.queue_free()
	if _codex_sel == "":
		var empty := Label.new()
		empty.text = "选择左侧装备查看详情"
		empty.add_theme_font_size_override("font_size", 9)
		empty.add_theme_color_override("font_color", Palette.MUTED)
		_codex_detail.add_child(empty)
		return
	var title := Label.new()
	title.text = _codex_name(_codex_sel)
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", Palette.ACCENT_GOLD)
	_codex_detail.add_child(title)
	for line in controller._codex.detail_lines(_codex_sel):
		var l := Label.new()
		l.text = String(line)
		l.add_theme_font_size_override("font_size", 9)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(258, 0)
		_codex_detail.add_child(l)


func _codex_name(path: String) -> String:
	var res = load(path)
	if res is WeaponData:
		return String(res.weapon_name)
	if res is ItemData:
		return String(res.item_name)
	return path.get_file().get_basename()


func hide_screen() -> void:
	visible = false
