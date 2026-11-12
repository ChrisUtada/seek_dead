extends SceneTree
## 临时演示：三张 ItemCard 的图标粒子（1px 火星），元素色不同。
## 运行：godot --path . --resolution 480x270 --script tools/demo_icon_fx.gd

const OUT := "res://.workbuddy/art_trials/icons/cardfx_%d.png"
const MARKS := [30, 55, 80, 105]
const ICON := "res://assets/icons/weapons/icon_ember_sword.png"

var _frames := 0


func _initialize() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.066, 0.086)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var scene: PackedScene = load("res://scenes/ui/item_card.tscn")
	var weapons := [
		"res://resources/weapon_templates/ember_sword.tres",
		"res://resources/weapon_templates/fire_sword.tres",
	]
	for i in weapons.size():
		var wd: Resource = load(weapons[i])
		var card: Button = scene.instantiate()
		card.position = Vector2(40 + i * 170, 70)
		card.custom_minimum_size = Vector2(120, 130)
		root.add_child(card)
		card.configure(String(wd.get("weapon_name")), "", 11)
		var ok := WeaponIcons.apply(card, weapons[i], String(wd.get("element")), Vector2(48, 48))
		print("card ", i, " icon=", ok, " elem=", wd.get("element"))


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames in MARKS:
		var img: Image = root.get_texture().get_image()
		img.save_png(OUT % _frames)
		print("shot ", _frames)
	if _frames >= MARKS[-1] + 1:
		return true
	return false
