extends SceneTree
## 自检：12 个符号能否加载、icon_tex 是否指向 16px 图。

const IDS := ["fire_slash", "frost_slash", "holy_slash", "shadow_slash", "iron_slash",
	"frost", "poison", "venom_bite", "holy_bolt", "ice_crystal", "dawn_light", "burn"]

var _done := false


func _process(_d: float) -> bool:
	if _done:
		return true
	_done = true
	for id in IDS:
		var path := "res://resources/symbols/%s.tres" % id
		var s: Resource = load(path)
		if s == null:
			print("FAIL load ", id)
			continue
		var tex = s.get("icon_tex")
		var info := "none"
		if tex is Texture2D:
			info = "%dx%d %s" % [tex.get_width(), tex.get_height(), tex.resource_path.get_file()]
		print("%-14s label=%-6s kind=%-8s icon=%s" % [id, str(s.get("label")), str(s.get("kind")), info])
	return true
