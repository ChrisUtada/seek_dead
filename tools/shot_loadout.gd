extends SceneTree
## 临时截图工具：加载整备页 → 在三个时间点各截一张 → 退出。
## 用于核对「整数像素摆动」是否真的按 1px 跳格。

const OUT := "res://.workbuddy/art_trials/camp/shot_fx_%d.png"
const MARKS := [40, 75, 110]

var _frames := 0


func _initialize() -> void:
	var scene: Node = load("res://scenes/ui/loadout_scene.tscn").instantiate()
	root.add_child(scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames in MARKS:
		var img: Image = root.get_texture().get_image()
		img.save_png(OUT % _frames)
		print("shot ", _frames, " -> ", OUT % _frames)
	if _frames >= MARKS[-1] + 1:
		return true
	return false
