extends SceneTree
## 临时自检：确认 camp_fx 能构建、音频流能加载并进入播放状态。

var _fx: Node = null
var _f := 0


func _initialize() -> void:
	_fx = load("res://scripts/ui/camp_fx.gd").new()
	root.add_child(_fx)


func _process(_delta: float) -> bool:
	_f += 1
	if _f == 10:
		_fx.start_ambience()
	if _f == 30:
		var p: AudioStreamPlayer = _fx._fire_sfx
		print("stream=", p.stream, " len=", p.stream.get_length(), " loop=", p.stream.loop, " playing=", p.playing, " db=", p.volume_db)
		_fx.stop_ambience()
		print("after stop playing=", p.playing)
		return true
	return false
