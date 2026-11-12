extends SceneTree
## 临时：加载战斗场景，截取转轮区域，验证符号图标是否生效。

const OUT := "res://.workbuddy/art_trials/icons/battle_%d.png"
const MARKS := [70, 200, 225, 250, 280]

var _f := 0
var _scene: Node = null


func _initialize() -> void:
	_scene = load("res://scenes/duel/duel.tscn").instantiate()
	root.add_child(_scene)


var _started := false


func _process(_delta: float) -> bool:
	_f += 1
	if _f == 195 and _scene.get("hud") != null:
		_scene.hud.reel_clicked.emit(0)
		print("spin started")

	if _f == 90 and not _started:
		_started = true
		if _scene.has_method("_confirm_loadout"):
			_scene._confirm_loadout()
			print("confirmed loadout")
	if _f in MARKS:
		var img: Image = root.get_texture().get_image()
		img.save_png(OUT % _f)
		print("shot ", _f, " ", img.get_width(), "x", img.get_height())
	if _f > MARKS[-1]:
		return true
	return false
