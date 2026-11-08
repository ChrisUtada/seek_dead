extends PanelContainer
# symbol_tooltip.gd — 转轮格子悬停提示（2026-11-08 G8 从 battle_hud 拆出）
#
# 只负责「两行文本 + 面板外观 + 按格子定位并夹紧屏幕边界」；
# 文本内容（符号名/有效元素/克制关系/增益说明）仍由 BattleHud 读战斗状态后传入。
# 纯展示：不读写战斗状态、不消耗 RNG。

var title_label: Label
var detail_label: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.TOOLTIP_BG
	sb.border_color = Palette.PANEL_BORDER
	sb.set_border_width_all(Palette.BORDER_WIDTH)
	sb.set_corner_radius_all(Palette.PANEL_RADIUS)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	add_child(vb)
	title_label = _label("", TypeScale.META)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vb.add_child(title_label)
	detail_label = _label("", TypeScale.TINY)
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(detail_label)


func _label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	return l


# 在格子正上方显示；hud_rect 用于把提示夹在 HUD 边界内（传 BattleHud 的 global rect）。
func show_tip(title: String, detail: String, cell_rect: Rect2, hud_rect: Rect2) -> void:
	title_label.text = title
	detail_label.text = detail
	var tp := get_combined_minimum_size()
	var x := cell_rect.position.x - hud_rect.position.x
	x = clampf(x, 4.0, hud_rect.size.x - tp.x - 4.0)
	var y := cell_rect.position.y - hud_rect.position.y - tp.y - 4.0
	position = Vector2(x, y)
	visible = true


func hide_tip() -> void:
	visible = false
