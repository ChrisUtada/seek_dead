extends SceneTree
# 临时截图工具：启动主场景，等若干帧后把画面存成 PNG 并退出。
# 用法：godot --path . --script tools/shoot.gd

var _f := 0
var _scene: Node
const SHOT_FRAME := 40


func _initialize() -> void:
	_scene = load("res://scenes/duel/duel.tscn").instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_f += 1
	if _f == 5:
		# 跳过整备：直接确认配装进入战斗
		var ctrl := _scene
		while ctrl != null and not ctrl.has_method("_confirm_loadout"):
			ctrl = ctrl.get_parent() if ctrl.get_parent() != null else null
		if ctrl != null:
			ctrl.call("_confirm_loadout")
			print("battle entered")
	if _f >= SHOT_FRAME:
		var img := root.get_texture().get_image()
		var dir := "res://.workbuddy/shots"
		DirAccess.make_dir_recursive_absolute(dir)
		var path := "%s/bar_%03d.png" % [dir, Time.get_ticks_msec() % 1000]
		img.save_png(path)
		print("SHOT_SAVED: ", path, " ", img.get_size())
		quit()
		return true
	return false
