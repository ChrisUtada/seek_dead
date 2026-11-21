extends Control
class_name CodexPanel

# S5-2 独立图鉴组件：从 anvil_screen 解耦，数据只读 controller._codex（不复制数据逻辑）。
# 自带「📖 图鉴」按钮 + 全屏详情面板；按钮挂到 host 容器（调用方指定，绝不依赖 roll_btn）。
# 铸式 / 来源 / 使用记录 / 已拥有状态由 CodexSystem.detail_lines 提供，迁移不丢功能。

var controller
var _btn: Button = null
var _panel: PanelContainer = null
var _list: VBoxContainer = null
var _detail: VBoxContainer = null
var _kind := "weapon"
var _sel := ""

# host：承载「图鉴」按钮的容器（由调用方传入，例如 meta_screen 的 Margin/Content）
func configure(ctrl, host: Node) -> void:
	controller = ctrl
	_build(host)

func get_button() -> Button:
	return _btn

func is_open() -> bool:
	return _panel != null and _panel.visible

func open() -> void:
	if _panel == null: return
	_panel.visible = true
	_refresh()

func close() -> void:
	if _panel != null:
		_panel.visible = false

func toggle() -> void:
	if is_open(): close()
	else: open()

func _build(host: Node) -> void:
	if _panel != null:
		return
	_btn = Button.new()
	_btn.text = "📖 图鉴"
	_btn.custom_minimum_size = Vector2(78, 40)
	_btn.add_theme_font_size_override("font_size", 9)
	_btn.tooltip_text = "查看装备路线 / 机制 / 真实来源 / 使用次数 / 最高熟练 / 铭印"
	_btn.pressed.connect(toggle)
	if host != null:
		host.add_child(_btn)

	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.z_index = 10   # 相对宿主 Control；meta_screen 根 z_index=90，面板盖住其内容即可
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.PANEL_BG
	sb.border_color = Palette.ACCENT_GOLD
	sb.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", sb)
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
	var close_btn := Button.new()
	close_btn.text = "✕ 关闭"
	close_btn.add_theme_font_size_override("font_size", 9)
	close_btn.pressed.connect(close)
	head.add_child(close_btn)
	root.add_child(head)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	var tab_labels := {"weapon": "武器", "skill": "技能", "passive": "护符", "active": "消耗品"}
	for k in ["weapon", "skill", "passive", "active"]:
		var b := Button.new()
		b.text = String(tab_labels[k])
		b.add_theme_font_size_override("font_size", 9)
		b.pressed.connect(_set_kind.bind(String(k)))
		tabs.add_child(b)
	root.add_child(tabs)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(168, 0)
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 1)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(_list)
	body.add_child(left_scroll)
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 2)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(_detail)
	body.add_child(right_scroll)
	root.add_child(body)

	margin.add_child(root)
	_panel.add_child(margin)
	add_child(_panel)
	_panel.visible = false

func _set_kind(kind: String) -> void:
	_kind = kind
	_sel = ""
	_refresh()

func _refresh() -> void:
	if _list == null or controller == null or controller._codex == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var entries: Array = controller._codex.list_entries(_kind)
	var owned := 0
	for e in entries:
		if bool(e.get("owned", false)):
			owned += 1
	var head := Label.new()
	head.text = "已拥有 %d / %d" % [owned, entries.size()]
	head.add_theme_font_size_override("font_size", 9)
	head.add_theme_color_override("font_color", Palette.ACCENT_GOLD)
	_list.add_child(head)
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
		row.pressed.connect(_select.bind(String(e.get("path", ""))))
		_list.add_child(row)
	if _sel == "":
		for e in entries:
			if bool(e.get("owned", false)):
				_sel = String(e.get("path", ""))
				break
	_refresh_detail()

func _select(path: String) -> void:
	if path == "": return
	_sel = path
	_refresh_detail()

func _refresh_detail() -> void:
	if _detail == null: return
	for c in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()
	if _sel == "":
		var empty := Label.new()
		empty.text = "选择左侧装备查看详情"
		empty.add_theme_font_size_override("font_size", 9)
		empty.add_theme_color_override("font_color", Palette.MUTED)
		_detail.add_child(empty)
		return
	var title := Label.new()
	title.text = _name_of(_sel)
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", Palette.ACCENT_GOLD)
	_detail.add_child(title)
	for line in controller._codex.detail_lines(_sel):
		var l := Label.new()
		l.text = String(line)
		l.add_theme_font_size_override("font_size", 9)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(258, 0)
		_detail.add_child(l)

func _name_of(path: String) -> String:
	var res = load(path)
	if res is WeaponData: return String(res.weapon_name)
	if res is ItemData: return String(res.item_name)
	return path.get_file().get_basename()
