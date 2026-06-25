extends Node

var _transition: ColorRect
var _anim: AnimationPlayer

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer = CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_transition = ColorRect.new()
	_transition.size = Vector2(640, 360)
	_transition.color = Color(0, 0, 0, 0)
	_transition.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_transition)
	_anim = AnimationPlayer.new()
	layer.add_child(_anim)

func fade_to_scene(path: String, duration: float = 0.4):
	_transition.mouse_filter = Control.MOUSE_FILTER_STOP
	var t = create_tween()
	t.tween_property(_transition, "color", Color(0, 0, 0, 1), duration)
	t.tween_callback(func():
		get_tree().change_scene_to_file(path)
		await get_tree().process_frame
		var t2 = create_tween()
		t2.tween_property(_transition, "color", Color(0, 0, 0, 0), duration)
		t2.tween_callback(func(): _transition.mouse_filter = Control.MOUSE_FILTER_IGNORE)
	)
