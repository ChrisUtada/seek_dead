class_name AnvilCell
extends CenterContainer

# 铁砧三格卡片组件：静态结构在 anvil_cell.tscn（Panel + VBox + 两行 Label，样式可视化），
# 本脚本只填文本。消灭 anvil_screen 三份重复的 CenterContainer+PanelContainer 构造器。
# 样式统一用 Palette 硬边化值（CARD_BG / PANEL_BORDER / BORDER_WIDTH=2 / PANEL_RADIUS=0），
# 修复原 _play_spin 内联版 radius=6 的不一致。configure 在入树前调用，不依赖 @onready。

var _line1: Label
var _line2: Label


func _resolve() -> void:
	if _line1 != null:
		return
	_line1 = $Panel/VBox/Line1
	_line2 = $Panel/VBox/Line2


func configure(line1: String, line2: String = "") -> void:
	_resolve()
	_line1.text = line1
	_line2.text = line2
	_line2.visible = line2 != ""


# 铁砧格 tooltip 为 BBCode 富文本，需自定义 tooltip（内置不支持 BBCode）
func _make_custom_tooltip(for_text: String) -> Control:
	if for_text.is_empty():
		return null
	return ItemTooltip.tooltip_label(for_text)
