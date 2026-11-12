extends SceneTree
## 临时演示：整备副屏武器行接入元素图标后的样式（Button.icon + 多行文本）。

const OUT := "res://.workbuddy/art_trials/icons/row_%d.png"
const MARKS := [30, 90]

var _f := 0


func _initialize() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.11, 0.16)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var btn_scene: PackedScene = load("res://scenes/ui/ui_button.tscn")
	var rows := [
		["res://resources/weapon_templates/fire_sword.tres", "余烬长剑", "🗡️ 火焰斩 灼烧\n攻18 火 · 命中92%"],
		["res://resources/weapon_templates/absolute_zero.tres", "绝对零度", "🗡️ 冰锥 冻结\n攻20 冰 · 命中88%"],
		["res://resources/weapon_templates/plague_reaper.tres", "瘟疫收割者", "🗡️ 毒雾 腐蚀\n攻24 毒 · 命中85%"],
		["res://resources/weapon_templates/iron_sword.tres", "铁剑", "🗡️ 斩击\n攻12 中 · 命中95%"],
	]
	for i in rows.size():
		var wd: Resource = load(rows[i][0])
		var b: Button = btn_scene.instantiate()
		b.position = Vector2(20, 20 + i * 40)
		b.custom_minimum_size = Vector2(300, 34)
		b.add_theme_constant_override("line_spacing", 0)
		b.text = "\n".join([rows[i][1], rows[i][2]])
		var ico := WeaponIcons.element_icon(String(wd.get("element")))
		if ico != null:
			b.icon = ico
			b.expand_icon = false
		root.add_child(b)


func _process(_delta: float) -> bool:
	_f += 1
	if _f in MARKS:
		root.get_texture().get_image().save_png(OUT % _f)
		print("shot ", _f)
	if _f > MARKS[-1]:
		return true
	return false
