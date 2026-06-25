extends CanvasLayer

signal start_game()
signal quit_game()

var _container: Control
var _title: Label
var _subtitle: Label
var _btn_start: ColorRect
var _btn_continue: ColorRect
var _btn_quit: ColorRect
var _anim: AnimationPlayer

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_container = Control.new()
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)
	_build_ui()
	_build_animation()
	_container.modulate = Color(1, 1, 1, 0)
	var t = create_tween()
	t.tween_property(_container, "modulate", Color(1, 1, 1, 1), 0.5)

func _build_ui():
	var bg = ColorRect.new()
	bg.size = Vector2(640, 360)
	bg.color = Color(0.08, 0.08, 0.12, 1)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.add_child(bg)

	_title = Label.new()
	_title.text = "SEEK DEAD"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.position = Vector2(0, 72)
	_title.size = Vector2(640, 48)
	_title.add_theme_color_override("font_color", Color(0.9, 0.15, 0.15))
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_title.add_theme_constant_override("outline_size", 4)
	_title.add_theme_font_size_override("font_size", 28)
	_container.add_child(_title)

	_subtitle = Label.new()
	_subtitle.text = "Godot 迁移可行性验证原型"
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtitle.position = Vector2(0, 120)
	_subtitle.size = Vector2(640, 24)
	_subtitle.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_subtitle.add_theme_constant_override("outline_size", 2)
	_subtitle.add_theme_font_size_override("font_size", 14)
	_container.add_child(_subtitle)

	_btn_start = _make_button("开始游戏", Vector2(240, 170), Color(0.6, 0.1, 0.1))
	_container.add_child(_btn_start)
	_btn_continue = _make_button("继续游戏", Vector2(240, 206), Color(0.15, 0.4, 0.15))
	_btn_continue.visible = SaveSystem.has_save()
	_container.add_child(_btn_continue)
	_btn_quit = _make_button("退出", Vector2(240, 242), Color(0.3, 0.3, 0.3))
	_container.add_child(_btn_quit)

func _make_button(text: String, pos: Vector2, color: Color) -> ColorRect:
	var btn = ColorRect.new()
	btn.position = pos
	btn.size = Vector2(160, 24)
	btn.color = color
	btn.mouse_filter = Control.MOUSE_FILTER_STOP

	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = Vector2(0, 0)
	label.size = Vector2(160, 24)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 1)
	label.add_theme_font_size_override("font_size", 14)
	btn.add_child(label)
	return btn

func _build_animation():
	_anim = AnimationPlayer.new()
	add_child(_anim)

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mpos = event.position
		if _rect_contains(_btn_start, mpos):
			SaveSystem.delete_save()
			SceneManager.fade_to_scene("res://scenes/game/game.tscn")
		if _rect_contains(_btn_continue, mpos) and _btn_continue.visible:
			SceneManager.fade_to_scene("res://scenes/game/game.tscn")
		if _rect_contains(_btn_quit, mpos):
			get_tree().quit()

func _rect_contains(node: ColorRect, point: Vector2) -> bool:
	return point.x >= node.position.x and point.x <= node.position.x + node.size.x \
		and point.y >= node.position.y and point.y <= node.position.y + node.size.y
