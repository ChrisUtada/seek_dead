# screen.gd — 屏幕脚手架辅助（Phase 1 组件化）
#
# 把 duel_controller.gd 中重复 4+ 套的「背景 ColorRect + MarginContainer + 根 VBox」
# 收成统一函数，消除样板、保证各屏布局一致。
# 仅做结构搭建，不改任何战斗逻辑/数据。
#
# 用法：在调用方 const Screen = preload("res://scripts/ui/screen.gd")，
# 然后 Screen.build_scaffold(...)。本文件不声明 class_name，避免与调用方常量同名冲突。

extends RefCounted

# 构建「满屏背景 + MarginContainer + 根 VBox」并返回根 VBox（调用方继续 add_child）。
# margins: {"l":, "r":, "t":, "b":} 四边内边距；separation: 根 VBox 子项间距。
static func build_scaffold(parent: Control, bg_color: Color, margins: Dictionary, separation: int = 6) -> VBoxContainer:
	var bg := ColorRect.new()
	bg.color = bg_color
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", margins.get("l", 10))
	margin.add_theme_constant_override("margin_right", margins.get("r", 10))
	margin.add_theme_constant_override("margin_top", margins.get("t", 8))
	margin.add_theme_constant_override("margin_bottom", margins.get("b", 8))
	parent.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", separation)
	margin.add_child(root)
	return root


# 覆盖层专用：满屏背景 + CenterContainer + 居中 VBox，返回该 VBox。
static func build_centered(parent: Control, bg_color: Color, separation: int = 18) -> VBoxContainer:
	var bg := ColorRect.new()
	bg.color = bg_color
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(bg)

	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(c)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	c.add_child(v)
	return v
