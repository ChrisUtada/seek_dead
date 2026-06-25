extends Node

var _transition: ColorRect
var _is_transitioning: bool = false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer = CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_transition = ColorRect.new()
	_transition.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_transition.color = Color(0, 0, 0, 0)
	_transition.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_transition)

func fade_to_scene(path: String, duration: float = 0.4):
	if _is_transitioning:
		return
	_is_transitioning = true
	_transition.mouse_filter = Control.MOUSE_FILTER_STOP

	var t = create_tween()
	t.tween_property(_transition, "color", Color(0, 0, 0, 1), duration)
	t.finished.connect(_on_fade_out.bind(path, duration))

func _on_fade_out(path: String, duration: float):
	_transition.color = Color(0, 0, 0, 1)
	get_tree().create_timer(0.0).timeout.connect(_on_swap.bind(path, duration))

func _on_swap(path: String, duration: float):
	_transition.color = Color(0, 0, 0, 1)
	get_tree().change_scene_to_file(path)
	get_tree().create_timer(0.0).timeout.connect(_on_fade_in.bind(duration))

func _on_fade_in(duration: float):
	var t = create_tween()
	t.tween_property(_transition, "color", Color(0, 0, 0, 0), duration)
	t.finished.connect(_end_transition)

func _end_transition():
	_is_transitioning = false
	_transition.mouse_filter = Control.MOUSE_FILTER_IGNORE
